-- Fix lesson tracking functions that still reference students.teacher_id
-- This migration updates any remaining functions to use contracts.teacher_id instead

BEGIN;

-- 1) Check if there are any functions still referencing students.teacher_id
DO $$
DECLARE
    func_record RECORD;
    func_body text;
BEGIN
    -- Find all functions that might reference students.teacher_id
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
        RAISE NOTICE 'Found function % that references students.teacher_id', func_record.function_name;
    END LOOP;
END $$;

-- 2) Update batch_update_lessons function to ensure it doesn't reference students.teacher_id
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
  contract_record RECORD;
  should_complete boolean := false;
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
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

      -- Update the lesson with proper table reference
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

  -- Process contracts for completion status
  array_length_val := array_length(contract_ids, 1);
  IF array_length_val IS NOT NULL THEN
    FOR i IN 1..array_length_val
    LOOP
      contract_id_val := contract_ids[i];
      
      -- Get contract details using contracts table only
      SELECT * INTO contract_record
      FROM contracts
      WHERE contracts.id = contract_id_val;
      
      IF FOUND THEN
        -- Check if contract should be marked as completed
        SELECT 
          COUNT(*) FILTER (WHERE lessons.is_available = true AND lessons.date IS NOT NULL),
          COUNT(*) FILTER (WHERE lessons.is_available = false),
          COUNT(*)
        INTO 
          completed_lessons,
          excluded_lessons,
          total_lessons
        FROM lessons
        WHERE lessons.contract_id = contract_id_val;
        
        should_complete := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);
        
        -- Update contract status if it should be completed
        IF should_complete AND contract_record.status = 'active' THEN
          UPDATE contracts
          SET status = 'completed', updated_at = now()
          WHERE contracts.id = contract_id_val;
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'success', error_count = 0,
    'success_count', success_count,
    'error_count', error_count,
    'errors', error_messages
  );
END;
$$;

-- 3) Grant execute permissions
GRANT EXECUTE ON FUNCTION batch_update_lessons(jsonb) TO authenticated;

COMMIT;
