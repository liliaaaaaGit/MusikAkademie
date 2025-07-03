/*
  # Improve Trial Lesson Notification System

  1. Changes
    - Update notification messages to use German text
    - Remove Accept/Decline buttons from notifications
    - Simplify notification workflow
    - Fix notification duplication issues
    - Ensure proper cleanup of outdated notifications

  2. Security
    - Maintain existing RLS policies
    - Ensure proper access control for notifications
*/

-- Update the notify_assigned_trial function to use German text
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

-- Update the notify_declined_trial function to use German text
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
    FOR teacher_record IN SELECT id FROM teachers WHERE id != declining_teacher_id LOOP
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

-- Update the notify_new_open_trial function to use German text
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

    -- Insert notification for all teachers
    FOR teacher_record IN SELECT id FROM teachers LOOP
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

-- Update the notify_accepted_trial function to use German text
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
    AND (teacher_id != NEW.teacher_id OR teacher_id IS NULL);

    -- Insert notification for the accepting teacher
    INSERT INTO notifications (
      type,
      trial_appointment_id,
      teacher_id,
      message,
      is_read,
      created_at,
      updated_at
    ) VALUES (
      'accepted_trial',
      NEW.id,
      NEW.teacher_id,
      notification_message,
      false,
      now(),
      now()
    )
    ON CONFLICT (trial_appointment_id, teacher_id, type) DO NOTHING;

    -- Insert notification for all admin profiles
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