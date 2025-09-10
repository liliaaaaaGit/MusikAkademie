-- Fix notification trigger system to ensure it works properly
-- This migration addresses the issue where notifications aren't being created
-- V2: Fixed function dependency issues

BEGIN;

-- =====================================================
-- 1. DROP CONFLICTING FUNCTIONS FIRST
-- =====================================================

-- Drop the batch_update_lessons function that's causing the conflict
DROP FUNCTION IF EXISTS batch_update_lessons(jsonb);

-- =====================================================
-- 2. ENSURE THE NOTIFICATION FUNCTION EXISTS AND WORKS
-- =====================================================

-- Drop and recreate the notification function with better debugging
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
  available_lessons integer := 0;
  
  -- Completion detection
  was_complete_before boolean := false;
  is_complete_now boolean := false;
  should_notify boolean := false;
  existing_notification_count integer;
  
  -- PDF link generation
  pdf_link text;
BEGIN
  -- Debug logging
  RAISE NOTICE '=== NOTIFICATION TRIGGER FIRED ===';
  RAISE NOTICE 'Contract ID: %, Old Status: %, New Status: %', NEW.id, OLD.status, NEW.status;

  -- Check if notification already exists to prevent duplicates
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = NEW.id AND type = 'contract_fulfilled';

  RAISE NOTICE 'Existing notifications for contract %: %', NEW.id, existing_notification_count;

  IF existing_notification_count > 0 THEN
    RAISE NOTICE 'SKIPPING: Notification already exists for contract %', NEW.id;
    RETURN NEW;
  END IF;

  -- Check for manual status change from 'active' to 'completed'
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    should_notify := true;
    RAISE NOTICE 'CONDITION MET: Manual status change detected: % -> %', OLD.status, NEW.status;
  END IF;

  -- Get accurate lesson counts directly from lessons table
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
    COUNT(*) FILTER (WHERE is_available = false),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_available = true)
  INTO 
    completed_lessons,
    excluded_lessons,
    total_lessons,
    available_lessons
  FROM lessons
  WHERE contract_id = NEW.id;

  RAISE NOTICE 'Lesson counts - Completed: %, Excluded: %, Total: %, Available: %', 
    completed_lessons, excluded_lessons, total_lessons, available_lessons;

  -- Determine completion status based on the rule: completed + excluded >= total_lessons
  is_complete_now := (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0);
  
  RAISE NOTICE 'Completion check - is_complete_now: %, NEW.status: %', is_complete_now, NEW.status;
  
  -- Check if contract just became complete
  IF is_complete_now AND NEW.status = 'active' THEN
    should_notify := true;
    
    -- Automatically mark contract as completed
    UPDATE contracts 
    SET status = 'completed', updated_at = now()
    WHERE id = NEW.id;
    
    -- Update NEW record for consistency
    NEW.status := 'completed';
    RAISE NOTICE 'AUTO-UPDATED: Contract status set to completed';
  END IF;

  -- Create notifications if conditions are met
  IF should_notify THEN
    RAISE NOTICE 'CREATING NOTIFICATIONS for contract %', NEW.id;
    
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
        RAISE NOTICE 'Teacher notification created for teacher %', teacher_id_val;
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
      
      GET DIAGNOSTICS existing_notification_count = ROW_COUNT;
      RAISE NOTICE 'Admin notifications created: %', existing_notification_count;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Failed to create admin notifications for contract %: %', NEW.id, SQLERRM;
    END;
  ELSE
    RAISE NOTICE 'NO NOTIFICATION: should_notify = false';
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================
-- 3. ENSURE THE TRIGGER IS PROPERLY ATTACHED
-- =====================================================

-- Drop and recreate the trigger
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- =====================================================
-- 4. RECREATE THE BATCH LESSON UPDATE FUNCTION
-- =====================================================

-- Recreate the batch lesson update function to check contract completion
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
  contract_record RECORD;
  should_complete boolean := false;
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
    contract_id := contract_ids[i];
    
    -- Get contract details
    SELECT * INTO contract_record
    FROM contracts
    WHERE id = contract_id;
    
    IF FOUND THEN
      -- Check if contract should be marked as completed
      WITH lesson_counts AS (
        SELECT 
          COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL) as completed_lessons,
          COUNT(*) FILTER (WHERE is_available = false) as excluded_lessons,
          COUNT(*) as total_lessons
        FROM lessons
        WHERE contract_id = contract_id
      )
      SELECT 
        (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0)
      INTO should_complete
      FROM lesson_counts;
      
      -- Update contract status if it should be completed
      IF should_complete AND contract_record.status = 'active' THEN
        UPDATE contracts 
        SET status = 'completed', updated_at = now()
        WHERE id = contract_id;
      END IF;
    END IF;
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
-- 5. CREATE A FUNCTION TO MANUALLY TRIGGER NOTIFICATIONS FOR TESTING
-- =====================================================

-- Function to manually trigger notifications for testing
CREATE OR REPLACE FUNCTION force_contract_notification(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  contract_record RECORD;
  result_message text;
BEGIN
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;
  
  -- Manually trigger the notification by updating contract status
  UPDATE contracts 
  SET status = 'completed', updated_at = now()
  WHERE id = contract_id_param;
  
  RETURN 'Notification triggered for contract: ' || contract_id_param;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION force_contract_notification(uuid) TO authenticated;

COMMIT; 