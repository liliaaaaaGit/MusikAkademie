-- Fix Concurrency Issue in Lesson Tracking
-- This fixes the "tuple to be updated was already modified" error

BEGIN;

-- =====================================================
-- 1. FIX BATCH UPDATE LESSONS FUNCTION (Remove Contract Status Update)
-- =====================================================

-- Drop and recreate the function WITHOUT automatic contract status update
-- Let the trigger handle contract completion instead
CREATE OR REPLACE FUNCTION batch_update_lessons(updates jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  update_record jsonb;
  lesson_id_val uuid;
  contract_id_val uuid;
  success_count integer := 0;
  error_count integer := 0;
  error_messages text[] := '{}';
BEGIN
  -- Process each update
  FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    BEGIN
      lesson_id_val := (update_record->>'id')::uuid;
      contract_id_val := (update_record->>'contract_id')::uuid;

      -- Update the lesson with explicit table references
      UPDATE lessons 
      SET 
        date = CASE WHEN update_record->>'date' IS NOT NULL AND update_record->>'date' != '' 
                    THEN (update_record->>'date')::date ELSE NULL END,
        comment = CASE WHEN update_record->>'comment' IS NOT NULL AND update_record->>'comment' != '' 
                       THEN update_record->>'comment' ELSE NULL END,
        is_available = (update_record->>'is_available')::boolean,
        updated_at = now()
      WHERE lessons.id = lesson_id_val AND lessons.contract_id = contract_id_val;

      IF FOUND THEN
        success_count := success_count + 1;
      ELSE
        error_count := error_count + 1;
        error_messages := array_append(error_messages, format('Lesson %s not found or contract mismatch', lesson_id_val));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      error_messages := array_append(error_messages, format('Error updating lesson %s: %s', lesson_id_val, SQLERRM));
    END;
  END LOOP;

  -- Return result
  RETURN jsonb_build_object(
    'success', error_count = 0,
    'success_count', success_count,
    'error_count', error_count,
    'errors', error_messages
  );
END;
$$;

-- =====================================================
-- 2. CREATE SEPARATE FUNCTION TO CHECK CONTRACT COMPLETION
-- =====================================================

-- Create a function that can be called after lesson updates to check completion
CREATE OR REPLACE FUNCTION check_contract_completion_after_lessons(contract_id_param uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
  contract_record RECORD;
BEGIN
  -- Get lesson counts
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
    COUNT(*) FILTER (WHERE is_available = false),
    COUNT(*)
  INTO 
    completed_lessons,
    excluded_lessons,
    total_lessons
  FROM lessons
  WHERE contract_id = contract_id_param;

  -- Check if contract should be completed
  IF (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0) THEN
    -- Get current contract status
    SELECT * INTO contract_record
    FROM contracts
    WHERE id = contract_id_param;
    
    -- Only update if not already completed
    IF contract_record.status = 'active' THEN
      UPDATE contracts
      SET status = 'completed', updated_at = now()
      WHERE id = contract_id_param;
      
      RETURN true; -- Status was updated
    END IF;
  END IF;

  RETURN false; -- No update needed
END;
$$;

-- =====================================================
-- 3. UPDATE NOTIFICATION FUNCTION TO HANDLE COMPLETION
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
    IF teacher_id_val IS NOT NULL THEN
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
          teacher_id_val,
          student_id_val,
          notification_message,
          false,
          now(),
          now()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Failed to create teacher notification for contract %: %', NEW.id, SQLERRM;
      END;
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
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Failed to create admin notifications for contract %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================
-- 4. RECREATE THE TRIGGER
-- =====================================================

-- Drop and recreate the trigger
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

COMMIT; 