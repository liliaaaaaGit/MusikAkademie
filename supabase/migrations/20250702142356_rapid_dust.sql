/*
  # Improve Trial Notification System

  1. Changes
    - Fix notification logic to only send open trial notifications to teachers (not admins)
    - Update notification messages to use German text
    - Ensure no duplicate notifications are sent
    - Clean up outdated notifications automatically

  2. Key Improvements
    - Teachers receive notifications when:
      - A trial lesson is assigned to them
      - A new open trial lesson is created
    - Admins receive notifications only when:
      - A contract is fulfilled
      - A trial lesson is accepted by a teacher
      - A trial lesson is declined by a teacher
*/

-- Update the notify_new_open_trial function to only notify teachers (not admins)
CREATE OR REPLACE FUNCTION notify_new_open_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  notification_message text;
BEGIN
  -- Only create notification if a new trial is created with status 'open'
  -- or if an existing trial is updated to 'open' status (and wasn't open before)
  IF (TG_OP = 'INSERT' AND NEW.status = 'open') OR 
     (TG_OP = 'UPDATE' AND NEW.status = 'open' AND (OLD.status != 'open' OR OLD.status IS NULL)) THEN
    
    -- Create notification message in German
    notification_message := format(
      'Eine neue offene Probestunde ist verfügbar. Sie können diese in Ihrer Probestundenübersicht annehmen.'
    );

    -- Insert notification for all teachers (NOT admins)
    FOR teacher_record IN 
      SELECT t.id 
      FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.role = 'teacher'
    LOOP
      -- Use INSERT ... ON CONFLICT DO NOTHING to prevent duplicates
      INSERT INTO notifications (
        type,
        trial_appointment_id,
        teacher_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'declined_trial', -- We use the same type for all open trial notifications
        NEW.id,
        teacher_record.id,
        notification_message,
        false,
        now(),
        now()
      )
      ON CONFLICT (trial_appointment_id, teacher_id, type) DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- Update the notify_declined_trial function to only notify teachers (not admins)
CREATE OR REPLACE FUNCTION notify_declined_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  notification_message text;
  declining_teacher_id uuid;
BEGIN
  -- Only create notification if status changed from 'assigned' to 'open'
  IF OLD.status = 'assigned' AND NEW.status = 'open' THEN
    
    -- Store the declining teacher's ID to exclude them from notifications
    declining_teacher_id := OLD.teacher_id;
    
    -- Create notification message in German
    notification_message := format(
      'Eine neue offene Probestunde ist verfügbar. Sie können diese in Ihrer Probestundenübersicht annehmen.'
    );

    -- Delete any existing assigned trial notification for the declining teacher
    DELETE FROM notifications
    WHERE trial_appointment_id = NEW.id 
    AND teacher_id = declining_teacher_id
    AND type = 'assigned_trial';

    -- Insert notification for all teachers except the one who declined
    -- and only for teachers (not admins)
    FOR teacher_record IN 
      SELECT t.id 
      FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.role = 'teacher' AND t.id != declining_teacher_id
    LOOP
      INSERT INTO notifications (
        type,
        trial_appointment_id,
        teacher_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'declined_trial',
        NEW.id,
        teacher_record.id,
        notification_message,
        false,
        now(),
        now()
      )
      ON CONFLICT (trial_appointment_id, teacher_id, type) DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- Update the notify_assigned_trial function with clearer German message
CREATE OR REPLACE FUNCTION notify_assigned_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  notification_message text;
BEGIN
  -- Only create notification if status changed to 'assigned' and teacher_id is set
  IF NEW.status = 'assigned' AND NEW.teacher_id IS NOT NULL AND
     (OLD IS NULL OR OLD.status != 'assigned' OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id) THEN
    
    -- Create notification message in German
    notification_message := format(
      'Sie wurden einer neuen Probestunde zugewiesen. Bitte prüfen Sie Ihre Probestundenübersicht, um diese anzunehmen oder abzulehnen.'
    );

    -- Delete any existing open trial notifications for this trial for all teachers
    DELETE FROM notifications
    WHERE trial_appointment_id = NEW.id AND type = 'declined_trial';

    -- Insert notification for the assigned teacher
    INSERT INTO notifications (
      type,
      trial_appointment_id,
      teacher_id,
      message,
      is_read,
      created_at,
      updated_at
    ) VALUES (
      'assigned_trial',
      NEW.id,
      NEW.teacher_id,
      notification_message,
      false,
      now(),
      now()
    )
    ON CONFLICT (trial_appointment_id, teacher_id, type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- Update the notify_accepted_trial function to only notify admins about acceptances
CREATE OR REPLACE FUNCTION notify_accepted_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_name text;
  notification_message text;
  admin_profile_record RECORD;
BEGIN
  -- Only create notification if status changed to 'accepted'
  IF NEW.status = 'accepted' AND (OLD IS NULL OR OLD.status != 'accepted') THEN
    
    -- Get teacher name
    SELECT name INTO teacher_name
    FROM teachers
    WHERE id = NEW.teacher_id;

    -- Create notification message in German
    notification_message := format(
      '%s hat eine Probestunde mit %s angenommen.',
      COALESCE(teacher_name, 'Ein Lehrer'),
      NEW.student_name
    );

    -- Delete all existing notifications for this trial for all teachers except the accepting one
    DELETE FROM notifications
    WHERE trial_appointment_id = NEW.id 
    AND (teacher_id != NEW.teacher_id OR teacher_id IS NULL)
    AND type IN ('declined_trial', 'assigned_trial');

    -- Insert notification for all admin profiles only
    FOR admin_profile_record IN 
      SELECT p.id as profile_id
      FROM profiles p
      WHERE p.role = 'admin'
    LOOP
      INSERT INTO notifications (
        type,
        trial_appointment_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'accepted_trial',
        NEW.id,
        notification_message,
        false,
        now(),
        now()
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- Run cleanup to fix any existing issues
SELECT run_notification_cleanup();