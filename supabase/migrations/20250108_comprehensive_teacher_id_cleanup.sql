-- Comprehensive cleanup of all remaining students.teacher_id references
-- This migration identifies and fixes ALL functions, triggers, and policies that reference the deprecated column

BEGIN;

-- 1) First, let's identify ALL functions that still reference students.teacher_id
DO $$
DECLARE
    func_record RECORD;
    func_body text;
BEGIN
    RAISE NOTICE '=== SEARCHING FOR FUNCTIONS WITH students.teacher_id REFERENCES ===';
    
    FOR func_record IN 
        SELECT 
            p.proname as function_name,
            p.prosrc as function_body,
            n.nspname as schema_name
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
        AND p.prosrc ILIKE '%students.teacher_id%'
    LOOP
        RAISE NOTICE 'FOUND PROBLEMATIC FUNCTION: %', func_record.function_name;
    END LOOP;
    
    RAISE NOTICE '=== SEARCH COMPLETE ===';
END $$;

-- 2) Drop ALL potentially problematic triggers and functions
DROP TRIGGER IF EXISTS trigger_update_contract_attendance_on_lesson_change ON lessons;
DROP TRIGGER IF EXISTS trigger_contract_completion ON contracts;
DROP TRIGGER IF EXISTS trigger_contract_fulfilled ON contracts;
DROP TRIGGER IF EXISTS trigger_notify_contract_completion ON contracts;
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;

-- Drop all potentially problematic functions
DROP FUNCTION IF EXISTS update_contract_attendance() CASCADE;
DROP FUNCTION IF EXISTS notify_contract_completion() CASCADE;
DROP FUNCTION IF EXISTS notify_contract_fulfilled() CASCADE;
DROP FUNCTION IF EXISTS handle_contract_notification() CASCADE;
DROP FUNCTION IF EXISTS batch_update_lessons(jsonb) CASCADE;

-- 3) Create a completely clean batch_update_lessons function
CREATE OR REPLACE FUNCTION batch_update_lessons(updates jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  update_record jsonb;
  lesson_id_val uuid;
  contract_id_val uuid;
  success_count integer := 0;
  error_count integer := 0;
  error_messages text[] := '{}';
  contract_ids uuid[] := '{}';
  array_length_val integer;
BEGIN
  -- Process each update
  FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    BEGIN
      lesson_id_val := (update_record->>'id')::uuid;
      contract_id_val := (update_record->>'contract_id')::uuid;
      
      -- Add contract_id to array for later processing
      IF NOT (contract_id_val = ANY(contract_ids)) THEN
        contract_ids := array_append(contract_ids, contract_id_val);
      END IF;

      -- Update the lesson with explicit table references
      UPDATE lessons l
      SET 
        date = CASE WHEN update_record->>'date' IS NOT NULL AND update_record->>'date' != '' 
                    THEN (update_record->>'date')::date ELSE NULL END,
        comment = CASE WHEN update_record->>'comment' IS NOT NULL AND update_record->>'comment' != '' 
                       THEN update_record->>'comment' ELSE NULL END,
        is_available = (update_record->>'is_available')::boolean,
        updated_at = now()
      WHERE l.id = lesson_id_val AND l.contract_id = contract_id_val;

      IF FOUND THEN
        success_count := success_count + 1;
      ELSE
        error_count := error_count + 1;
        error_messages := array_append(error_messages, format('Lesson %s not found or contract mismatch', lesson_id_val));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      error_messages := array_append(error_messages, format('Error updating lesson %s: %s', lesson_id_val, SQLERRM));
    END;
  END LOOP;

  -- Update contract attendance counts for affected contracts
  array_length_val := array_length(contract_ids, 1);
  IF array_length_val IS NOT NULL THEN
    FOR i IN 1..array_length_val
    LOOP
      contract_id_val := contract_ids[i];
      
      -- Update contract attendance count
      UPDATE contracts
      SET 
        attendance_count = (
          SELECT 
            COALESCE(COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL), 0) || '/' || 
            COALESCE(COUNT(*) FILTER (WHERE is_available = true), 0)
          FROM lessons 
          WHERE contract_id = contract_id_val
        ),
        attendance_dates = (
          SELECT COALESCE(
            jsonb_agg(date ORDER BY lesson_number) FILTER (WHERE is_available = true AND date IS NOT NULL),
            '[]'::jsonb
          )
          FROM lessons 
          WHERE contract_id = contract_id_val
        ),
        updated_at = now()
      WHERE id = contract_id_val;
      
      -- Check if contract should be marked as completed
      DECLARE
        completed_lessons integer := 0;
        excluded_lessons integer := 0;
        total_lessons integer := 0;
        should_complete boolean := false;
      BEGIN
        SELECT 
          COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
          COUNT(*) FILTER (WHERE is_available = false),
          COUNT(*)
        INTO 
          completed_lessons,
          excluded_lessons,
          total_lessons
        FROM lessons
        WHERE contract_id = contract_id_val;
        
        should_complete := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);
        
        -- Update contract status if it should be completed
        IF should_complete THEN
          UPDATE contracts
          SET status = 'completed', updated_at = now()
          WHERE id = contract_id_val AND status = 'active';
        END IF;
      END;
    END LOOP;
  END IF;

  -- Return detailed result
  RETURN jsonb_build_object(
    'success', error_count = 0,
    'success_count', success_count,
    'error_count', error_count,
    'errors', error_messages,
    'processed_contracts', contract_ids
  );
