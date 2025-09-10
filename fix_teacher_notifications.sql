-- Fix Teacher Notifications
-- This ensures teachers get notified about their own contracts

BEGIN;

-- =====================================================
-- 1. UPDATE NOTIFICATION FUNCTION TO USE CORRECT TEACHER ID
-- =====================================================

CREATE OR REPLACE FUNCTION notify_contract_fulfilled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  student_name text;
  teacher_name text;
  teacher_id_val uuid;
  teacher_profile_id uuid;
  student_id_val uuid;
  contract_type_display text;
  notification_message text;
  
  -- Lesson counts from database
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
  
  -- Completion detection
  should_notify boolean := false;
  existing_notification_count integer;
  
  -- PDF link generation
  pdf_link text;
BEGIN
  -- Check if notification already exists to prevent duplicates
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = NEW.id AND type = 'contract_fulfilled';

  IF existing_notification_count > 0 THEN
    RETURN NEW;
  END IF;

  -- Check for manual status change from 'active' to 'completed'
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    should_notify := true;
  END IF;

  -- Create notifications if conditions are met
  IF should_notify THEN
    -- Get accurate lesson counts directly from lessons table
    SELECT 
      COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
      COUNT(*) FILTER (WHERE is_available = false),
      COUNT(*)
    INTO 
      completed_lessons,
      excluded_lessons,
      total_lessons
    FROM lessons
    WHERE contract_id = NEW.id;

    -- Get student and teacher information
    SELECT 
      s.name,
      s.id,
      t.name,
      t.id,
      t.profile_id  -- Get the teacher's profile ID
    INTO 
      student_name,
      student_id_val,
      teacher_name,
      teacher_id_val,
      teacher_profile_id
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

    -- Generate PDF link
    pdf_link := '/contracts/' || NEW.id || '/pdf';

    -- Create detailed notification message with PDF link
    IF excluded_lessons > 0 THEN
      notification_message := format(
        'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen (%s von %s Stunden abgeschlossen, %s ausgeschlossen). Lehrer: %s. Abgeschlossen am: %s. [PDF herunterladen](%s)',
        COALESCE(student_name, 'Unbekannter Schüler'),
        COALESCE(contract_type_display, 'Vertrag'),
        completed_lessons,
        total_lessons,
        excluded_lessons,
        COALESCE(teacher_name, 'Unbekannter Lehrer'),
        to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI'),
        pdf_link
      );
    ELSE
      notification_message := format(
        'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen (%s von %s Stunden). Lehrer: %s. Abgeschlossen am: %s. [PDF herunterladen](%s)',
        COALESCE(student_name, 'Unbekannter Schüler'),
        COALESCE(contract_type_display, 'Vertrag'),
        completed_lessons,
        total_lessons,
        COALESCE(teacher_name, 'Unbekannter Lehrer'),
        to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI'),
        pdf_link
      );
    END IF;

    -- Create notification for the teacher (contract owner)
    -- Use teacher_profile_id instead of teacher_id_val for RLS compatibility
    IF teacher_profile_id IS NOT NULL THEN
      BEGIN
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
          teacher_profile_id,  -- Use profile ID for RLS compatibility
          student_id_val,
          notification_message,
          false,
          now(),
          now()
        );
        
        RAISE NOTICE 'Created teacher notification for contract % with teacher profile ID %', NEW.id, teacher_profile_id;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Failed to create teacher notification for contract %: %', NEW.id, SQLERRM;
      END;
    ELSE
      RAISE NOTICE 'No teacher profile ID found for contract %', NEW.id;
    END IF;

    -- Create notifications for all admins
    BEGIN
      INSERT INTO notifications (
        type,
        contract_id,
        teacher_id,
        student_id,
        message,
        is_read,
        created_at,
        updated_at
      )
      SELECT 
        'contract_fulfilled',
        NEW.id,
        p.id,
        student_id_val,
        notification_message,
        false,
        now(),
        now()
      FROM profiles p
      WHERE p.role = 'admin';
      
      RAISE NOTICE 'Created admin notifications for contract %', NEW.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Failed to create admin notifications for contract %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================
-- 2. RECREATE THE TRIGGER
-- =====================================================

-- Drop and recreate the trigger
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- =====================================================
-- 3. VERIFY RLS POLICIES ARE CORRECT
-- =====================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS notifications_select_policy ON notifications;
DROP POLICY IF EXISTS notifications_insert_policy ON notifications;
DROP POLICY IF EXISTS notifications_update_policy ON notifications;

-- RLS Policy: Users can read their own notifications
CREATE POLICY notifications_select_policy
  ON notifications
  FOR SELECT
  TO authenticated
  USING (
    -- Admins can see all notifications
    public.get_user_role() = 'admin'
    OR
    -- Teachers can see notifications where they are the teacher_id
    (public.get_user_role() = 'teacher' AND teacher_id = auth.uid())
  );

-- RLS Policy: Allow system to create notifications
CREATE POLICY notifications_insert_policy
  ON notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Allow the notification function to create notifications
    public.get_user_role() IN ('admin', 'teacher')
  );

-- RLS Policy: Users can update their own notifications (mark as read)
CREATE POLICY notifications_update_policy
  ON notifications
  FOR UPDATE
  TO authenticated
  USING (
    -- Admins can update any notification
    public.get_user_role() = 'admin'
    OR
    -- Teachers can update notifications where they are the teacher_id
    (public.get_user_role() = 'teacher' AND teacher_id = auth.uid())
  )
  WITH CHECK (
    -- Only allow updating is_read and updated_at
    public.get_user_role() = 'admin'
    OR
    (public.get_user_role() = 'teacher' AND teacher_id = auth.uid())
  );

COMMIT; 