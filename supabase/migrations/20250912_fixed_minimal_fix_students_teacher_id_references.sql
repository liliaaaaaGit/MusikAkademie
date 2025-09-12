-- MINIMAL FIX: Only fix broken students.teacher_id references
-- This migration fixes ONLY the specific broken references without rewriting everything
-- Goal: Fix the ambiguous contract_id error by fixing the root cause (broken s.teacher_id references)

BEGIN;

-- 1) Fix the update_contract_attendance trigger function (this is likely the main culprit)
-- This function runs after every lesson update and might have broken references

-- First, let's check if this function exists and what it looks like
DO $$
DECLARE
    func_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' 
        AND p.proname = 'update_contract_attendance'
        AND p.proargtypes = '{}'
    ) INTO func_exists;
    
    IF func_exists THEN
        RAISE NOTICE 'Found update_contract_attendance function - will fix it';
    ELSE
        RAISE NOTICE 'update_contract_attendance function not found';
    END IF;
END $$;

-- Drop and recreate the update_contract_attendance function with correct references
DROP FUNCTION IF EXISTS update_contract_attendance() CASCADE;

CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_available integer := 0;
  available_lessons integer := 0;
  contract_id_val uuid;
  lesson_dates jsonb := '[]'::jsonb;
BEGIN
  contract_id_val := COALESCE(NEW.contract_id, OLD.contract_id);
  
  -- Count available lessons and completed ones with explicit table aliases
  SELECT 
    COUNT(*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL),
    COUNT(*) FILTER (WHERE l.is_available = true),
    COALESCE(jsonb_agg(l.date ORDER BY l.lesson_number) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL), '[]'::jsonb)
  INTO 
    completed_available,
    available_lessons,
    lesson_dates
  FROM lessons l
  WHERE l.contract_id = contract_id_val;
  
  -- Update the contract with explicit table aliases
  UPDATE contracts c
  SET 
    attendance_count = completed_available || '/' || available_lessons,
    attendance_dates = lesson_dates,
    updated_at = now()
  WHERE c.id = contract_id_val;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger
DROP TRIGGER IF EXISTS trigger_update_contract_attendance_on_lesson_change ON lessons;
CREATE TRIGGER trigger_update_contract_attendance_on_lesson_change
  AFTER INSERT OR UPDATE OR DELETE ON lessons
  FOR EACH ROW EXECUTE FUNCTION update_contract_attendance();

-- Grant permissions
GRANT EXECUTE ON FUNCTION update_contract_attendance() TO authenticated;

-- 2) Fix any RLS policies that might reference students.teacher_id
-- Check if there are any broken policies and fix only those

-- Fix the specific RLS policy that was identified as problematic
DROP POLICY IF EXISTS "Teachers can delete contracts of their students" ON contracts;
CREATE POLICY "Teachers can delete contracts of their students" 
ON contracts FOR DELETE TO authenticated 
USING (
  (get_user_role() = 'admin') OR 
  ((get_user_role() = 'teacher') AND (
    EXISTS (
      SELECT 1 
      FROM contracts c
      LEFT JOIN teachers t ON c.teacher_id = t.id
      LEFT JOIN profiles p ON t.profile_id = p.id
      WHERE c.id = contracts.id AND p.id = auth.uid()
    )
  ))
);

-- 3) Fix any notification functions that might still reference students.teacher_id
-- Only fix the ones that are actually broken

