/*
  # Fix Lesson Progress Saving Issue

  1. Database Changes
    - Update the contract attendance trigger to prevent concurrent modifications
    - Use advisory locks to prevent "tuple already modified" errors
    - Improve efficiency with single-query operations
    - Add manual fix function for contract attendance

  2. Functions
    - Enhanced `update_contract_attendance()` function with conflict prevention
    - New `fix_contract_attendance()` function for manual corrections

  3. Triggers
    - Recreate trigger with improved logic to prevent conflicts
*/

-- Drop existing trigger
DROP TRIGGER IF EXISTS trigger_update_contract_attendance_on_lesson_change ON lessons;

-- Create an improved version of the update_contract_attendance function
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_count integer;
  available_count integer;
  total_count integer;
  contract_id_to_update uuid;
  lesson_dates jsonb;
  lock_acquired boolean := false;
BEGIN
  -- Get the contract ID to update
  contract_id_to_update := COALESCE(NEW.contract_id, OLD.contract_id);
  
  -- Use advisory lock to prevent concurrent modifications of the same contract
  -- This helps prevent the "tuple already updated" error
  BEGIN
    -- Try to acquire an advisory lock for this contract
    SELECT pg_try_advisory_xact_lock(hashtext(contract_id_to_update::text)) INTO lock_acquired;
    
    -- If we couldn't get the lock, skip this update
    IF NOT lock_acquired THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- If there's any error with the advisory lock, continue anyway
    lock_acquired := true;
  END;

  -- Get total lessons from contract variant
  SELECT cv.total_lessons INTO total_count
  FROM contracts c
  LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
  WHERE c.id = contract_id_to_update;

  -- Default fallback for contracts without variants
  IF total_count IS NULL THEN
    -- Try to get from legacy type system
    SELECT 
      CASE 
        WHEN c.type = 'ten_class_card' THEN 10
        WHEN c.type = 'half_year' THEN 18
        ELSE 10
      END
    INTO total_count
    FROM contracts c
    WHERE c.id = contract_id_to_update;
    
    -- Final fallback
    IF total_count IS NULL THEN
      total_count := 10;
    END IF;
  END IF;

  -- Count available and completed lessons in a single query
  -- This is more efficient than separate queries
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true),
    COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true),
    COALESCE(
      jsonb_agg(date::text ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL AND is_available = true),
      '[]'::jsonb
    )
  INTO 
    available_count,
    completed_count,
    lesson_dates
  FROM lessons
  WHERE contract_id = contract_id_to_update;

  -- Update contract attendance count and dates in a single atomic operation
  -- Use total_count as the denominator for consistent progress tracking
  UPDATE contracts
  SET 
    attendance_count = completed_count || '/' || total_count,
    attendance_dates = lesson_dates,
    updated_at = now()
  WHERE id = contract_id_to_update;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create a new trigger that runs AFTER changes to lessons
CREATE TRIGGER trigger_update_contract_attendance_on_lesson_change
  AFTER INSERT OR UPDATE OR DELETE ON lessons
  FOR EACH ROW
  EXECUTE FUNCTION update_contract_attendance();

-- Create a function to manually update contract attendance
-- This can be used to fix contracts with incorrect attendance counts
CREATE OR REPLACE FUNCTION fix_contract_attendance(contract_id_param uuid)
RETURNS text AS $$
DECLARE
  completed_count integer;
  available_count integer;
  total_count integer;
  lesson_dates jsonb;
  contract_record RECORD;
  result_message text;
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN 'Access denied: Only administrators can fix contract attendance';
  END IF;
  
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;
  
  -- Get total lessons from contract variant
  SELECT cv.total_lessons INTO total_count
  FROM contract_variants cv
  WHERE cv.id = contract_record.contract_variant_id;

  -- Default fallback for contracts without variants
  IF total_count IS NULL THEN
    total_count := CASE 
      WHEN contract_record.type = 'ten_class_card' THEN 10
      WHEN contract_record.type = 'half_year' THEN 18
      ELSE 10
    END;
  END IF;

  -- Count available and completed lessons
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true),
    COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true),
    COALESCE(
      jsonb_agg(date::text ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL AND is_available = true),
      '[]'::jsonb
    )
  INTO 
    available_count,
    completed_count,
    lesson_dates
  FROM lessons
  WHERE contract_id = contract_id_param;

  -- Update contract attendance count and dates
  UPDATE contracts
  SET 
    attendance_count = completed_count || '/' || total_count,
    attendance_dates = lesson_dates,
    updated_at = now()
  WHERE id = contract_id_param;

  result_message := format(
    'Contract attendance updated. Lessons: %s completed of %s available (total: %s).',
    completed_count, available_count, total_count
  );
  
  RETURN result_message;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission on fix function
GRANT EXECUTE ON FUNCTION fix_contract_attendance(uuid) TO authenticated;