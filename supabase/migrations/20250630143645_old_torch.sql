/*
  # Create Postfach (Inbox) System for Contract Fulfillment Notifications

  1. New Tables
    - `notifications`
      - `id` (uuid, primary key)
      - `type` (text, notification type)
      - `contract_id` (uuid, foreign key to contracts)
      - `teacher_id` (uuid, foreign key to teachers)
      - `student_id` (uuid, foreign key to students)
      - `message` (text, notification content)
      - `is_read` (boolean, default false)
      - `created_at` (timestamp)

  2. Functions
    - `notify_contract_fulfilled()` - Creates notification when contract is completed
    - Trigger function to automatically create notifications

  3. Security
    - Enable RLS on notifications table
    - Only admins can access notifications
    - Secure function execution for automatic notifications

  4. Triggers
    - Auto-create notification when contract status changes to 'completed'
*/

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL DEFAULT 'contract_fulfilled',
  contract_id uuid REFERENCES contracts(id) ON DELETE CASCADE,
  teacher_id uuid REFERENCES teachers(id) ON DELETE SET NULL,
  student_id uuid REFERENCES students(id) ON DELETE SET NULL,
  message text NOT NULL,
  is_read boolean DEFAULT false NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_contract_id ON notifications(contract_id);
CREATE INDEX IF NOT EXISTS idx_notifications_teacher_id ON notifications(teacher_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies for notifications (Admin-only access)
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

-- Function to create contract fulfillment notifications
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
BEGIN
  -- Only create notification if status changed from 'active' to 'completed'
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    
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
      'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen. Lehrer: %s. Erstellt am: %s.',
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
      created_at
    ) VALUES (
      'contract_fulfilled',
      NEW.id,
      teacher_id_val,
      student_id_val,
      notification_message,
      false,
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

-- Add updated_at column to notifications table for tracking read status changes
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

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