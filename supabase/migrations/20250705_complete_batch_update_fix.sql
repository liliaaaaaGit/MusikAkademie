-- Complete fix for batch_update_lessons function
-- This migration completely recreates the function to fix the ambiguous column reference

BEGIN;

-- =====================================================
-- 1. DROP ALL EXISTING FUNCTIONS THAT MIGHT CONFLICT
-- =====================================================

-- Drop the batch_update_lessons function completely
DROP FUNCTION IF EXISTS batch_update_lessons(jsonb);

-- =====================================================
-- 2. CREATE A CLEAN VERSION OF THE FUNCTION
-- =====================================================

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
  FOR i IN 1..array_length(contract_ids, 1)
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

  -- Return result
  RETURN jsonb_build_object(
    'success', error_count = 0,
    'success_count', success_count,
    'error_count', error_count,
    'errors', error_messages
  );
END;
$$;

-- =====================================================
-- 3. GRANT EXECUTE PERMISSIONS
-- =====================================================

GRANT EXECUTE ON FUNCTION batch_update_lessons(jsonb) TO authenticated;

-- =====================================================
-- 4. VERIFY THE FUNCTION WAS CREATED
-- =====================================================

-- This will show if the function exists and its signature
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'batch_update_lessons' 
    AND proargtypes = ARRAY['jsonb'::regtype]
  ) THEN
    RAISE EXCEPTION 'Function batch_update_lessons was not created successfully';
  END IF;
END $$;

COMMIT; 