/*
  # Fix Trial Lesson Notification System

  1. Changes
    - Add function to notify teachers about new open trial lessons
    - Fix duplicate notification issues by adding unique constraints
    - Improve notification cleanup when trials are accepted
    - Add function to clean up outdated notifications

  2. Security
    - Maintain existing RLS policies
    - Ensure proper access control for notifications
*/

-- Create a unique constraint on notifications to prevent duplicates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'notifications_trial_teacher_unique' 
    AND conrelid = 'notifications'::regclass
  ) THEN
    ALTER TABLE notifications 
    ADD CONSTRAINT notifications_trial_teacher_unique 
    UNIQUE (trial_appointment_id, teacher_id, type);
  END IF;
EXCEPTION WHEN undefined_table THEN
  -- Table doesn't exist, constraint can't be added
  NULL;
END $$;

-- Function to notify teachers about new open trial lessons
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
    
    -- Create notification message
    notification_message := format(
      'Eine neue Probestunde mit %s ist jetzt verfügbar.',
      NEW.student_name
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

-- Create trigger for new open trial notifications
DROP TRIGGER IF EXISTS trigger_notify_new_open_trial ON trial_appointments;
CREATE TRIGGER trigger_notify_new_open_trial
  AFTER INSERT OR UPDATE ON trial_appointments
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_open_trial();

-- Improve the assigned trial notification function to handle duplicates
CREATE OR REPLACE FUNCTION notify_assigned_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_name text;
  notification_message text;
BEGIN
  -- Only create notification if status changed to 'assigned' and teacher_id is set
  IF NEW.status = 'assigned' AND NEW.teacher_id IS NOT NULL AND
     (OLD IS NULL OR OLD.status != 'assigned' OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id) THEN
    
    -- Get teacher name
    SELECT name INTO teacher_name
    FROM teachers
    WHERE id = NEW.teacher_id;

    -- Create notification message
    notification_message := format(
      'Sie wurden einer neuen Probestunde mit %s zugewiesen. Bitte nehmen Sie an oder lehnen Sie ab.',
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

-- Improve the declined trial notification function to handle duplicates
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
    
    -- Create notification message
    notification_message := format(
      'Eine neue Probestunde mit %s ist jetzt verfügbar.',
      NEW.student_name
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

-- Improve the accepted trial notification function to clean up other notifications
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

    -- Create notification message
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

-- Function to clean up outdated notifications
CREATE OR REPLACE FUNCTION cleanup_trial_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  accepted_trials uuid[];
BEGIN
  -- Get all accepted trial IDs
  SELECT array_agg(id) INTO accepted_trials
  FROM trial_appointments
  WHERE status = 'accepted';
  
  -- If there are accepted trials, clean up their notifications
  IF accepted_trials IS NOT NULL AND array_length(accepted_trials, 1) > 0 THEN
    -- Delete all open and assigned notifications for accepted trials
    DELETE FROM notifications
    WHERE trial_appointment_id = ANY(accepted_trials)
    AND type IN ('declined_trial', 'assigned_trial');
  END IF;
END;
$$;

-- Create a function to run cleanup on demand
CREATE OR REPLACE FUNCTION run_notification_cleanup()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count integer;
BEGIN
  -- Only allow admins to run this function
  IF get_user_role() != 'admin' THEN
    RETURN 'Access denied: Only administrators can run notification cleanup';
  END IF;
  
  -- Count notifications before cleanup
  WITH before_count AS (
    SELECT COUNT(*) as cnt FROM notifications
  )
  -- Run cleanup and count deleted rows
  SELECT COUNT(*) INTO deleted_count
  FROM notifications
  WHERE (
    -- Find notifications for accepted trials that aren't acceptance notifications
    trial_appointment_id IN (
      SELECT id FROM trial_appointments WHERE status = 'accepted'
    )
    AND type IN ('declined_trial', 'assigned_trial')
  )
  OR (
    -- Find notifications for trials that no longer exist
    trial_appointment_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM trial_appointments WHERE id = trial_appointment_id
    )
  );
  
  -- Delete the outdated notifications
  DELETE FROM notifications
  WHERE (
    -- Find notifications for accepted trials that aren't acceptance notifications
    trial_appointment_id IN (
      SELECT id FROM trial_appointments WHERE status = 'accepted'
    )
    AND type IN ('declined_trial', 'assigned_trial')
  )
  OR (
    -- Find notifications for trials that no longer exist
    trial_appointment_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM trial_appointments WHERE id = trial_appointment_id
    )
  );
  
  RETURN format('Notification cleanup complete. Removed %s outdated notifications.', deleted_count);
END;
$$;

-- Grant execute permission on cleanup function
GRANT EXECUTE ON FUNCTION run_notification_cleanup() TO authenticated;

-- Update the accept_trial function to clean up notifications
CREATE OR REPLACE FUNCTION accept_trial(_trial_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_teacher_id uuid;
  trial_record RECORD;
BEGIN
  -- Get the current user's teacher ID
  SELECT t.id INTO current_teacher_id
  FROM teachers t
  JOIN profiles p ON t.profile_id = p.id
  WHERE p.id = auth.uid();
  
  IF current_teacher_id IS NULL THEN
    RAISE EXCEPTION 'Teacher profile not found';
  END IF;
  
  -- Get trial appointment details
  SELECT * INTO trial_record
  FROM trial_appointments
  WHERE id = _trial_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Trial appointment not found';
  END IF;
  
  -- Check if trial can be accepted
  IF trial_record.status = 'assigned' THEN
    -- Only assigned teacher can accept assigned trials
    IF trial_record.teacher_id != current_teacher_id THEN
      RAISE EXCEPTION 'You are not assigned to this trial appointment';
    END IF;
  ELSIF trial_record.status = 'open' THEN
    -- Any teacher can accept open trials
    NULL; -- No additional check needed
  ELSE
    RAISE EXCEPTION 'Trial appointment cannot be accepted in current status';
  END IF;
  
  -- Delete all existing notifications for this trial for all teachers except the accepting one
  DELETE FROM notifications
  WHERE trial_appointment_id = _trial_id 
  AND type IN ('declined_trial', 'assigned_trial')
  AND (teacher_id != current_teacher_id OR teacher_id IS NULL);
  
  -- Update trial appointment to accepted status
  UPDATE trial_appointments
  SET
    status = 'accepted',
    teacher_id = current_teacher_id
  WHERE id = _trial_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Failed to accept trial appointment';
  END IF;
END;
$$;

-- Update the decline_trial function to clean up notifications
CREATE OR REPLACE FUNCTION decline_trial(_trial_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_teacher_id uuid;
  trial_record RECORD;
BEGIN
  -- Get the current user's teacher ID
  SELECT t.id INTO current_teacher_id
  FROM teachers t
  JOIN profiles p ON t.profile_id = p.id
  WHERE p.id = auth.uid();
  
  IF current_teacher_id IS NULL THEN
    RAISE EXCEPTION 'Teacher profile not found';
  END IF;
  
  -- Get trial appointment details
  SELECT * INTO trial_record
  FROM trial_appointments
  WHERE id = _trial_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Trial appointment not found';
  END IF;
  
  -- Check if the teacher is assigned to this trial
  IF trial_record.teacher_id != current_teacher_id THEN
    RAISE EXCEPTION 'You are not assigned to this trial appointment';
  END IF;
  
  -- Check if the trial is in assigned status
  IF trial_record.status != 'assigned' THEN
    RAISE EXCEPTION 'Trial appointment is not in assigned status';
  END IF;
  
  -- Delete the assigned notification for this teacher
  DELETE FROM notifications
  WHERE trial_appointment_id = _trial_id
  AND teacher_id = current_teacher_id
  AND type = 'assigned_trial';
  
  -- Update trial appointment to open status and remove teacher assignment
  UPDATE trial_appointments
  SET
    status = 'open',
    teacher_id = NULL
  WHERE id = _trial_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Failed to decline trial appointment';
  END IF;
END;
$$;

-- Run initial cleanup to fix any existing issues
SELECT run_notification_cleanup();