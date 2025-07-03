/*
  # Fix Notifications for New Open Trial Lessons

  1. Changes
    - Ensure teachers receive notifications for new open trial lessons
    - Prevent admins from receiving notifications for new open trial lessons
    - Improve notification messages with more details
    - Fix notification routing based on user roles

  2. Key Fixes
    - Update notify_new_open_trial function to properly notify all teachers
    - Include student name and instrument in notification messages
    - Ensure proper notification cleanup when trials change status
    - Fix RLS policies to ensure correct visibility
*/

-- Update RLS policies for notifications to ensure proper visibility
DO $$
DECLARE
  policy_exists boolean;
BEGIN
  -- Check and drop existing policies
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'notifications' 
    AND policyname = 'Admins can read admin notifications'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Admins can read admin notifications" ON notifications;
  END IF;
  
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'notifications' 
    AND policyname = 'Teachers can read their own notifications'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can read their own notifications" ON notifications;
  END IF;
END $$;

-- Create updated RLS policies for notifications
CREATE POLICY "Admins can read admin notifications"
  ON notifications FOR SELECT
  TO authenticated
  USING (
    (get_user_role() = 'admin') AND
    (
      (teacher_id IS NULL) OR
      (type = 'contract_fulfilled')
    )
  );

CREATE POLICY "Teachers can read their own notifications"
  ON notifications FOR SELECT
  TO authenticated
  USING (
    (get_user_role() = 'teacher') AND
    (teacher_id IN (
      SELECT t.id FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid()
    ))
  );

-- Update the notify_new_open_trial function to properly notify teachers about new open trials
CREATE OR REPLACE FUNCTION notify_new_open_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  notification_message text;
  creator_profile_id uuid;
  creator_role text;
