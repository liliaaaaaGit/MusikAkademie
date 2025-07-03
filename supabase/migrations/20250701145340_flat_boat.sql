/*
  # Update test_notification_system function to properly reset and test notifications

  1. Function Updates
    - Delete existing notifications for the test contract
    - Reset contract to active status with 0 completed lessons
    - Then trigger completion to create new notification
    - Comprehensive logging for debugging

  2. Features
    - Ensures clean test environment each time
    - Guarantees trigger conditions are met
    - Detailed step-by-step logging
*/

-- Create an improved test function that properly resets the contract state
CREATE OR REPLACE FUNCTION test_notification_system(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result_message text;
  contract_record RECORD;
  current_lessons integer;
  total_lessons integer;
  notification_count integer;
BEGIN
  RAISE NOTICE 'MANUAL TEST: Starting notification test for contract %', contract_id_param;
  
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN 'Access denied: Only administrators can test notifications';
  END IF;
  
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;
  
  RAISE NOTICE 'MANUAL TEST: Contract found - status: %, attendance: %', contract_record.status, contract_record.attendance_count;
  
  -- Step 1: Delete any existing notifications for this contract to allow fresh testing
  DELETE FROM notifications 
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  GET DIAGNOSTICS notification_count = ROW_COUNT;
  RAISE NOTICE 'MANUAL TEST: Deleted % existing notifications for contract %', notification_count, contract_id_param;
  
  -- Step 2: Reset contract to an active, non-completed state
  -- This ensures the trigger conditions for "old_current_lessons < old_total_lessons" and "NEW.status = 'active'" are met
  UPDATE contracts
  SET 
    status = 'active',
    attendance_count = '0/' || SPLIT_PART(contract_record.attendance_count, '/', 2), -- Set to 0 completed lessons
    updated_at = now()
  WHERE id = contract_id_param;

  RAISE NOTICE 'MANUAL TEST: Contract reset to active and 0 lessons completed.';

  -- Re-fetch the contract record to get the updated state for the next update
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;

  -- Parse current attendance (after reset)
  IF contract_record.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
    current_lessons := CAST(SPLIT_PART(contract_record.attendance_count, '/', 1) AS INTEGER);
    total_lessons := CAST(SPLIT_PART(contract_record.attendance_count, '/', 2) AS INTEGER);
  ELSE
    current_lessons := 0;
    total_lessons := 10; -- Default
  END IF;
  
  RAISE NOTICE 'MANUAL TEST: Parsed attendance after reset - %/%', current_lessons, total_lessons;
  
  -- Step 3: Force completion by setting attendance to max and triggering update
  -- This is the update that should fire the notification trigger
  UPDATE contracts
  SET 
    attendance_count = total_lessons::text || '/' || total_lessons::text,
    updated_at = now()
  WHERE id = contract_id_param;
  
  RAISE NOTICE 'MANUAL TEST: Updated contract attendance to %/% to trigger notification.', total_lessons, total_lessons;
  
  -- Check if notification was created
  SELECT COUNT(*) INTO notification_count
  FROM notifications
  WHERE contract_id = contract_id_param;
  
  result_message := format(
    'Test completed for contract %s. Notifications after test: %s. Check logs for detailed execution trace.',
    contract_id_param,
    notification_count
  );
  
  RAISE NOTICE 'MANUAL TEST: %', result_message;
  
  RETURN result_message;
END;
$$;

-- Grant execute permission on test function
GRANT EXECUTE ON FUNCTION test_notification_system(uuid) TO authenticated;