-- DEFINITIVE FIX for batch_update_lessons function
-- This migration resolves the "column reference contract_id is ambiguous" error
-- by dropping ALL existing versions and creating the correct one

BEGIN;

-- =====================================================
-- 1. DROP ALL EXISTING FUNCTIONS AND DEPENDENCIES
-- =====================================================

-- Drop the function with CASCADE to remove all dependencies
DROP FUNCTION IF EXISTS batch_update_lessons(jsonb) CASCADE;

-- =====================================================
-- 2. CREATE THE DEFINITIVE CORRECT FUNCTION
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
  array_length_val integer;
  i integer;
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

      -- Update the lesson with EXPLICIT table aliases to avoid ambiguity
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
      
      -- Update contract attendance count with EXPLICIT table aliases
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
            jsonb_agg(l.date ORDER BY l.lesson_number) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL),
            '[]'::jsonb
          )
          FROM lessons l 
          WHERE l.contract_id = c.id
        ),
        updated_at = now()
      WHERE c.id = contract_id_val;
      
      -- Check if contract should be marked as completed
      DECLARE
        completed_lessons integer := 0;
        excluded_lessons integer := 0;
        total_lessons integer := 0;
        should_complete boolean := false;
      BEGIN
        SELECT 
          COUNT(*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL),
          COUNT(*) FILTER (WHERE l.is_available = false),
          COUNT(*)
        INTO 
          completed_lessons,
          excluded_lessons,
          total_lessons
        FROM lessons l
        WHERE l.contract_id = contract_id_val;
        
        should_complete := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);
        
        -- Update contract status if it should be completed
        IF should_complete THEN
          UPDATE contracts c
          SET status = 'completed', updated_at = now()
          WHERE c.id = contract_id_val AND c.status = 'active';
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

-- =====================================================
-- 3. GRANT PERMISSIONS
-- =====================================================

GRANT EXECUTE ON FUNCTION batch_update_lessons(jsonb) TO authenticated;

-- =====================================================
-- 4. VERIFICATION QUERY
-- =====================================================

-- Verify the function was created correctly
DO $$
DECLARE
    func_exists boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_proc p 
        JOIN pg_namespace n ON n.oid = p.pronamespace 
        WHERE n.nspname = 'public' 
        AND p.proname = 'batch_update_lessons'
        AND p.proargtypes = ARRAY['jsonb'::regtype]
    ) INTO func_exists;
    
    IF func_exists THEN
        RAISE NOTICE 'SUCCESS: batch_update_lessons function created successfully';
    ELSE
        RAISE EXCEPTION 'FAILED: batch_update_lessons function was not created';
    END IF;
END $$;

COMMIT;
