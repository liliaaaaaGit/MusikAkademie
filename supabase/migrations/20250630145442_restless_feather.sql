/*
  # Debug and Fix Notification System

  1. Enhanced Debugging
    - Add detailed logging to the notification function
    - Simplify the trigger logic to focus on the core issue
    - Add test data to verify the system works

  2. Key Fixes
    - Ensure the trigger fires on the right conditions
    - Add better error handling
    - Verify the notification creation logic
*/

-- First, let's create a simplified version of the notification function with better debugging
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
  current_lessons integer;
  total_lessons integer;
  should_notify boolean := false;
  existing_notification_count integer;
  debug_info text;
BEGIN
  -- Debug: Log the trigger execution
  RAISE NOTICE 'Notification trigger fired for contract %', NEW.id;
  RAISE NOTICE 'Old status: %, New status: %', OLD.status, NEW.status;
  RAISE NOTICE 'Old attendance: %, New attendance: %', OLD.attendance_count, NEW.attendance_count;

  -- Check if notification already exists for this contract to prevent duplicates
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = NEW.id AND type = 'contract_fulfilled';

  RAISE NOTICE 'Existing notifications for contract %: %', NEW.id, existing_notification_count;

  -- Skip if notification already exists
  IF existing_notification_count > 0 THEN
    RAISE NOTICE 'Notification already exists, skipping';
    RETURN NEW;
  END IF;

  -- Check for manual status change from 'active' to 'completed'
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    should_notify := true;
    RAISE NOTICE 'Manual status change detected: % -> %', OLD.status, NEW.status;
  END IF;

  -- Check for attendance completion (progress reaching 100%)
  IF OLD.attendance_count IS DISTINCT FROM NEW.attendance_count THEN
    RAISE NOTICE 'Attendance count changed: % -> %', OLD.attendance_count, NEW.attendance_count;
    
    -- Parse new attendance count
    IF NEW.attendance_count IS NOT NULL AND NEW.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      current_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 1) AS INTEGER);
      total_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 2) AS INTEGER);
      
      RAISE NOTICE 'Parsed attendance: % completed out of %', current_lessons, total_lessons;
      
      -- Check if contract just became complete (reached 100%)
      IF current_lessons = total_lessons AND total_lessons > 0 AND NEW.status = 'active' THEN
        should_notify := true;
        RAISE NOTICE 'Contract completion detected: %/%', current_lessons, total_lessons;
        
        -- Automatically mark contract as completed when all lessons are done
        UPDATE contracts 
        SET status = 'completed', updated_at = now()
        WHERE id = NEW.id;
        
        -- Update NEW record for consistency
        NEW.status := 'completed';
        RAISE NOTICE 'Contract status updated to completed';
      END IF;
    END IF;
  END IF;

  -- Only create notification if conditions are met
  IF should_notify THEN
    RAISE NOTICE 'Creating notification for contract %', NEW.id;
    
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

    RAISE NOTICE 'Student: %, Teacher: %', student_name, teacher_name;

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

    RAISE NOTICE 'Contract type: %', contract_type_display;

    -- Create notification message
    notification_message := format(
      'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen. Lehrer: %s. Abgeschlossen am: %s.',
      COALESCE(student_name, 'Unbekannter Schüler'),
      COALESCE(contract_type_display, 'Vertrag'),
      COALESCE(teacher_name, 'Unbekannter Lehrer'),
      to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI')
    );

    RAISE NOTICE 'Notification message: %', notification_message;

    -- Insert notification
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
      
      RAISE NOTICE 'Notification created successfully';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Error creating notification: %', SQLERRM;
    END;

  ELSE
    RAISE NOTICE 'No notification needed for contract %', NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate the trigger to ensure it's properly attached
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  AFTER UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- Create a test function to manually trigger a notification (for debugging)
CREATE OR REPLACE FUNCTION test_notification_system(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result_message text;
  contract_record RECORD;
BEGIN
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found';
  END IF;
  
  -- Manually update the contract to trigger the notification
  UPDATE contracts
  SET attendance_count = SPLIT_PART(attendance_count, '/', 2) || '/' || SPLIT_PART(attendance_count, '/', 2),
      updated_at = now()
  WHERE id = contract_id_param;
  
  RETURN 'Test notification triggered for contract ' || contract_id_param;
END;
$$;

-- Grant execute permission on test function
GRANT EXECUTE ON FUNCTION test_notification_system(uuid) TO authenticated;