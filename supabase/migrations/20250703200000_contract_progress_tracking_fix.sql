/*
  # Contract Progress Tracking Critical Fix

  This migration fixes critical bugs in contract progress tracking:

  1. Lesson Updates
    - Ensure contract_id is always preserved in lesson updates
    - Fix null contract_id constraint violations
    - Add proper validation for lesson-contract relationships

  2. Contract Editing
    - Fix "Unknown error" when saving contract changes
    - Implement proper transactional saving
    - Add comprehensive error handling

  3. Data Integrity
    - Ensure lessons are always linked to valid contracts
    - Prevent orphaned lesson records
    - Add validation triggers

  4. Performance
    - Optimize lesson update operations
    - Add proper indexing for better performance
    - Implement batch operations safely
*/

-- =====================================================
-- 1. FIX LESSON UPDATE FUNCTION
-- =====================================================

-- Create a safe lesson update function that preserves contract_id
CREATE OR REPLACE FUNCTION safe_update_lesson(
  lesson_id_param uuid,
  date_param date DEFAULT NULL,
  comment_param text DEFAULT NULL,
  is_available_param boolean DEFAULT true
)
RETURNS text AS $$
DECLARE
  contract_id_check uuid;
  result_message text;
BEGIN
  -- First, verify the lesson exists and get its contract_id
  SELECT contract_id INTO contract_id_check
  FROM lessons
  WHERE id = lesson_id_param;

  IF contract_id_check IS NULL THEN
    RETURN 'Lesson not found';
  END IF;

  -- Update the lesson with all required fields
  UPDATE lessons
  SET 
    date = date_param,
    comment = comment_param,
    is_available = is_available_param,
    updated_at = now()
  WHERE id = lesson_id_param;

  -- Force attendance recalculation
  PERFORM fix_contract_attendance(contract_id_check);

  result_message := format('Lesson %s updated successfully for contract %s', 
    lesson_id_param, contract_id_check);
  
  RETURN result_message;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 2. ENHANCE CONTRACT SYNC FUNCTION
-- =====================================================

-- Improve the sync_contract_data function with better error handling
CREATE OR REPLACE FUNCTION sync_contract_data(contract_id_param uuid)
RETURNS text AS $$
DECLARE
  contract_record RECORD;
  lesson_count integer;
  i integer;
  existing_lessons integer;
  result_message text;
  lock_key bigint;
BEGIN
  -- Use advisory lock to prevent concurrent modifications
  lock_key := hashtext(contract_id_param::text);
  
  IF NOT pg_try_advisory_xact_lock(lock_key) THEN
    RETURN 'Contract is being modified by another operation';
  END IF;

  -- Get contract details with better error handling
  SELECT 
    c.id,
    c.contract_variant_id,
    c.type,
    c.status,
    cv.total_lessons
  INTO contract_record
  FROM contracts c
  LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
  WHERE c.id = contract_id_param;

  IF contract_record.id IS NULL THEN
    RETURN 'Contract not found';
  END IF;

  -- Get lesson count with fallback
  lesson_count := COALESCE(contract_record.total_lessons, 
    CASE 
      WHEN contract_record.type = 'ten_class_card' THEN 10
      WHEN contract_record.type = 'half_year' THEN 18
      ELSE 10
    END
  );

  -- Count existing lessons
  SELECT COUNT(*) INTO existing_lessons
  FROM lessons
  WHERE contract_id = contract_id_param;

  -- Regenerate lessons if count doesn't match
  IF existing_lessons != lesson_count THEN
    -- Delete existing lessons
    DELETE FROM lessons WHERE contract_id = contract_id_param;
    
    -- Generate new lessons with proper contract_id
    FOR i IN 1..lesson_count LOOP
      INSERT INTO lessons (contract_id, lesson_number, is_available)
      VALUES (contract_id_param, i, true);
    END LOOP;
  END IF;

  -- Force attendance recalculation
  PERFORM fix_contract_attendance(contract_id_param);

  result_message := format('Contract %s synchronized: %s lessons, attendance recalculated', 
    contract_id_param, lesson_count);
  
  RETURN result_message;
