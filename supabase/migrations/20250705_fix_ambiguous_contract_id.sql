-- Fix ambiguous contract_id reference in batch_update_lessons function
-- This migration fixes the SQL error when saving lesson progress

BEGIN;

-- Drop and recreate the batch lesson update function with proper table aliases
CREATE OR REPLACE FUNCTION batch_update_lessons(updates jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  update_record jsonb;
  lesson_id uuid;
  contract_id uuid;
  success_count integer := 0;
  error_count integer := 0;
  error_messages text[] := '{}';
  contract_ids uuid[] := '{}';
  contract_record RECORD;
  should_complete boolean := false;
BEGIN
  -- Process each update
  FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    BEGIN
      lesson_id := (update_record->>'id')::uuid;
      contract_id := (update_record->>'contract_id')::uuid;
      
      -- Add contract_id to array for later processing
      IF NOT (contract_id = ANY(contract_ids)) THEN
        contract_ids := array_append(contract_ids, contract_id);
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
      WHERE l.id = lesson_id AND l.contract_id = contract_id;

      IF FOUND THEN
        success_count := success_count + 1;
      ELSE
        error_count := error_count + 1;
        error_messages := array_append(error_messages, format('Lesson %s not found or contract mismatch', lesson_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      error_messages := array_append(error_messages, format('Error updating lesson %s: %s', lesson_id, SQLERRM));
    END;
  END LOOP;

  -- Check contract completion for each affected contract
  FOR i IN 1..array_length(contract_ids, 1)
  LOOP
    contract_id := contract_ids[i];
    
    -- Get contract details with proper table reference
    SELECT c.* INTO contract_record
    FROM contracts c
    WHERE c.id = contract_id;
    
    IF FOUND THEN
      -- Check if contract should be marked as completed with proper table aliases
      WITH lesson_counts AS (
        SELECT 
          COUNT(*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) as completed_lessons,
          COUNT(*) FILTER (WHERE l.is_available = false) as excluded_lessons,
          COUNT(*) as total_lessons
        FROM lessons l
        WHERE l.contract_id = contract_id
      )
      SELECT 
        (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0)
      INTO should_complete
      FROM lesson_counts;
      
      -- Update contract status if it should be completed
      IF should_complete AND contract_record.status = 'active' THEN
        UPDATE contracts c
        SET status = 'completed', updated_at = now()
        WHERE c.id = contract_id;
      END IF;
    END IF;
  END LOOP;

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