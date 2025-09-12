-- Fix batch_update_lessons function to properly handle final lesson completion
-- This migration addresses the issue where the final lesson that completes a contract is not saved
-- and ensures proper contract completion logic

BEGIN;

-- =====================================================
-- 1. DROP ALL EXISTING FUNCTIONS AND DEPENDENCIES
-- =====================================================

-- Drop the function with CASCADE to remove all dependencies
DROP FUNCTION IF EXISTS batch_update_lessons(jsonb) CASCADE;

-- =====================================================
-- 2. CREATE THE CORRECTED FUNCTION
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
  current_contract_id uuid;
  
  -- Variables for contract completion check
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
  should_complete boolean := false;
  contract_status text;
BEGIN
  -- Process each lesson update
  FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    BEGIN
      lesson_id_val := (update_record->>'id')::uuid;
      contract_id_val := (update_record->>'contract_id')::uuid;
      
      -- Validate inputs
      IF lesson_id_val IS NULL OR contract_id_val IS NULL THEN
        error_count := error_count + 1;
        error_messages := array_append(error_messages, format('Invalid lesson_id or contract_id in update: %s', update_record));
        CONTINUE;
      END IF;
      
      -- Add contract_id to array for later processing (avoid duplicates)
      IF NOT (contract_id_val = ANY(contract_ids)) THEN
        contract_ids := array_append(contract_ids, contract_id_val);
      END IF;

      -- Update the lesson with EXPLICIT table aliases to avoid ambiguity
      UPDATE lessons l
      SET 
        date = CASE 
          WHEN update_record->>'date' IS NOT NULL AND update_record->>'date' != '' 
          THEN (update_record->>'date')::date 
          ELSE NULL 
        END,
        comment = CASE 
          WHEN update_record->>'comment' IS NOT NULL AND update_record->>'comment' != '' 
          THEN update_record->>'comment' 
          ELSE NULL 
        END,
        is_available = COALESCE((update_record->>'is_available')::boolean, true),
        updated_at = now()
      WHERE l.id = lesson_id_val AND l.contract_id = contract_id_val;

      -- Check if the update was successful
      IF FOUND THEN
        success_count := success_count + 1;
        
        -- Log successful update for debugging
        RAISE NOTICE 'Successfully updated lesson % for contract %', lesson_id_val, contract_id_val;
      ELSE
        error_count := error_count + 1;
        error_messages := array_append(error_messages, format('Lesson %s not found or contract mismatch for contract %s', lesson_id_val, contract_id_val));
        
        -- Log failed update for debugging
        RAISE NOTICE 'Failed to update lesson % for contract %', lesson_id_val, contract_id_val;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      error_messages := array_append(error_messages, format('Error updating lesson %s: %s', lesson_id_val, SQLERRM));
      
      -- Log exception for debugging
      RAISE NOTICE 'Exception updating lesson %: %', lesson_id_val, SQLERRM;
    END;
  END LOOP;

  -- Update contract attendance counts and check completion for each affected contract
  array_length_val := array_length(contract_ids, 1);
  IF array_length_val IS NOT NULL THEN
    FOR i IN 1..array_length_val
    LOOP
      current_contract_id := contract_ids[i];
      
      -- First, update contract attendance count with EXPLICIT table aliases
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
      WHERE c.id = current_contract_id;

      -- Then check if contract should be marked as completed
      -- Get current contract status first
      SELECT status INTO contract_status
      FROM contracts c
      WHERE c.id = current_contract_id;
      
      -- Only check completion for active contracts
      IF contract_status = 'active' THEN
        -- Count lessons for completion check
        SELECT 
          COUNT(*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL),
          COUNT(*) FILTER (WHERE l.is_available = false),
          COUNT(*)
        INTO 
          completed_lessons,
          excluded_lessons,
          total_lessons
        FROM lessons l
        WHERE l.contract_id = current_contract_id;
        
        -- Determine if contract should be completed
        should_complete := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);
        
        -- Log completion check for debugging
        RAISE NOTICE 'Contract % completion check: completed=%, excluded=%, total=%, should_complete=%', 
          current_contract_id, completed_lessons, excluded_lessons, total_lessons, should_complete;
        
        -- Update contract status if it should be completed
        IF should_complete THEN
          UPDATE contracts c
          SET 
            status = 'completed', 
            completed_at = now(),
            updated_at = now()
          WHERE c.id = current_contract_id AND c.status = 'active';
          
          -- Log completion for debugging
          RAISE NOTICE 'Contract % marked as completed', current_contract_id;
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- Log final result for debugging
  RAISE NOTICE 'Batch update completed: success=%, error=%, contracts_processed=%', 
    success_count, error_count, array_length(contract_ids, 1);

  -- Return detailed result
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
        AND p.pronargs = 1
    ) INTO func_exists;
    
    IF func_exists THEN
        RAISE NOTICE 'SUCCESS: batch_update_lessons function created successfully with enhanced debugging and completion logic';
    ELSE
        RAISE EXCEPTION 'FAILED: batch_update_lessons function was not created';
    END IF;
END $$;

COMMIT;
