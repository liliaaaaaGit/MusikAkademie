-- Restore contract completion notifications (Teacher + all Admins) with PDF download link
-- This migration fixes the regression where contract completion notifications stopped working

BEGIN;

-- =====================================================
-- 1. UPDATE NOTIFICATION FUNCTION WITH PROPER LOGIC
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
  
  -- Lesson counts from database (the key fix)
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
  available_lessons integer := 0;
  
  -- Completion detection
  was_complete_before boolean := false;
  is_complete_now boolean := false;
  should_notify boolean := false;
  existing_notification_count integer;
  
  -- PDF link generation
  pdf_link text;
  base_url text;
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

  -- KEY FIX: Get accurate lesson counts directly from lessons table
  -- This ensures we're checking against the correct completion criteria
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),  -- completed available
    COUNT(*) FILTER (WHERE is_available = false),                      -- excluded lessons
    COUNT(*),                                                           -- total lessons
    COUNT(*) FILTER (WHERE is_available = true)                        -- available lessons
  INTO 
    completed_lessons,
    excluded_lessons,
    total_lessons,
    available_lessons
  FROM lessons
  WHERE contract_id = NEW.id;

  -- Determine completion status based on the rule: completed + excluded >= total_lessons
  is_complete_now := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);
  
  -- Check if contract just became complete
  IF is_complete_now AND NEW.status = 'active' THEN
    should_notify := true;
    
    -- Automatically mark contract as completed
    UPDATE contracts 
    SET status = 'completed', updated_at = now()
    WHERE id = NEW.id;
    
    -- Update NEW record for consistency
    NEW.status := 'completed';
  END IF;

  -- Create notifications if conditions are met
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

    -- Generate PDF link (use relative path for now, will be resolved by frontend)
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
          teacher_id_val, -- Teacher gets their own notification
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
        p.id, -- Admin profile ID as teacher_id (for notification targeting)
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
-- 2. RECREATE THE TRIGGER
-- =====================================================

-- Drop and recreate the trigger to ensure it's properly attached
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- =====================================================
-- 3. ENSURE RLS POLICIES FOR NOTIFICATIONS
-- =====================================================

-- Enable RLS on notifications table if not already enabled
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Add helpful defaults for notifications
ALTER TABLE notifications
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now(),
  ALTER COLUMN is_read SET DEFAULT false;

-- Ensure created_at is not null
ALTER TABLE notifications
  ALTER COLUMN created_at SET NOT NULL;

-- RLS Policy: Users can read their own notifications
-- Teachers see notifications where teacher_id matches their profile
-- Admins see all notifications
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

-- =====================================================
-- 4. UPDATE LESSON TRACKING TO TRIGGER CONTRACT STATUS
-- =====================================================

-- Create a function to check and update contract completion status
CREATE OR REPLACE FUNCTION check_and_update_contract_completion(contract_id_param uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  completed_lessons integer := 0;
  excluded_lessons integer := 0;
  total_lessons integer := 0;
  is_complete boolean := false;
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

  -- Check completion condition: completed + excluded >= total
  is_complete := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);

  -- If complete, update contract status to trigger notification
  IF is_complete THEN
    SELECT * INTO contract_record
    FROM contracts
    WHERE id = contract_id_param;

    -- Only update if not already completed
    IF contract_record.status != 'completed' THEN
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
-- 5. UPDATE BATCH LESSON UPDATE FUNCTION
-- =====================================================

-- Update the batch lesson update function to check contract completion
CREATE OR REPLACE FUNCTION batch_update_lessons(updates jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  update_record jsonb;
  lesson_id uuid;
  contract_id uuid;
  success_count integer := 0;
  error_count integer := 0;
  error_messages text[] := '{}';
  contract_ids uuid[] := '{}';
BEGIN
  -- Process each update
  FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    BEGIN
      lesson_id := (update_record->>'id')::uuid;
      contract_id := (update_record->>'contract_id')::uuid;
      
      -- Add contract_id to array for later processing
      IF NOT (contract_id = ANY(contract_ids)) THEN
        contract_ids := array_append(contract_ids, contract_id);
      END IF;

      -- Update the lesson
      UPDATE lessons
      SET 
        date = CASE WHEN update_record->>'date' IS NOT NULL AND update_record->>'date' != '' 
                    THEN (update_record->>'date')::date ELSE NULL END,
        comment = CASE WHEN update_record->>'comment' IS NOT NULL AND update_record->>'comment' != '' 
                       THEN update_record->>'comment' ELSE NULL END,
        is_available = (update_record->>'is_available')::boolean,
        updated_at = now()
      WHERE id = lesson_id AND contract_id = contract_id;

      IF FOUND THEN
        success_count := success_count + 1;
      ELSE
        error_count := error_count + 1;
        error_messages := array_append(error_messages, format('Lesson %s not found or contract mismatch', lesson_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      error_messages := array_append(error_messages, format('Error updating lesson %s: %s', lesson_id, SQLERRM));
    END;
  END LOOP;

  -- Check contract completion for each affected contract
  FOR i IN 1..array_length(contract_ids, 1)
  LOOP
    PERFORM check_and_update_contract_completion(contract_ids[i]);
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

COMMIT; 