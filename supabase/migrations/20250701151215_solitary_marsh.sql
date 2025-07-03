-- Drop existing functions and triggers to recreate them
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
DROP FUNCTION IF EXISTS notify_contract_fulfilled();
DROP FUNCTION IF EXISTS test_notification_system(uuid);
DROP FUNCTION IF EXISTS force_contract_notification(uuid);
DROP FUNCTION IF EXISTS check_notification_system_status();

-- Create a simplified and robust notification function
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
  old_total_lessons integer := 1;
  new_current_lessons integer := 0;
  new_total_lessons integer := 1;
  should_notify boolean := false;
  existing_notification_count integer;
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

  -- Check for attendance completion (progress reaching 100%)
  IF OLD.attendance_count IS DISTINCT FROM NEW.attendance_count THEN
    -- Parse old attendance count safely
    IF OLD.attendance_count IS NOT NULL AND OLD.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      BEGIN
        old_current_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 1) AS INTEGER);
        old_total_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 2) AS INTEGER);
      EXCEPTION WHEN OTHERS THEN
        old_current_lessons := 0;
        old_total_lessons := 1;
      END;
    END IF;
    
    -- Parse new attendance count safely
    IF NEW.attendance_count IS NOT NULL AND NEW.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      BEGIN
        new_current_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 1) AS INTEGER);
        new_total_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 2) AS INTEGER);
      EXCEPTION WHEN OTHERS THEN
        new_current_lessons := 0;
        new_total_lessons := 1;
      END;
    END IF;
    
    -- Check if contract just became complete (reached 100%)
    -- Conditions: new lessons = total, total > 0, old was not complete, status is active
    IF new_current_lessons = new_total_lessons 
       AND new_total_lessons > 0 
       AND (old_current_lessons < old_total_lessons OR old_total_lessons = 0)
       AND NEW.status = 'active' THEN
      
      should_notify := true;
      
      -- Automatically mark contract as completed when all lessons are done
      UPDATE contracts 
      SET status = 'completed', updated_at = now()
      WHERE id = NEW.id;
      
      -- Update NEW record for consistency
      NEW.status := 'completed';
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

-- Create the trigger
CREATE TRIGGER trigger_contract_fulfilled_notification
  AFTER UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- Create an improved test function
CREATE OR REPLACE FUNCTION test_notification_system(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result_message text;
  contract_record RECORD;
  total_lessons integer;
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
  
  -- Parse total lessons from attendance count
  IF contract_record.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
    total_lessons := CAST(SPLIT_PART(contract_record.attendance_count, '/', 2) AS INTEGER);
  ELSE
    total_lessons := 10; -- Default fallback
  END IF;
  
  -- Reset contract to incomplete state
  UPDATE contracts
  SET 
    status = 'active',
    attendance_count = '0/' || total_lessons::text,
    updated_at = now()
  WHERE id = contract_id_param;

  -- Force completion to trigger notification
  UPDATE contracts
  SET 
    attendance_count = total_lessons::text || '/' || total_lessons::text,
    updated_at = now()
  WHERE id = contract_id_param;
  
  -- Count notifications after test
  SELECT COUNT(*) INTO notification_count_after
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  result_message := format(
    'Test completed for contract %s. Notifications before: %s, after: %s. %s',
    contract_id_param,
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

-- Create a function to manually trigger a notification for any contract
CREATE OR REPLACE FUNCTION force_contract_notification(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result_message text;
  contract_record RECORD;
  student_name text;
  teacher_name text;
  teacher_id_val uuid;
  student_id_val uuid;
  contract_type_display text;
  notification_message text;
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN 'Access denied: Only administrators can force notifications';
  END IF;
  
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;
  
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
  WHERE s.id = contract_record.student_id;

  -- Get contract type display name
  SELECT 
    COALESCE(cv.name, 
      CASE contract_record.type
        WHEN 'ten_class_card' THEN '10er Karte'
        WHEN 'half_year' THEN 'Halbjahresvertrag'
        ELSE contract_record.type
      END
    )
  INTO contract_type_display
  FROM contracts c
  LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
  WHERE c.id = contract_record.id;

  -- Create notification message
  notification_message := format(
    'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen. Lehrer: %s. Abgeschlossen am: %s.',
    COALESCE(student_name, 'Unbekannter Schüler'),
    COALESCE(contract_type_display, 'Vertrag'),
    COALESCE(teacher_name, 'Unbekannter Lehrer'),
    to_char(now(), 'DD.MM.YYYY HH24:MI')
  );

  -- Insert notification directly
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
    contract_record.id,
    teacher_id_val,
    student_id_val,
    notification_message,
    false,
    now(),
    now()
  );
  
  result_message := format(
    'Forced notification created for contract %s (%s - %s)',
    contract_id_param,
    student_name,
    contract_type_display
  );
  
  RETURN result_message;
END;
$$;

-- Create a comprehensive status check function with new signature
CREATE OR REPLACE FUNCTION check_notification_system_status()
RETURNS TABLE(
  total_contracts bigint,
  active_contracts bigint,
  completed_contracts bigint,
  total_notifications bigint,
  recent_notifications bigint,
  contracts_with_notifications bigint
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT 
    (SELECT COUNT(*) FROM contracts) as total_contracts,
    (SELECT COUNT(*) FROM contracts WHERE status = 'active') as active_contracts,
    (SELECT COUNT(*) FROM contracts WHERE status = 'completed') as completed_contracts,
    (SELECT COUNT(*) FROM notifications WHERE type = 'contract_fulfilled') as total_notifications,
    (SELECT COUNT(*) FROM notifications WHERE type = 'contract_fulfilled' AND created_at > now() - interval '24 hours') as recent_notifications,
    (SELECT COUNT(DISTINCT contract_id) FROM notifications WHERE type = 'contract_fulfilled') as contracts_with_notifications;
$$;

-- Grant execute permissions on all functions
GRANT EXECUTE ON FUNCTION test_notification_system(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION force_contract_notification(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION check_notification_system_status() TO authenticated;