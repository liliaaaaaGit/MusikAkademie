-- Fix array_length error in batch_update_lessons function
-- This migration fixes the "upper bound of FOR loop cannot be null" error

BEGIN;

-- Drop and recreate the function with proper array handling
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

      -- Update the lesson with explicit table references
      UPDATE lessons 
      SET 
        date = CASE WHEN update_record->>'date' IS NOT NULL AND update_record->>'date' != '' 
                    THEN (update_record->>'date')::date ELSE NULL END,
        comment = CASE WHEN update_record->>'comment' IS NOT NULL AND update_record->>'comment' != '' 
                       THEN update_record->>'comment' ELSE NULL END,
        is_available = (update_record->>'is_available')::boolean,
        updated_at = now()
      WHERE lessons.id = lesson_id_val AND lessons.contract_id = contract_id_val;

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

  -- Check contract completion for each affected contract
  -- Get array length safely
  array_length_val := array_length(contract_ids, 1);
  
  -- Only process if we have contracts to check
  IF array_length_val IS NOT NULL AND array_length_val > 0 THEN
    FOR i IN 1..array_length_val
    LOOP
      contract_id_val := contract_ids[i];
      
      -- Get contract details
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

COMMIT; 