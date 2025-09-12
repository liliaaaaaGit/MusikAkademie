-- FINAL FIX for batch_update_lessons function
-- This migration definitively fixes the ambiguous contract_id and boolean casting issues
-- It will replace ANY existing version of the function

BEGIN;

-- Drop ALL existing versions with CASCADE to ensure clean replacement
DROP FUNCTION IF EXISTS batch_update_lessons(jsonb) CASCADE;

-- Create the definitive, hardened function
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
  i integer;
  current_contract_id uuid;

  -- completion counters
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
  should_complete boolean := false;
  contract_status text;

  -- temp parsed values
  date_raw text;
  comment_raw text;
  is_available_raw text;
  is_available_val boolean;
BEGIN
  -- Process each lesson update
  FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    BEGIN
      lesson_id_val := NULLIF(update_record->>'id','')::uuid;

      -- 1) derive contract_id robustly
      contract_id_val := NULLIF(update_record->>'contract_id','')::uuid;
      IF contract_id_val IS NULL AND lesson_id_val IS NOT NULL THEN
        SELECT l.contract_id INTO contract_id_val
        FROM lessons l
        WHERE l.id = lesson_id_val;
      END IF;

      IF lesson_id_val IS NULL OR contract_id_val IS NULL THEN
        error_count := error_count + 1;
        error_messages := array_append(error_messages,
          format('Invalid ids in update (id: %, contract_id: %)', update_record->>'id', update_record->>'contract_id'));
        CONTINUE;
      END IF;

      -- collect contract ids
      IF NOT (contract_id_val = ANY(contract_ids)) THEN
        contract_ids := array_append(contract_ids, contract_id_val);
      END IF;

      -- 2) parse fields safely
      date_raw := update_record->>'date';
      comment_raw := update_record->>'comment';
      is_available_raw := update_record->>'is_available';

      -- Safe boolean parsing: handle all possible values
      IF is_available_raw IS NULL OR is_available_raw = '' THEN
        -- If not provided, keep current value
        SELECT l.is_available INTO is_available_val FROM lessons l WHERE l.id = lesson_id_val;
      ELSE
        -- Parse boolean safely
        BEGIN
          is_available_val := (is_available_raw)::boolean;
        EXCEPTION WHEN OTHERS THEN
          -- If cast fails, try string parsing
          is_available_val := CASE lower(trim(is_available_raw))
            WHEN 'true'  THEN true
            WHEN 't'     THEN true
            WHEN '1'     THEN true
            WHEN 'yes'   THEN true
            WHEN 'false' THEN false
            WHEN 'f'     THEN false
            WHEN '0'     THEN false
            WHEN 'no'    THEN false
            ELSE true  -- default to true if we can't parse
          END;
        END;
      END IF;

      -- 3) do the update (fully qualified with explicit table aliases)
      UPDATE lessons l
      SET
        date = CASE
                 WHEN date_raw IS NOT NULL AND date_raw <> '' THEN date_raw::date
                 ELSE NULL
               END,
        comment = CASE
                    WHEN comment_raw IS NOT NULL AND comment_raw <> '' THEN comment_raw
                    ELSE NULL
                  END,
        is_available = is_available_val,
        updated_at = now()
      WHERE l.id = lesson_id_val
        AND l.contract_id = contract_id_val;

      IF FOUND THEN
        success_count := success_count + 1;
      ELSE
        error_count := error_count + 1;
        error_messages := array_append(error_messages,
          format('Lesson %s not found or contract mismatch (%s)', lesson_id_val, contract_id_val));
      END IF;

    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      error_messages := array_append(error_messages,
        format('Error updating lesson %s: %s', lesson_id_val, SQLERRM));
    END;
  END LOOP;

  -- Update contracts & completion status for affected contracts
  array_length_val := array_length(contract_ids, 1);
  IF array_length_val IS NOT NULL THEN
    FOR i IN 1..array_length_val LOOP
      current_contract_id := contract_ids[i];

      -- Update contract attendance count with explicit table aliases
      UPDATE contracts c
      SET
        attendance_count = (
          SELECT
            COALESCE(COUNT(*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL), 0) || '/' ||
            COALESCE(COUNT(*) FILTER (WHERE l.is_available = true), 0)
          FROM lessons l
          WHERE l.contract_id = c.id
        ),
        attendance_dates = (
          SELECT COALESCE(
            jsonb_agg(l.date ORDER BY l.lesson_number)
              FILTER (WHERE l.is_available = true AND l.date IS NOT NULL),
            '[]'::jsonb
          )
          FROM lessons l
          WHERE l.contract_id = c.id
        ),
        updated_at = now()
      WHERE c.id = current_contract_id;

      -- Check contract completion
      SELECT status INTO contract_status
      FROM contracts c
      WHERE c.id = current_contract_id;

      IF contract_status = 'active' THEN
        SELECT
          COUNT(*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL),
          COUNT(*) FILTER (WHERE l.is_available = false),
          COUNT(*)
        INTO completed_lessons, excluded_lessons, total_lessons
        FROM lessons l
        WHERE l.contract_id = current_contract_id;

        should_complete := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);

        IF should_complete THEN
          UPDATE contracts c
          SET status = 'completed',
              completed_at = now(),
              updated_at = now()
          WHERE c.id = current_contract_id
            AND c.status = 'active';
        END IF;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', error_count = 0,
    'success_count', success_count,
    'error_count', error_count,
    'errors', error_messages,
    'processed_contracts', contract_ids,
    'contracts_updated', array_length(contract_ids, 1)
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION batch_update_lessons(jsonb) TO authenticated;

