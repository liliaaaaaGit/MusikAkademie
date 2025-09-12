-- Fix contract completion notification trigger to use contracts.teacher_id instead of students.teacher_id
-- This fixes the "column s.teacher_id does not exist" error when completing contracts

BEGIN;

-- 1) Drop the existing problematic trigger function
DROP FUNCTION IF EXISTS public.notify_contract_completion();

-- 2) Create the fixed trigger function that uses contracts.teacher_id
CREATE OR REPLACE FUNCTION public.notify_contract_completion()
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

  -- Determine completion status based on the rule: completed + excluded >= total_lessons
  IF (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0) AND NEW.status = 'active' THEN
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
    -- FIXED: Get student and teacher information using contracts.teacher_id instead of students.teacher_id
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
    LEFT JOIN teachers t ON t.id = NEW.teacher_id  -- FIXED: Use contracts.teacher_id instead of students.teacher_id
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

    -- Generate PDF link (placeholder for now)
    pdf_link := 'https://musikakademie-muenchen.de/contracts/' || NEW.id::text || '/pdf';

    -- Create notification message
    notification_message := format(
      'Vertrag "%s" von %s (%s) wurde erfolgreich abgeschlossen!',
      contract_type_display,
      student_name,
      NEW.id::text
    );

    -- Insert notification for admin
    INSERT INTO notifications (
      type,
      title,
      message,
      contract_id,
      student_id,
      teacher_id,
      metadata,
      created_at
    ) VALUES (
      'contract_fulfilled',
      'Vertrag abgeschlossen',
      notification_message,
      NEW.id,
      student_id_val,
      teacher_id_val,
      jsonb_build_object(
        'contract_type', contract_type_display,
        'student_name', student_name,
        'teacher_name', teacher_name,
        'pdf_link', pdf_link,
        'completed_lessons', completed_lessons,
        'total_lessons', total_lessons,
        'excluded_lessons', excluded_lessons
      ),
      now()
    );

    RAISE NOTICE 'Created contract completion notification for contract %', NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- 3) Recreate the trigger
DROP TRIGGER IF EXISTS trigger_contract_completion ON contracts;

CREATE TRIGGER trigger_contract_completion
  AFTER UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_contract_completion();

-- 4) Grant permissions
GRANT EXECUTE ON FUNCTION public.notify_contract_completion() TO authenticated;

COMMIT;
