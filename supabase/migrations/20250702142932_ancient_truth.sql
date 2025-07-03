/*
  # Fix Admin Trial Notification Logic

  1. Changes
    - Ensure admins don't receive notifications for trial lessons they created
    - Ensure admins only receive notifications for accepted/declined trials
    - Ensure teachers receive proper notifications for assigned/open trials
    - Fix duplicate notification issues
    - Improve notification message text in German

  2. Key Fixes
    - Update notification trigger functions to check creator role
    - Add logic to prevent notification creation for admins' own actions
    - Ensure proper notification cleanup when trials change status
    - Fix message text to be more clear and user-friendly
*/

-- Update the notify_new_open_trial function to only notify teachers and exclude the creator
CREATE OR REPLACE FUNCTION notify_new_open_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  notification_message text;
  creator_role text;
  creator_id uuid;
BEGIN
  -- Check if the creator is an admin (to prevent notifications for admin-created trials)
  creator_id := COALESCE(NEW.created_by, auth.uid());
  
  IF creator_id IS NOT NULL THEN
    SELECT role INTO creator_role
    FROM profiles
    WHERE id = creator_id;
  END IF;
  
  -- Only create notification if a new trial is created with status 'open'
  -- or if an existing trial is updated to 'open' status (and wasn't open before)
  IF (TG_OP = 'INSERT' AND NEW.status = 'open') OR 
     (TG_OP = 'UPDATE' AND NEW.status = 'open' AND (OLD.status != 'open' OR OLD.status IS NULL)) THEN
    
    -- Create notification message in German
    notification_message := format(
      'Eine neue offene Probestunde ist verfügbar. Sie können diese in Ihrer Probestundenübersicht annehmen.'
    );

    -- Insert notification for all teachers (NOT admins)
    -- Exclude the creator if they're a teacher
    FOR teacher_record IN 
      SELECT t.id 
      FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.role = 'teacher'
      AND (p.id != creator_id OR creator_role = 'admin')
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

-- Update the notify_declined_trial function to only notify teachers and exclude the decliner
CREATE OR REPLACE FUNCTION notify_declined_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  notification_message text;
  declining_teacher_id uuid;
  declining_profile_id uuid;
BEGIN
  -- Only create notification if status changed from 'assigned' to 'open'
  IF OLD.status = 'assigned' AND NEW.status = 'open' THEN
    
    -- Store the declining teacher's ID to exclude them from notifications
    declining_teacher_id := OLD.teacher_id;
    
    -- Get the profile ID of the declining teacher
    SELECT profile_id INTO declining_profile_id
    FROM teachers
    WHERE id = declining_teacher_id;
    
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

-- Update the notify_assigned_trial function to only notify the assigned teacher
CREATE OR REPLACE FUNCTION notify_assigned_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  notification_message text;
  assigning_role text;
BEGIN
  -- Check if the assigner is an admin (to prevent notifications for admin-assigned trials)
  SELECT role INTO assigning_role
  FROM profiles
  WHERE id = auth.uid();
  
  -- Only create notification if status changed to 'assigned' and teacher_id is set
  IF NEW.status = 'assigned' AND NEW.teacher_id IS NOT NULL AND
     (OLD IS NULL OR OLD.status != 'assigned' OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id) THEN
    
    -- Create notification message in German
    notification_message := format(
      'Sie wurden einer neuen Probestunde mit %s zugewiesen. Bitte prüfen Sie Ihre Probestundenübersicht, um diese anzunehmen oder abzulehnen.',
      NEW.student_name
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
  accepting_profile_id uuid;
  accepting_role text;
BEGIN
  -- Only create notification if status changed to 'accepted'
  IF NEW.status = 'accepted' AND (OLD IS NULL OR OLD.status != 'accepted') THEN
    
    -- Get teacher name
    SELECT name, profile_id INTO teacher_name, accepting_profile_id
    FROM teachers
    WHERE id = NEW.teacher_id;
    
    -- Get the role of the accepting teacher's profile
    SELECT role INTO accepting_role
    FROM profiles
    WHERE id = accepting_profile_id;
    
    -- Create notification message in German
    notification_message := format(
      '%s hat eine Probestunde mit %s angenommen.',
      COALESCE(teacher_name, 'Ein Lehrer'),
      NEW.student_name
    );

    -- Delete all existing notifications for this trial for all teachers
    DELETE FROM notifications
    WHERE trial_appointment_id = NEW.id 
    AND type IN ('declined_trial', 'assigned_trial');

    -- Insert notification for all admin profiles only
    -- Skip notification if the accepting user is an admin (to prevent self-notifications)
    FOR admin_profile_record IN 
      SELECT p.id as profile_id
      FROM profiles p
      WHERE p.role = 'admin'
      AND (accepting_role != 'admin' OR p.id != accepting_profile_id)
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