-- Check and fix notify_contract_completion if it exists and is broken
DO $$
DECLARE
    func_exists boolean;
    func_body text;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' 
        AND p.proname = 'notify_contract_completion'
        AND p.proargtypes = '{}'
    ) INTO func_exists;
    
    IF func_exists THEN
        -- Get the function body to check if it has broken references
        SELECT prosrc INTO func_body
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' 
        AND p.proname = 'notify_contract_completion'
        AND p.proargtypes = '{}';
        
        IF func_body ILIKE '%students.teacher_id%' OR func_body ILIKE '%s.teacher_id%' THEN
            RAISE NOTICE 'Found broken notify_contract_completion function - fixing it';
            
            -- Drop and recreate with correct references using dynamic SQL
            DROP FUNCTION IF EXISTS notify_contract_completion() CASCADE;
            
            EXECUTE '
            CREATE OR REPLACE FUNCTION notify_contract_completion()
            RETURNS TRIGGER
            LANGUAGE plpgsql
            SECURITY DEFINER
            AS $func$
            DECLARE
              student_name text;
              teacher_name text;
              student_id_val uuid;
              teacher_id_val uuid;
              should_notify boolean := false;
            BEGIN
              -- Check for manual status change from ''active'' to ''completed''
              IF OLD.status = ''active'' AND NEW.status = ''completed'' THEN
                should_notify := true;
              END IF;
              
              -- Check for attendance completion based on available lessons
              IF OLD.attendance_count IS DISTINCT FROM NEW.attendance_count THEN
                DECLARE
                  completed_lessons integer := 0;
                  available_lessons integer := 0;
                BEGIN
                  SELECT 
                    COUNT(*) FILTER (WHERE l.date IS NOT NULL AND l.is_available = true),
                    COUNT(*) FILTER (WHERE l.is_available = true)
                  INTO 
                    completed_lessons,
                    available_lessons
                  FROM lessons l
                  WHERE l.contract_id = NEW.id;
                  
                  -- Check if all available lessons are completed
                  IF completed_lessons > 0 AND available_lessons > 0 AND
                     completed_lessons = available_lessons AND
                     NEW.status = ''active'' THEN
                    should_notify := true;
                  END IF;
                END;
              END IF;
              
              -- Create notification if conditions are met
              IF should_notify THEN
                -- Get student and teacher information using contracts.teacher_id (FIXED)
                SELECT 
                  s.name,
                  s.id,
                  t.name,
                  t.id
                INTO 
                  student_name,
                  student_id_val,
                  teacher_name,
                  teacher_id_val
                FROM students s
                LEFT JOIN teachers t ON t.id = NEW.teacher_id
                WHERE s.id = NEW.student_id;
                
                -- Insert notification
                INSERT INTO notifications (
                  type,
                  contract_id,
                  teacher_id,
                  student_id,
                  message,
                  is_read,
                  created_at,
                  updated_at
                ) VALUES (
                  ''contract_completed'',
                  NEW.id,
                  teacher_id_val,
                  student_id_val,
                  format(''Contract completed for student %s'', COALESCE(student_name, ''Unknown'')),
                  false,
                  now(),
                  now()
                );
              END IF;
              
              RETURN NEW;
            END;
            $func$;';
            
            -- Recreate the trigger
            DROP TRIGGER IF EXISTS trigger_contract_completion ON contracts;
            CREATE TRIGGER trigger_contract_completion
              AFTER UPDATE ON contracts
              FOR EACH ROW EXECUTE FUNCTION notify_contract_completion();
              
            GRANT EXECUTE ON FUNCTION notify_contract_completion() TO authenticated;
        ELSE
            RAISE NOTICE 'notify_contract_completion function is already correct';
        END IF;
    ELSE
        RAISE NOTICE 'notify_contract_completion function not found';
    END IF;
END $$;

-- 4) Final verification - check if there are any remaining broken references
DO $$
DECLARE
    remaining_count integer := 0;
BEGIN
    -- Check for any remaining functions with students.teacher_id references
    SELECT COUNT(*) INTO remaining_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
    AND p.prosrc ILIKE '%students.teacher_id%';
    
    IF remaining_count > 0 THEN
        RAISE WARNING 'WARNING: % functions still reference students.teacher_id', remaining_count;
    ELSE
        RAISE NOTICE 'SUCCESS: No functions reference students.teacher_id anymore!';
    END IF;
END $$;

COMMIT;