-- Create the missing check_contract_completion_after_lessons function
DROP FUNCTION IF EXISTS check_contract_completion_after_lessons(uuid) CASCADE;

CREATE OR REPLACE FUNCTION check_contract_completion_after_lessons(contract_id_param uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
  available_lessons integer := 0;
  should_complete boolean := false;
  contract_record RECORD;
  result_message text;
BEGIN
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts c
  WHERE c.id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Contract not found: ' || contract_id_param,
      'contract_id', contract_id_param
    );
  END IF;
  
  -- Only check completion for active contracts
  IF contract_record.status != 'active' THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Contract is not active, skipping completion check',
      'contract_id', contract_id_param,
      'current_status', contract_record.status
    );
  END IF;
  
  -- Get accurate lesson counts with explicit table aliases
  SELECT 
    COUNT(*) FILTER (WHERE l.date IS NOT NULL AND l.is_available = true),
    COUNT(*) FILTER (WHERE l.is_available = true),
    COUNT(*),
    COUNT(*) FILTER (WHERE l.is_available = false)
  INTO 
    completed_lessons,
    available_lessons,
    total_lessons,
    excluded_lessons
  FROM lessons l
  WHERE l.contract_id = contract_id_param;
  
  -- Determine if contract should be completed
  should_complete := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);
  
  -- Update contract status if it should be completed
  IF should_complete THEN
    UPDATE contracts c
    SET 
      status = 'completed',
      completed_at = now(),
      updated_at = now()
    WHERE c.id = contract_id_param AND c.status = 'active';
    
    result_message := format(
      'Contract marked as completed. Lessons: %s completed of %s available (total: %s, excluded: %s)',
      completed_lessons, available_lessons, total_lessons, excluded_lessons
    );
  ELSE
    result_message := format(
      'Contract not yet completed. Lessons: %s completed of %s available (total: %s, excluded: %s)',
      completed_lessons, available_lessons, total_lessons, excluded_lessons
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', result_message,
    'contract_id', contract_id_param,
    'completed_lessons', completed_lessons,
    'available_lessons', available_lessons,
    'total_lessons', total_lessons,
    'excluded_lessons', excluded_lessons,
    'should_complete', should_complete,
    'was_completed', should_complete
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION check_contract_completion_after_lessons(uuid) TO authenticated;

-- Verification
DO $$
DECLARE 
  batch_func_exists boolean;
  completion_func_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' 
    AND p.proname = 'batch_update_lessons'
    AND p.pronargs = 1
  ) INTO batch_func_exists;
  
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' 
    AND p.proname = 'check_contract_completion_after_lessons'
    AND p.pronargs = 1
  ) INTO completion_func_exists;
  
  IF batch_func_exists AND completion_func_exists THEN
    RAISE NOTICE 'SUCCESS: Both batch_update_lessons and check_contract_completion_after_lessons functions created successfully';
  ELSE
    RAISE EXCEPTION 'FAILED: Functions not created properly - batch: %, completion: %', batch_func_exists, completion_func_exists;
  END IF;
END $$;

COMMIT;