BEGIN
  -- Get the creator's profile ID and role
  creator_profile_id := auth.uid();
  
  IF creator_profile_id IS NOT NULL THEN
    SELECT role INTO creator_role
    FROM profiles
    WHERE id = creator_profile_id;
  END IF;
  
  -- Only create notification if a new trial is created with status 'open'
  -- or if an existing trial is updated to 'open' status (and wasn't open before)
  IF (TG_OP = 'INSERT' AND NEW.status = 'open') OR 
     (TG_OP = 'UPDATE' AND NEW.status = 'open' AND (OLD.status != 'open' OR OLD.status IS NULL)) THEN
    
    -- Create notification message in German with student name and instrument
    notification_message := format(
      'Eine neue offene Probestunde mit %s (%s) ist verfügbar. Sie können diese in Ihrer Probestundenübersicht annehmen.',
      NEW.student_name,
      NEW.instrument
    );

    -- Insert notification for all teachers except the creator (if creator is a teacher)
    FOR teacher_record IN 
      SELECT t.id 
      FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.role = 'teacher'
      AND (p.id != creator_profile_id OR creator_role = 'admin')
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

-- Update the notify_declined_trial function to create better notifications
CREATE OR REPLACE FUNCTION notify_declined_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  notification_message_teachers text;
  notification_message_admins text;
  declining_teacher_id uuid;
  declining_teacher_name text;
  declining_profile_id uuid;
  declining_profile_role text;
BEGIN
  -- Only create notification if status changed from 'assigned' to 'open'
  IF OLD.status = 'assigned' AND NEW.status = 'open' THEN
    
    -- Store the declining teacher's ID to exclude them from notifications
    declining_teacher_id := OLD.teacher_id;
    
    -- Get the declining teacher's name and profile ID
    SELECT name, profile_id INTO declining_teacher_name, declining_profile_id
    FROM teachers
    WHERE id = declining_teacher_id;
    
    -- Get the declining user's role
    IF declining_profile_id IS NOT NULL THEN
      SELECT role INTO declining_profile_role
      FROM profiles
      WHERE id = declining_profile_id;
    END IF;
    
    -- Create notification message for teachers in German
    notification_message_teachers := format(
      'Eine neue offene Probestunde mit %s (%s) ist verfügbar. Sie können diese in Ihrer Probestundenübersicht annehmen.',
      NEW.student_name,
      NEW.instrument
    );
    
    -- Create notification message for admins in German
    notification_message_admins := format(
      '%s hat eine Probestunde mit %s (%s) abgelehnt. Die Probestunde ist jetzt für andere Lehrer verfügbar.',
      COALESCE(declining_teacher_name, 'Ein Lehrer'),
      NEW.student_name,
      NEW.instrument
    );

    -- Delete any existing assigned trial notification for the declining teacher
    DELETE FROM notifications
    WHERE trial_appointment_id = NEW.id 
    AND teacher_id = declining_teacher_id
    AND type = 'assigned_trial';

    -- Insert notification for all teachers except the one who declined
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
    
    -- Insert notification for admins only if the declining user is not an admin
    IF declining_profile_role != 'admin' THEN
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
        NULL,
        notification_message_admins,
        false,
        now(),
        now()
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Update the notify_assigned_trial function to create better notifications
CREATE OR REPLACE FUNCTION notify_assigned_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  notification_message text;
  assigning_profile_id uuid;
  assigning_role text;
  teacher_profile_id uuid;
BEGIN
  -- Get the assigning user's profile ID and role
  assigning_profile_id := auth.uid();
  
  IF assigning_profile_id IS NOT NULL THEN
    SELECT role INTO assigning_role
    FROM profiles
    WHERE id = assigning_profile_id;
  END IF;
  
  -- Get the profile ID of the assigned teacher
  SELECT profile_id INTO teacher_profile_id
  FROM teachers
  WHERE id = NEW.teacher_id;
  
  -- Only create notification if status changed to 'assigned' and teacher_id is set
  -- Skip if the assigned teacher is the same as the assigning user (to prevent self-notifications)
  IF NEW.status = 'assigned' AND NEW.teacher_id IS NOT NULL AND
     (OLD IS NULL OR OLD.status != 'assigned' OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id) AND
     teacher_profile_id != assigning_profile_id THEN
    
    -- Create notification message in German
    notification_message := format(
      'Sie wurden einer neuen Probestunde mit %s (%s) zugewiesen. Bitte prüfen Sie Ihre Probestundenübersicht, um diese anzunehmen oder abzulehnen.',
      NEW.student_name,
      NEW.instrument
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

-- Update the notify_accepted_trial function to create better notifications
CREATE OR REPLACE FUNCTION notify_accepted_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_name text;
  notification_message text;
  accepting_profile_id uuid;
  accepting_role text;
BEGIN
  -- Only create notification if status changed to 'accepted'
  IF NEW.status = 'accepted' AND (OLD IS NULL OR OLD.status != 'accepted') THEN
    
    -- Get teacher name and profile ID
    SELECT name, profile_id INTO teacher_name, accepting_profile_id
    FROM teachers
    WHERE id = NEW.teacher_id;
    
    -- Get the role of the accepting user
    IF accepting_profile_id IS NOT NULL THEN
      SELECT role INTO accepting_role
      FROM profiles
      WHERE id = accepting_profile_id;
    END IF;
    
    -- Create notification message in German
    notification_message := format(
      '%s hat eine Probestunde mit %s (%s) angenommen.',
      COALESCE(teacher_name, 'Ein Lehrer'),
      NEW.student_name,
      NEW.instrument
    );

    -- Delete all existing notifications for this trial for all teachers
    DELETE FROM notifications
    WHERE trial_appointment_id = NEW.id 
    AND type IN ('declined_trial', 'assigned_trial');

    -- Insert notification for admins only if the accepting user is not an admin
    IF accepting_role != 'admin' THEN
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
        NULL,
        notification_message,
        false,
        now(),
        now()
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Run cleanup to fix any existing issues
SELECT run_notification_cleanup();