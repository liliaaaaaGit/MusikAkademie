-- Update trial_appointments status constraint to include 'assigned'
ALTER TABLE trial_appointments DROP CONSTRAINT IF EXISTS trial_appointments_status_check;
ALTER TABLE trial_appointments ADD CONSTRAINT trial_appointments_status_check 
  CHECK (status IN ('open', 'assigned', 'accepted'));

-- Update notifications table to support trial-related notifications
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS trial_appointment_id uuid REFERENCES trial_appointments(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_notifications_trial_appointment_id ON notifications(trial_appointment_id);

-- Drop existing RLS policies for trial_appointments with better existence checks
DO $$
DECLARE
  policy_exists boolean;
BEGIN
  -- Check and drop "Admins can manage all trial appointments"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Admins can manage all trial appointments'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Admins can manage all trial appointments" ON trial_appointments;
  END IF;
  
  -- Check and drop "Teachers can read all trial appointments"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Teachers can read all trial appointments'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can read all trial appointments" ON trial_appointments;
  END IF;
  
  -- Check and drop "Teachers can create trial appointments"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Teachers can create trial appointments'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can create trial appointments" ON trial_appointments;
  END IF;
  
  -- Check and drop "Teachers can edit own trial appointments"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Teachers can edit own trial appointments'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can edit own trial appointments" ON trial_appointments;
  END IF;
  
  -- Check and drop "Teachers can accept open trials"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Teachers can accept open trials'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can accept open trials" ON trial_appointments;
  END IF;
  
  -- Check and drop "Teachers can only accept open trials"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Teachers can only accept open trials'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can only accept open trials" ON trial_appointments;
  END IF;
  
  -- Check and drop "Only admins can delete trial appointments"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Only admins can delete trial appointments'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Only admins can delete trial appointments" ON trial_appointments;
  END IF;
  
  -- Check and drop "Only admins can create trial appointments"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Only admins can create trial appointments'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Only admins can create trial appointments" ON trial_appointments;
  END IF;
  
  -- Check and drop "Only admins can edit trial appointments"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'trial_appointments' 
    AND policyname = 'Only admins can edit trial appointments'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Only admins can edit trial appointments" ON trial_appointments;
  END IF;
END $$;

-- New RLS policies for trial_appointments
CREATE POLICY "Admins can manage all trial appointments"
  ON trial_appointments FOR ALL
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read relevant trial appointments"
  ON trial_appointments FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    (
      get_user_role() = 'teacher' AND
      (
        status = 'open' OR
        (status IN ('assigned', 'accepted') AND teacher_id IN (
          SELECT t.id FROM teachers t
          JOIN profiles p ON t.profile_id = p.id
          WHERE p.id = auth.uid()
        ))
      )
    )
  );

CREATE POLICY "Only admins can create trial appointments"
  ON trial_appointments FOR INSERT
  TO authenticated
  WITH CHECK (get_user_role() = 'admin');

CREATE POLICY "Only admins can edit trial appointments"
  ON trial_appointments FOR UPDATE
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Only admins can delete trial appointments"
  ON trial_appointments FOR DELETE
  TO authenticated
  USING (get_user_role() = 'admin');

-- Update notifications RLS policies to include trial notifications
DO $$
DECLARE
  policy_exists boolean;
BEGIN
  -- Check and drop "Only admins can read notifications"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'notifications' 
    AND policyname = 'Only admins can read notifications'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Only admins can read notifications" ON notifications;
  END IF;
  
  -- Check and drop "Teachers can read trial notifications"
  SELECT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'notifications' 
    AND policyname = 'Teachers can read trial notifications'
  ) INTO policy_exists;
  
  IF policy_exists THEN
    DROP POLICY "Teachers can read trial notifications" ON notifications;
  END IF;
  
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

CREATE POLICY "Admins can read all notifications"
  ON notifications FOR SELECT
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read their trial notifications"
  ON notifications FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'teacher' AND
    type IN ('assigned_trial', 'declined_trial', 'accepted_trial') AND
    teacher_id IN (
      SELECT t.id FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid()
    )
  );

-- Create decline_trial RPC function
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

-- Update accept_trial function to handle both open and assigned trials
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

-- Grant execute permissions on RPC functions
GRANT EXECUTE ON FUNCTION decline_trial(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION accept_trial(uuid) TO authenticated;

-- Function to create trial assignment notifications
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
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Function to create trial decline notifications
CREATE OR REPLACE FUNCTION notify_declined_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record RECORD;
  notification_message text;
BEGIN
  -- Only create notification if status changed from 'assigned' to 'open'
  IF OLD.status = 'assigned' AND NEW.status = 'open' THEN
    
    -- Create notification message
    notification_message := format(
      'Eine neue Probestunde mit %s ist jetzt verfügbar.',
      NEW.student_name
    );

    -- Insert notification for all teachers
    FOR teacher_record IN SELECT id FROM teachers LOOP
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
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- Function to create trial acceptance notifications
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
    );

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

-- Create triggers for trial notifications
DROP TRIGGER IF EXISTS trigger_notify_assigned_trial ON trial_appointments;
CREATE TRIGGER trigger_notify_assigned_trial
  AFTER INSERT OR UPDATE ON trial_appointments
  FOR EACH ROW
  EXECUTE FUNCTION notify_assigned_trial();

DROP TRIGGER IF EXISTS trigger_notify_declined_trial ON trial_appointments;
CREATE TRIGGER trigger_notify_declined_trial
  AFTER UPDATE ON trial_appointments
  FOR EACH ROW
  EXECUTE FUNCTION notify_declined_trial();

DROP TRIGGER IF EXISTS trigger_notify_accepted_trial ON trial_appointments;
CREATE TRIGGER trigger_notify_accepted_trial
  AFTER UPDATE ON trial_appointments
  FOR EACH ROW
  EXECUTE FUNCTION notify_accepted_trial();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON notifications TO authenticated;
GRANT SELECT, UPDATE ON trial_appointments TO authenticated;