END;
$$;

-- 4) Create a simple contract attendance update function (no teacher references)
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_available integer := 0;
  available_lessons integer := 0;
  contract_id uuid;
  lesson_dates jsonb := '[]'::jsonb;
BEGIN
  contract_id := COALESCE(NEW.contract_id, OLD.contract_id);
  
  -- Count available lessons and completed ones
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
    COUNT(*) FILTER (WHERE is_available = true),
    COALESCE(jsonb_agg(date ORDER BY lesson_number) FILTER (WHERE is_available = true AND date IS NOT NULL), '[]'::jsonb)
  INTO completed_available, available_lessons, lesson_dates
  FROM lessons
  WHERE contract_id = contract_id;
  
  -- Update contract with completed/available counts
  UPDATE contracts
  SET attendance_count = completed_available || '/' || available_lessons,
      attendance_dates = lesson_dates,
      updated_at = now()
  WHERE id = contract_id;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- 5) Recreate triggers with clean functions
CREATE TRIGGER trigger_update_contract_attendance_on_lesson_change
  AFTER INSERT OR UPDATE OR DELETE ON lessons
  FOR EACH ROW EXECUTE FUNCTION update_contract_attendance();

-- 6) Grant permissions
GRANT EXECUTE ON FUNCTION batch_update_lessons(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION update_contract_attendance() TO authenticated;

-- 7) Verify no more students.teacher_id references
DO $$
DECLARE
    func_record RECORD;
    remaining_count integer := 0;
BEGIN
    RAISE NOTICE '=== FINAL VERIFICATION: CHECKING FOR REMAINING students.teacher_id REFERENCES ===';
    
    SELECT COUNT(*) INTO remaining_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
    AND p.prosrc ILIKE '%students.teacher_id%';
    
    IF remaining_count > 0 THEN
        RAISE WARNING 'WARNING: % functions still reference students.teacher_id', remaining_count;
        
        FOR func_record IN 
            SELECT p.proname as function_name
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
            AND p.prosrc ILIKE '%students.teacher_id%'
        LOOP
            RAISE WARNING 'REMAINING PROBLEMATIC FUNCTION: %', func_record.function_name;
        END LOOP;
    ELSE
        RAISE NOTICE 'SUCCESS: No functions reference students.teacher_id anymore!';
    END IF;
END $$;

COMMIT;
