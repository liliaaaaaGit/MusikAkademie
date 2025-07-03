/*
  # Fix Admin Notifications for Trial Lessons

  1. RLS Policy Updates
    - Update RLS policies for notifications table
    - Create separate policies for admins and teachers
    - Ensure admins only see notifications intended for them
    - Ensure teachers only see notifications intended for them

  2. Function Updates
    - Update notification functions to properly target recipients
    - Prevent admins from receiving notifications about their own actions
    - Ensure proper notification routing based on user roles
*/

-- Drop existing notification RLS policies
DO $$
DECLARE
  policy_exists boolean;
BEGIN
  -- Check and drop "Admins can read all notifications"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'notifications' 
    AND policyname = 'Admins can read all notifications'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Admins can read all notifications" ON notifications;
  END IF;
  
  -- Check and drop "Teachers can read their trial notifications"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'notifications' 
    AND policyname = 'Teachers can read their trial notifications'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can read their trial notifications" ON notifications;
  END IF;
END $$;

-- Create new RLS policies for notifications
-- Admins can only see notifications where teacher_id is NULL (intended for admins)
-- or notifications about contract fulfillment
CREATE POLICY "Admins can read admin notifications"
  ON notifications FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' AND
    (
      teacher_id IS NULL OR
      type = 'contract_fulfilled'
    )
  );

-- Teachers can only see notifications where teacher_id matches their own teacher ID
CREATE POLICY "Teachers can read their own notifications"
  ON notifications FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'teacher' AND
    teacher_id IN (
      SELECT t.id FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid()
    )
  );

-- Update the notify_contract_fulfilled function to set teacher_id to NULL
-- This ensures contract fulfillment notifications are only visible to admins
CREATE OR REPLACE FUNCTION notify_contract_fulfilled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  student_name text;
  teacher_name text;
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
      t.name
    INTO 
      student_name,
      student_id_val,
      teacher_name
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
    -- IMPORTANT: teacher_id is set to NULL to ensure it's visible to admins only
    BEGIN
      INSERT INTO notifications (
        type,
        contract_id,
        teacher_id,  -- Set to NULL explicitly
        student_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'contract_fulfilled',
        NEW.id,
        NULL,       -- NULL teacher_id means it's for admins
        student_id_val,
        notification_message,
        false,
        now(),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Log error but don't fail the transaction
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- Update the notify_accepted_trial function to only create admin notifications
-- and ensure teacher_id is NULL for admin notifications
CREATE OR REPLACE FUNCTION notify_accepted_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_name text;
  notification_message text;
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

    -- Insert notification for admins only
    -- IMPORTANT: teacher_id is NULL to ensure it's visible to admins only
    -- and we check that the accepting user is not an admin to prevent self-notifications
    IF NOT EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = accepting_profile_id AND role = 'admin'
    ) THEN
      INSERT INTO notifications (
        type,
        trial_appointment_id,
        teacher_id,  -- Set to NULL explicitly for admin notifications
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'accepted_trial',
        NEW.id,
        NULL,       -- NULL teacher_id means it's for admins
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

-- Update the notify_declined_trial function to create separate notifications
-- for teachers and admins with appropriate teacher_id values
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
BEGIN
  -- Only create notification if status changed from 'assigned' to 'open'
  IF OLD.status = 'assigned' AND NEW.status = 'open' THEN
    
    -- Store the declining teacher's ID to exclude them from notifications
    declining_teacher_id := OLD.teacher_id;
    
    -- Get the declining teacher's name and profile ID
    SELECT name, profile_id INTO declining_teacher_name, declining_profile_id
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
        teacher_record.id,  -- Set teacher_id for teacher notifications
        notification_message_teachers,
        false,
        now(),
        now()
      )
      ON CONFLICT (trial_appointment_id, teacher_id, type) DO NOTHING;
    END LOOP;
    
    -- Insert notification for admins only if the declining user is not an admin
    IF NOT EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = declining_profile_id AND role = 'admin'
    ) THEN
      INSERT INTO notifications (
        type,
        trial_appointment_id,
        teacher_id,  -- Set to NULL explicitly for admin notifications
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'declined_trial',
        NEW.id,
        NULL,       -- NULL teacher_id means it's for admins
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

-- Run cleanup to fix any existing issues
SELECT run_notification_cleanup();