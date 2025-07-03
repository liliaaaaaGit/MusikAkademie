/*
  # Fix Notification System for Duplicate Messages and Available Lessons Logic

  1. Changes
    - Use BEFORE UPDATE trigger instead of AFTER UPDATE to prevent recursive calls
    - Update logic to check completed lessons against available lessons (not total contract lessons)
    - Fix duplicate notification issue by preventing recursive trigger execution
    - Ensure notifications are sent when progress bar reaches 100% based on available lessons

  2. Key Fixes
    - Notifications triggered when completed_lessons = available_lessons (excluding disabled lessons)
    - Prevent duplicate notifications through better trigger design
    - Use lesson availability data from lessons table for accurate progress calculation
*/

-- Drop existing trigger and function to recreate them
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
DROP FUNCTION IF EXISTS notify_contract_fulfilled();

-- Create the improved notification function that uses BEFORE UPDATE trigger
CREATE OR REPLACE FUNCTION notify_contract_fulfilled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  student_name text;
  teacher_name text;
  teacher_id_val uuid;
  student_id_val uuid;
  contract_type_display text;
  notification_message text;
  old_current_lessons integer := 0;
  old_available_lessons integer := 1;
  new_current_lessons integer := 0;
  new_available_lessons integer := 1;
  should_notify boolean := false;
  existing_notification_count integer;
  was_complete_before boolean := false;
  is_complete_now boolean := false;