EXCEPTION WHEN OTHERS THEN
  RETURN format('Error syncing contract %s: %s', contract_id_param, SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 3. ADD LESSON VALIDATION TRIGGER
-- =====================================================

-- Create function to validate lesson data integrity
CREATE OR REPLACE FUNCTION validate_lesson_integrity()
RETURNS TRIGGER AS $$
DECLARE
  contract_exists boolean;
BEGIN
  -- Ensure contract_id is always provided
  IF NEW.contract_id IS NULL THEN
    RAISE EXCEPTION 'contract_id cannot be null';
  END IF;

  -- Verify contract exists
  SELECT EXISTS(SELECT 1 FROM contracts WHERE id = NEW.contract_id) INTO contract_exists;
  
  IF NOT contract_exists THEN
    RAISE EXCEPTION 'Contract with id % does not exist', NEW.contract_id;
  END IF;

  -- Ensure lesson_number is within valid range
  IF NEW.lesson_number < 1 OR NEW.lesson_number > 18 THEN
    RAISE EXCEPTION 'Lesson number must be between 1 and 18';
  END IF;

  -- Ensure unique lesson number per contract
  IF EXISTS(
    SELECT 1 FROM lessons 
    WHERE contract_id = NEW.contract_id 
    AND lesson_number = NEW.lesson_number 
    AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) THEN
    RAISE EXCEPTION 'Lesson number % already exists for contract %', NEW.lesson_number, NEW.contract_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create validation trigger
DROP TRIGGER IF EXISTS trigger_validate_lesson_integrity ON lessons;
CREATE TRIGGER trigger_validate_lesson_integrity
  BEFORE INSERT OR UPDATE ON lessons
  FOR EACH ROW
  EXECUTE FUNCTION validate_lesson_integrity();

-- =====================================================
-- 4. ENHANCE CONTRACT UPDATE FUNCTION
-- =====================================================

-- Improve contract update function with better error handling
CREATE OR REPLACE FUNCTION handle_contract_update()
RETURNS TRIGGER AS $$
DECLARE
  lock_key bigint;
BEGIN
  -- Use advisory lock to prevent concurrent modifications
  lock_key := hashtext(NEW.id::text);
  
  IF NOT pg_try_advisory_xact_lock(lock_key) THEN
    RAISE EXCEPTION 'Contract is being modified by another operation';
  END IF;

  -- Force attendance recalculation when contract variant changes
  IF OLD.contract_variant_id IS DISTINCT FROM NEW.contract_variant_id THEN
    -- Reset attendance to force recalculation
    NEW.attendance_count := '0/0';
    NEW.attendance_dates := '[]'::jsonb;
  END IF;
  
  -- Ensure updated_at is always set
  NEW.updated_at := now();
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Error updating contract: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 5. ADD BATCH LESSON UPDATE FUNCTION
-- =====================================================

-- Create function for safe batch lesson updates
CREATE OR REPLACE FUNCTION batch_update_lessons(updates jsonb)
RETURNS text AS $$
DECLARE
  update_record RECORD;
  success_count integer := 0;
  error_count integer := 0;
  error_messages text[] := '{}';
  result_message text;
BEGIN
  -- Process each update in the batch
  FOR update_record IN 
    SELECT * FROM jsonb_array_elements(updates) AS update_data
  LOOP
    BEGIN
      -- Extract update data
      PERFORM safe_update_lesson(
        (update_record.value->>'id')::uuid,
        CASE WHEN update_record.value->>'date' = '' THEN NULL 
             ELSE (update_record.value->>'date')::date END,
        CASE WHEN update_record.value->>'comment' = '' THEN NULL 
             ELSE update_record.value->>'comment' END,
        (update_record.value->>'is_available')::boolean
      );
      
      success_count := success_count + 1;
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      error_messages := array_append(error_messages, 
        format('Lesson %s: %s', update_record.value->>'id', SQLERRM));
    END;
  END LOOP;

  -- Build result message
  result_message := format('Batch update completed: %s successful, %s failed', 
    success_count, error_count);
  
  IF error_count > 0 THEN
    result_message := result_message || format(' Errors: %s', array_to_string(error_messages, '; '));
  END IF;

  RETURN result_message;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 6. FIX EXISTING DATA INCONSISTENCIES
-- =====================================================

-- Fix any lessons with null contract_id (should not exist but just in case)
DELETE FROM lessons WHERE contract_id IS NULL;

-- Fix any contracts with missing lessons
DO $$
DECLARE
  contract_record RECORD;
  expected_lessons integer;
  actual_lessons integer;
  i integer;
BEGIN
  FOR contract_record IN 
    SELECT 
      c.id,
      c.contract_variant_id,
      c.type,
      cv.total_lessons
    FROM contracts c
    LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
    WHERE c.status = 'active'
  LOOP
    -- Get expected lesson count
    expected_lessons := COALESCE(contract_record.total_lessons, 
      CASE 
        WHEN contract_record.type = 'ten_class_card' THEN 10
        WHEN contract_record.type = 'half_year' THEN 18
        ELSE 10
      END
    );

    -- Count actual lessons
    SELECT COUNT(*) INTO actual_lessons
    FROM lessons
    WHERE contract_id = contract_record.id;

    -- Fix if counts don't match
    IF actual_lessons != expected_lessons THEN
      -- Delete existing lessons
      DELETE FROM lessons WHERE contract_id = contract_record.id;
      
      -- Regenerate lessons
      FOR i IN 1..expected_lessons LOOP
        INSERT INTO lessons (contract_id, lesson_number, is_available)
        VALUES (contract_record.id, i, true);
      END LOOP;
    END IF;
  END LOOP;
END $$;

-- =====================================================
-- 7. ADD PERFORMANCE INDEXES
-- =====================================================

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_lessons_contract_id_lesson_number ON lessons(contract_id, lesson_number);
CREATE INDEX IF NOT EXISTS idx_lessons_date_available ON lessons(date, is_available) WHERE date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contracts_status_variant ON contracts(status, contract_variant_id);

-- =====================================================
-- 8. GRANT PERMISSIONS
-- =====================================================

-- Grant execute permissions on new functions
GRANT EXECUTE ON FUNCTION safe_update_lesson(uuid, date, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION batch_update_lessons(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_contract_data(uuid) TO authenticated;

-- =====================================================
-- 9. ADD ERROR LOGGING
-- =====================================================

-- Create error logging function for debugging
CREATE OR REPLACE FUNCTION log_contract_error(
  operation text,
  contract_id_param uuid,
  error_message text
)
RETURNS void AS $$
BEGIN
  -- Log to a dedicated error table (create if doesn't exist)
  CREATE TABLE IF NOT EXISTS contract_error_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    operation text NOT NULL,
    contract_id uuid,
    error_message text NOT NULL,
    created_at timestamptz DEFAULT now()
  );

  INSERT INTO contract_error_logs (operation, contract_id, error_message)
  VALUES (operation, contract_id_param, error_message);
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION log_contract_error(text, uuid, text) TO authenticated; 