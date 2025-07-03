/*
  # Fix Admin Notifications for Trial Lessons

  1. Changes
    - Update notification functions to prevent admins from receiving notifications about their own actions
    - Ensure admins only receive notifications for relevant events (teacher actions, contract fulfillment)
    - Fix duplicate notifications issue
    - Improve notification message text and clarity

  2. Key Fixes
    - Check creator role in notify_new_open_trial to prevent notifications for admin-created trials
    - Check assigner role in notify_assigned_trial to prevent notifications for admin-assigned trials
    - Ensure proper notification cleanup when trials change status
    - Improve notification message text for better user experience
*/

-- Update the notify_new_open_trial function to check creator role and prevent admin notifications
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
  -- Get the creator ID (either from the record or the current user)
  creator_id := COALESCE(NEW.created_by, auth.uid());
  
  -- Check if the creator is an admin
  IF creator_id IS NOT NULL THEN
    SELECT role INTO creator_role
    FROM profiles
    WHERE id = creator_id;
    
    -- If creator is an admin, skip notification creation entirely
    IF creator_role = 'admin' THEN
      RETURN NEW;
    END IF;
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
      AND (p.id != creator_id)
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

-- Update the notify_assigned_trial function to check assigner role and prevent admin notifications
CREATE OR REPLACE FUNCTION notify_assigned_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  notification_message text;
  assigner_role text;
  assigner_id uuid;
  teacher_profile_id uuid;
BEGIN
  -- Get the assigner ID (current user)
  assigner_id := auth.uid();
  
  -- Check if the assigner is an admin
  IF assigner_id IS NOT NULL THEN
    SELECT role INTO assigner_role
    FROM profiles
    WHERE id = assigner_id;
  END IF;
  
  -- Get the profile ID of the assigned teacher
  SELECT profile_id INTO teacher_profile_id
  FROM teachers
  WHERE id = NEW.teacher_id;
  
  -- Only create notification if status changed to 'assigned' and teacher_id is set
  -- Skip if the assigned teacher is also an admin (to prevent self-notifications)
  IF NEW.status = 'assigned' AND NEW.teacher_id IS NOT NULL AND
     (OLD IS NULL OR OLD.status != 'assigned' OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id) AND
     teacher_profile_id != assigner_id THEN
    
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

-- Update the notify_declined_trial function to notify admins and other teachers
CREATE OR REPLACE FUNCTION notify_declined_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  admin_record RECORD;
  notification_message_teachers text;
  notification_message_admins text;
  declining_teacher_id uuid;
  declining_teacher_name text;
BEGIN
  -- Only create notification if status changed from 'assigned' to 'open'
  IF OLD.status = 'assigned' AND NEW.status = 'open' THEN
    
    -- Store the declining teacher's ID to exclude them from notifications
    declining_teacher_id := OLD.teacher_id;
    
    -- Get the declining teacher's name
    SELECT name INTO declining_teacher_name
    FROM teachers
    WHERE id = declining_teacher_id;
    
    -- Create notification message for teachers in German
    notification_message_teachers := format(
      'Eine neue offene Probestunde ist verfügbar. Sie können diese in Ihrer Probestundenübersicht annehmen.'
    );
    
    -- Create notification message for admins in German
    notification_message_admins := format(
      '%s hat eine Probestunde mit %s abgelehnt. Die Probestunde ist jetzt für andere Lehrer verfügbar.',
      COALESCE(declining_teacher_name, 'Ein Lehrer'),
      NEW.student_name
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
        notification_message_teachers,
        false,
        now(),
        now()
      )
      ON CONFLICT (trial_appointment_id, teacher_id, type) DO NOTHING;
    END LOOP;
    
    -- Insert notification for all admin profiles
    FOR admin_record IN 
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
        'declined_trial',
        NEW.id,
        notification_message_admins,
        false,
        now(),
        now()
      );
    END LOOP;
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
BEGIN
  -- Only create notification if status changed to 'accepted'
  IF NEW.status = 'accepted' AND (OLD IS NULL OR OLD.status != 'accepted') THEN
    
    -- Get teacher name and profile ID
    SELECT name, profile_id INTO teacher_name, accepting_profile_id
    FROM teachers
    WHERE id = NEW.teacher_id;
    
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
      AND p.id != accepting_profile_id
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