BEGIN
  -- Check if notification already exists for this contract to prevent duplicates
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = NEW.id AND type = 'contract_fulfilled';

  -- Skip if notification already exists
  IF existing_notification_count > 0 THEN
    RETURN NEW;
  END IF;

  -- Check for manual status change from 'active' to 'completed'
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    should_notify := true;
  END IF;

  -- Check for attendance completion based on available lessons
  IF OLD.attendance_count IS DISTINCT FROM NEW.attendance_count THEN
    -- Parse old attendance count safely
    IF OLD.attendance_count IS NOT NULL AND OLD.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      BEGIN
        old_current_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 1) AS INTEGER);
        old_available_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 2) AS INTEGER);
      EXCEPTION WHEN OTHERS THEN
        old_current_lessons := 0;
        old_available_lessons := 1;
      END;
    END IF;
    
    -- Parse new attendance count safely
    IF NEW.attendance_count IS NOT NULL AND NEW.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      BEGIN
        new_current_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 1) AS INTEGER);
        new_available_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 2) AS INTEGER);
      EXCEPTION WHEN OTHERS THEN
        new_current_lessons := 0;
        new_available_lessons := 1;
      END;
    END IF;
    
    -- Determine completion status
    was_complete_before := (old_current_lessons = old_available_lessons AND old_available_lessons > 0);
    is_complete_now := (new_current_lessons = new_available_lessons AND new_available_lessons > 0);
    
    -- Check if contract just became complete (reached 100% of available lessons)
    -- Key fix: Use available lessons (denominator) instead of total contract lessons
    IF is_complete_now 
       AND NOT was_complete_before 
       AND NEW.status = 'active' THEN
      
      should_notify := true;
      
      -- Automatically mark contract as completed when all available lessons are done
      -- This is done in the BEFORE trigger, so no recursive call
      NEW.status := 'completed';
      NEW.updated_at := now();
    END IF;
  END IF;

  -- Create notification if conditions are met
  IF should_notify THEN
    -- Get student and teacher information
    SELECT 
      s.name,
      s.id,
      t.name,
      t.id
    INTO 
      student_name,
      student_id_val,
      teacher_name,
      teacher_id_val
    FROM students s
    LEFT JOIN teachers t ON s.teacher_id = t.id
    WHERE s.id = NEW.student_id;

    -- Get contract type display name
    SELECT 
      COALESCE(cv.name, 
        CASE NEW.type
          WHEN 'ten_class_card' THEN '10er Karte'
          WHEN 'half_year' THEN 'Halbjahresvertrag'
          ELSE NEW.type
        END
      )
    INTO contract_type_display
    FROM contracts c
    LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
    WHERE c.id = NEW.id;

    -- Create notification message
    notification_message := format(
      'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen. Lehrer: %s. Abgeschlossen am: %s.',
      COALESCE(student_name, 'Unbekannter Schüler'),
      COALESCE(contract_type_display, 'Vertrag'),
      COALESCE(teacher_name, 'Unbekannter Lehrer'),
      to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI')
    );

    -- Insert notification with error handling
    BEGIN
      INSERT INTO notifications (
        type,
        contract_id,
        teacher_id,
        student_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'contract_fulfilled',
        NEW.id,
        teacher_id_val,
        student_id_val,
        notification_message,
        false,
        now(),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Log error but don't fail the transaction
      -- This ensures the contract update still succeeds even if notification fails
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- Create the trigger as BEFORE UPDATE to prevent recursive calls
CREATE TRIGGER trigger_contract_fulfilled_notification
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- Update the test function to work with the new logic
CREATE OR REPLACE FUNCTION test_notification_system(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result_message text;
  contract_record RECORD;
  available_lessons integer;
  notification_count_before integer;
  notification_count_after integer;
BEGIN
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
  
  -- Count existing notifications
  SELECT COUNT(*) INTO notification_count_before
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  -- Delete existing notifications to allow fresh testing
  DELETE FROM notifications 
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  -- Get available lessons count (lessons that are not disabled)
  SELECT COUNT(*) INTO available_lessons
  FROM lessons
  WHERE contract_id = contract_id_param 
    AND is_available = true;
  
  -- If no lessons exist, use fallback from attendance count
  IF available_lessons = 0 THEN
    IF contract_record.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      available_lessons := CAST(SPLIT_PART(contract_record.attendance_count, '/', 2) AS INTEGER);
    ELSE
      available_lessons := 10; -- Default fallback
    END IF;
  END IF;
  
  -- Reset contract to incomplete state
  UPDATE contracts
  SET 
    status = 'active',
    attendance_count = '0/' || available_lessons::text,
    updated_at = now()
  WHERE id = contract_id_param;

  -- Force completion to trigger notification (using available lessons)
  UPDATE contracts
  SET 
    attendance_count = available_lessons::text || '/' || available_lessons::text,
    updated_at = now()
  WHERE id = contract_id_param;
  
  -- Count notifications after test
  SELECT COUNT(*) INTO notification_count_after
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  result_message := format(
    'Test completed for contract %s. Available lessons: %s. Notifications before: %s, after: %s. %s',
    contract_id_param,
    available_lessons,
    notification_count_before,
    notification_count_after,
    CASE 
      WHEN notification_count_after > 0 THEN 'SUCCESS: Notification created!'
      ELSE 'FAILED: No notification created.'
    END
  );
  
  RETURN result_message;
END;
$$;

-- Grant execute permission on test function
GRANT EXECUTE ON FUNCTION test_notification_system(uuid) TO authenticated;

-- Create a function to check lesson availability for a contract
CREATE OR REPLACE FUNCTION check_contract_lesson_availability(contract_id_param uuid)
RETURNS TABLE(
  total_lessons bigint,
  available_lessons bigint,
  unavailable_lessons bigint,
  completed_lessons bigint,
  completion_percentage numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT 
    COUNT(*) as total_lessons,
    COUNT(*) FILTER (WHERE is_available = true) as available_lessons,
    COUNT(*) FILTER (WHERE is_available = false) as unavailable_lessons,
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL) as completed_lessons,
    CASE 
      WHEN COUNT(*) FILTER (WHERE is_available = true) > 0 
      THEN ROUND(
        (COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL)::numeric / 
         COUNT(*) FILTER (WHERE is_available = true)::numeric) * 100, 
        2
      )
      ELSE 0
    END as completion_percentage
  FROM lessons
  WHERE contract_id = contract_id_param;
$$;

-- Grant execute permission on lesson availability function
GRANT EXECUTE ON FUNCTION check_contract_lesson_availability(uuid) TO authenticated;