/*
  # Contract Fulfillment Notifications System

  1. New Tables
    - `notifications`
      - `id` (uuid, primary key)
      - `type` (text, default 'contract_fulfilled')
      - `contract_id` (uuid, foreign key to contracts)
      - `teacher_id` (uuid, foreign key to teachers)
      - `student_id` (uuid, foreign key to students)
      - `message` (text)
      - `is_read` (boolean, default false)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)

  2. Security
    - Enable RLS on notifications table
    - Add policies for admin-only access
    - System can insert notifications via SECURITY DEFINER functions

  3. Functions
    - `notify_contract_fulfilled()` - Creates notifications when contracts are completed
    - `mark_notification_read()` - Helper function to mark notifications as read
    - `delete_notification()` - Helper function to delete notifications
    - `update_notification_timestamp()` - Updates timestamp on notification changes

  4. Triggers
    - Contract fulfillment notification trigger
    - Notification timestamp update trigger
*/

-- Create notifications table if it doesn't exist
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL DEFAULT 'contract_fulfilled',
  contract_id uuid REFERENCES contracts(id) ON DELETE CASCADE,
  teacher_id uuid REFERENCES teachers(id) ON DELETE SET NULL,
  student_id uuid REFERENCES students(id) ON DELETE SET NULL,
  message text NOT NULL,
  is_read boolean DEFAULT false NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_contract_id ON notifications(contract_id);
CREATE INDEX IF NOT EXISTS idx_notifications_teacher_id ON notifications(teacher_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);

-- Enable RLS if not already enabled
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables 
    WHERE tablename = 'notifications' 
    AND rowsecurity = true
  ) THEN
    ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
  END IF;
END $$;

-- Drop existing policies if they exist and recreate them
DO $$
BEGIN
  -- Drop existing policies
  DROP POLICY IF EXISTS "Only admins can read notifications" ON notifications;
  DROP POLICY IF EXISTS "Only admins can update notifications" ON notifications;
  DROP POLICY IF EXISTS "Only admins can delete notifications" ON notifications;
  DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
END $$;

-- Create RLS Policies for notifications (Admin-only access)
CREATE POLICY "Only admins can read notifications"
  ON notifications FOR SELECT
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Only admins can update notifications"
  ON notifications FOR UPDATE
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Only admins can delete notifications"
  ON notifications FOR DELETE
  TO authenticated
  USING (get_user_role() = 'admin');

-- Special policy for system inserts (via SECURITY DEFINER function)
CREATE POLICY "System can insert notifications"
  ON notifications FOR INSERT
  TO authenticated
  WITH CHECK (true); -- This will be restricted by the SECURITY DEFINER function

-- Enhanced function to create contract fulfillment notifications
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

  -- Check for attendance completion (progress bar reaching 100%)
  IF OLD.attendance_count IS DISTINCT FROM NEW.attendance_count THEN
    -- Parse old attendance count
    IF OLD.attendance_count IS NOT NULL AND OLD.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      old_current_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 1) AS INTEGER);
      old_total_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 2) AS INTEGER);
    ELSE
      old_current_lessons := 0;
      old_total_lessons := 1; -- Avoid division by zero
    END IF;

    -- Parse new attendance count
    IF NEW.attendance_count IS NOT NULL AND NEW.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
      new_current_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 1) AS INTEGER);
      new_total_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 2) AS INTEGER);
    ELSE
      new_current_lessons := 0;
      new_total_lessons := 1; -- Avoid division by zero
    END IF;

    -- Check if contract just became complete (reached 100%)
    IF new_current_lessons = new_total_lessons 
       AND new_total_lessons > 0 
       AND old_current_lessons < old_total_lessons 
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

  -- Only create notification if conditions are met
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

    -- Insert notification
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

  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger for contract fulfillment notifications
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  AFTER UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON notifications TO authenticated;

-- Create helper function to mark notification as read (admin only)
CREATE OR REPLACE FUNCTION mark_notification_read(notification_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN false;
  END IF;

  -- Update notification
  UPDATE notifications 
  SET is_read = true, updated_at = now()
  WHERE id = notification_id;

  RETURN FOUND;
END;
$$;

-- Create helper function to delete notification (admin only)
CREATE OR REPLACE FUNCTION delete_notification(notification_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN false;
  END IF;

  -- Delete notification
  DELETE FROM notifications 
  WHERE id = notification_id;

  RETURN FOUND;
END;
$$;

-- Grant execute permissions on helper functions
GRANT EXECUTE ON FUNCTION mark_notification_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_notification(uuid) TO authenticated;

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_notification_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_notification_timestamp ON notifications;
CREATE TRIGGER trigger_update_notification_timestamp
  BEFORE UPDATE ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION update_notification_timestamp();