/*
  # Fix Notification Function - Remove Debug Exception

  1. Function Updates
    - Remove the RAISE EXCEPTION line that was preventing normal execution
    - Keep all the detailed logging for debugging purposes
    - Allow the function to complete its notification creation process

  2. Testing
    - The function will now properly create notifications when conditions are met
    - All debug logging remains active to help track execution
*/

-- Update the notification function to remove the blocking RAISE EXCEPTION
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
  old_current_lessons integer;
  old_total_lessons integer;
  new_current_lessons integer;
  new_total_lessons integer;
  should_notify boolean := false;
  existing_notification_count integer;
  notification_reason text := '';
BEGIN
  -- Debug: Log the trigger execution
  RAISE NOTICE '=== NOTIFICATION TRIGGER FIRED ===';
  RAISE NOTICE 'Contract ID: %', NEW.id;
  RAISE NOTICE 'Old status: %, New status: %', OLD.status, NEW.status;
  RAISE NOTICE 'Old attendance: %, New attendance: %', OLD.attendance_count, NEW.attendance_count;
  RAISE NOTICE 'Contract student_id: %', NEW.student_id;

  -- Check if notification already exists for this contract to prevent duplicates
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = NEW.id AND type = 'contract_fulfilled';

  RAISE NOTICE 'Existing notifications for contract %: %', NEW.id, existing_notification_count;

  -- Skip if notification already exists
  IF existing_notification_count > 0 THEN
    RAISE NOTICE 'SKIPPING: Notification already exists for contract %', NEW.id;
    RETURN NEW;
  END IF;

  -- Check for manual status change from 'active' to 'completed'
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    should_notify := true;
    notification_reason := 'Manual status change to completed';
    RAISE NOTICE 'CONDITION MET: Manual status change detected: % -> %', OLD.status, NEW.status;
  END IF;

  -- Check for attendance completion (progress reaching 100%)
  IF OLD.attendance_count IS DISTINCT FROM NEW.attendance_count THEN
    RAISE NOTICE 'ATTENDANCE CHANGE: % -> %', OLD.attendance_count, NEW.attendance_count;
    
    -- Parse old attendance count
    IF OLD.attendance_count IS NOT NULL AND OLD.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      old_current_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 1) AS INTEGER);
      old_total_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 2) AS INTEGER);
      RAISE NOTICE 'OLD parsed: % completed out of %', old_current_lessons, old_total_lessons;
    ELSE
      old_current_lessons := 0;
      old_total_lessons := 1; -- Avoid division by zero
      RAISE NOTICE 'OLD attendance could not be parsed, using defaults: %/%', old_current_lessons, old_total_lessons;
    END IF;
    
    -- Parse new attendance count
    IF NEW.attendance_count IS NOT NULL AND NEW.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      new_current_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 1) AS INTEGER);
      new_total_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 2) AS INTEGER);
      RAISE NOTICE 'NEW parsed: % completed out of %', new_current_lessons, new_total_lessons;
    ELSE
      new_current_lessons := 0;
      new_total_lessons := 1; -- Avoid division by zero
      RAISE NOTICE 'NEW attendance could not be parsed, using defaults: %/%', new_current_lessons, new_total_lessons;
    END IF;
    
    -- Check if contract just became complete (reached 100%)
    IF new_current_lessons = new_total_lessons 
       AND new_total_lessons > 0 
       AND old_current_lessons < old_total_lessons 
       AND NEW.status = 'active' THEN
      should_notify := true;
      notification_reason := 'Contract completion detected (100% progress)';
      RAISE NOTICE 'CONDITION MET: Contract completion detected: %/% (was %/%)', new_current_lessons, new_total_lessons, old_current_lessons, old_total_lessons;
      
      -- Automatically mark contract as completed when all lessons are done
      RAISE NOTICE 'AUTO-UPDATING: Setting contract status to completed';
      UPDATE contracts 
      SET status = 'completed', updated_at = now()
      WHERE id = NEW.id;
      
      -- Update NEW record for consistency
      NEW.status := 'completed';
      RAISE NOTICE 'Contract status updated to completed in trigger';
    ELSE
      RAISE NOTICE 'NO COMPLETION: new_current=%s, new_total=%s, old_current=%s, old_total=%s, status=%s', 
                   new_current_lessons, new_total_lessons, old_current_lessons, old_total_lessons, NEW.status;
    END IF;
  ELSE
    RAISE NOTICE 'NO ATTENDANCE CHANGE detected';
  END IF;

  -- Only create notification if conditions are met
  IF should_notify THEN
    RAISE NOTICE 'CREATING NOTIFICATION: Reason = %', notification_reason;
    
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

    RAISE NOTICE 'Student info: name=%, id=%', student_name, student_id_val;
    RAISE NOTICE 'Teacher info: name=%, id=%', teacher_name, teacher_id_val;

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

    RAISE NOTICE 'Contract type display: %', contract_type_display;

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
      RAISE NOTICE 'ATTEMPTING: Notification insert...';
      
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
      
      RAISE NOTICE 'SUCCESS: Notification created successfully for contract %', NEW.id;
      
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ERROR: Failed to create notification: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
      -- Don't fail the entire transaction, just log the error
    END;

  ELSE
    RAISE NOTICE 'NO NOTIFICATION: Conditions not met for contract %', NEW.id;
    RAISE NOTICE 'should_notify = %, existing_notifications = %', should_notify, existing_notification_count;
  END IF;

  RAISE NOTICE '=== NOTIFICATION TRIGGER COMPLETE ===';
  RETURN NEW;
END;
$$;