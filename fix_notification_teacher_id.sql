-- Fix Notification Teacher ID Issue
-- The notifications are being created but teacher_id is null

BEGIN;

-- =====================================================
-- 1. CHECK CURRENT NOTIFICATION FUNCTION
-- =====================================================

-- Let's see what the current function looks like
SELECT prosrc FROM pg_proc WHERE proname = 'notify_contract_fulfilled';

-- =====================================================
-- 2. FIX THE NOTIFICATION FUNCTION
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
-- 3. RECREATE THE TRIGGER
-- =====================================================

-- Drop and recreate the trigger
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- =====================================================
-- 4. FIX EXISTING NOTIFICATIONS
-- =====================================================

-- Update existing notifications to have the correct teacher_id
UPDATE notifications 
SET teacher_id = t.profile_id
FROM students s
JOIN teachers t ON s.teacher_id = t.id
WHERE notifications.contract_id = s.id
  AND notifications.type = 'contract_fulfilled'
  AND notifications.teacher_id IS NULL
  AND t.profile_id IS NOT NULL;

-- =====================================================
-- 5. VERIFY THE FIX
-- =====================================================

-- Check if notifications now have teacher_id set
SELECT 
  n.id,
  n.type,
  n.contract_id,
  n.teacher_id,
  n.student_id,
  n.message,
  n.is_read,
  n.created_at,
  p.full_name as teacher_name,
  p.role as teacher_role
FROM notifications n
LEFT JOIN profiles p ON n.teacher_id = p.id
WHERE n.contract_id IN (
  '110e3cdf-c1d6-4de1-bec3-f24fddc72589',
  'd845d143-68b6-45d4-8619-e9dadc4705ec',
  'ffed5251-283d-45ea-95a5-063493f65f4e'
)
ORDER BY n.created_at DESC;

COMMIT; 