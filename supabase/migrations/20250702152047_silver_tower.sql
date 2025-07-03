/*
  # Fix Contract Fulfillment Notification Logic

  1. Changes
    - Update the notify_contract_fulfilled function to consider excluded/unavailable lessons
    - Fix notification logic to trigger when all available lessons are completed
    - Ensure admins receive notifications when contracts are truly fulfilled
    - Prevent duplicate notifications

  2. Key Fixes
    - Check if completed lessons equals available lessons (not total lessons)
    - Use lesson availability data from lessons table for accurate completion detection
    - Ensure notifications are sent to admins only
    - Improve notification message with more details
*/

-- Update the notify_contract_fulfilled function to properly handle excluded lessons
CREATE OR REPLACE FUNCTION notify_contract_fulfilled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  student_name text;
  teacher_name text;
  student_id_val uuid;
  contract_type_display text;
  notification_message text;
  completed_lessons integer := 0;
  available_lessons integer := 0;
  total_lessons integer := 0;
  unavailable_lessons integer := 0;
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

  -- Check for attendance completion based on available lessons
  IF OLD.attendance_count IS DISTINCT FROM NEW.attendance_count THEN
    -- Get accurate lesson counts directly from the lessons table
    SELECT 
      COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true),
      COUNT(*) FILTER (WHERE is_available = true),
      COUNT(*),
      COUNT(*) FILTER (WHERE is_available = false)
    INTO 
      completed_lessons,
      available_lessons,
      total_lessons,
      unavailable_lessons
    FROM lessons
    WHERE contract_id = NEW.id;
    
    -- Check if all available lessons are completed (100% of relevant lessons)
    IF completed_lessons > 0 AND available_lessons > 0 AND
       completed_lessons = available_lessons AND
       NEW.status = 'active' THEN
      
      should_notify := true;
      
      -- Automatically mark contract as completed when all available lessons are done
      UPDATE contracts 
      SET status = 'completed', updated_at = now()
      WHERE id = NEW.id;
      
      -- Update NEW record for consistency
      NEW.status := 'completed';
    END IF;
  END IF;

  -- Create notification if conditions are met
  IF should_notify THEN
    -- Get student and teacher information
    SELECT 
      s.name,
      s.id,
      t.name
    INTO 
      student_name,
      student_id_val,
      teacher_name
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

    -- Create enhanced notification message with more details
    notification_message := format(
      'Ein Vertrag wurde vollständig erfüllt. %s hat den %s erfolgreich abgeschlossen (%s von %s relevanten Stunden). Lehrer: %s.',
      COALESCE(student_name, 'Unbekannter Schüler'),
      COALESCE(contract_type_display, 'Vertrag'),
      completed_lessons,
      available_lessons,
      COALESCE(teacher_name, 'Unbekannter Lehrer')
    );

    -- Insert notification with error handling
    -- IMPORTANT: teacher_id is set to NULL to ensure it's visible to admins only
    BEGIN
      INSERT INTO notifications (
        type,
        contract_id,
        teacher_id,  -- Set to NULL explicitly
        student_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'contract_fulfilled',
        NEW.id,
        NULL,       -- NULL teacher_id means it's for admins
        student_id_val,
        notification_message,
        false,
        now(),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Log error but don't fail the transaction
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate the trigger to ensure it's properly attached
DROP TRIGGER IF EXISTS trigger_contract_fulfilled_notification ON contracts;
CREATE TRIGGER trigger_contract_fulfilled_notification
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION notify_contract_fulfilled();

-- Create a function to manually trigger contract fulfillment notifications
-- This can be used to fix contracts that were completed but didn't send notifications
CREATE OR REPLACE FUNCTION force_contract_fulfillment_notification(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  student_name text;
  teacher_name text;
  student_id_val uuid;
  contract_type_display text;
  notification_message text;
  completed_lessons integer := 0;
  available_lessons integer := 0;
  total_lessons integer := 0;
  unavailable_lessons integer := 0;
  existing_notification_count integer;
  contract_record RECORD;
  result_message text;
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN 'Access denied: Only administrators can force contract notifications';
  END IF;
  
  -- Check if notification already exists
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  IF existing_notification_count > 0 THEN
    RETURN 'Notification already exists for this contract';
  END IF;
  
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;
  
  -- Get accurate lesson counts directly from the lessons table
  SELECT 
    COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true),
    COUNT(*) FILTER (WHERE is_available = true),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_available = false)
  INTO 
    completed_lessons,
    available_lessons,
    total_lessons,
    unavailable_lessons
  FROM lessons
  WHERE contract_id = contract_id_param;
  
  -- Get student and teacher information
  SELECT 
    s.name,
    s.id,
    t.name
  INTO 
    student_name,
    student_id_val,
    teacher_name
  FROM students s
  LEFT JOIN teachers t ON s.teacher_id = t.id
  WHERE s.id = contract_record.student_id;

  -- Get contract type display name
  SELECT 
    COALESCE(cv.name, 
      CASE contract_record.type
        WHEN 'ten_class_card' THEN '10er Karte'
        WHEN 'half_year' THEN 'Halbjahresvertrag'
        ELSE contract_record.type
      END
    )
  INTO contract_type_display
  FROM contracts c
  LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
  WHERE c.id = contract_id_param;

  -- Create enhanced notification message with more details
  notification_message := format(
    'Ein Vertrag wurde vollständig erfüllt. %s hat den %s erfolgreich abgeschlossen (%s von %s relevanten Stunden). Lehrer: %s.',
    COALESCE(student_name, 'Unbekannter Schüler'),
    COALESCE(contract_type_display, 'Vertrag'),
    completed_lessons,
    available_lessons,
    COALESCE(teacher_name, 'Unbekannter Lehrer')
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
    contract_id_param,
    NULL,
    student_id_val,
    notification_message,
    false,
    now(),
    now()
  );
  
  -- Mark contract as completed if not already
  IF contract_record.status != 'completed' THEN
    UPDATE contracts
    SET status = 'completed', updated_at = now()
    WHERE id = contract_id_param;
    
    result_message := format(
      'Notification created and contract marked as completed. Lessons: %s completed of %s available (total: %s, unavailable: %s).',
      completed_lessons, available_lessons, total_lessons, unavailable_lessons
    );
  ELSE
    result_message := format(
      'Notification created for already completed contract. Lessons: %s completed of %s available (total: %s, unavailable: %s).',
      completed_lessons, available_lessons, total_lessons, unavailable_lessons
    );
  END IF;
  
  RETURN result_message;
END;
$$;

-- Grant execute permission on force notification function
GRANT EXECUTE ON FUNCTION force_contract_fulfillment_notification(uuid) TO authenticated;

-- Create a function to check contract completion status
CREATE OR REPLACE FUNCTION check_contract_completion_status(contract_id_param uuid)
RETURNS TABLE(
  contract_id uuid,
  student_name text,
  teacher_name text,
  contract_type text,
  status text,
  completed_lessons bigint,
  available_lessons bigint,
  total_lessons bigint,
  unavailable_lessons bigint,
  completion_percentage numeric,
  has_notification boolean,
  is_fully_completed boolean
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  WITH lesson_counts AS (
    SELECT 
      COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true) as completed,
      COUNT(*) FILTER (WHERE is_available = true) as available,
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE is_available = false) as unavailable
    FROM lessons
    WHERE contract_id = contract_id_param
  ),
  notification_check AS (
    SELECT COUNT(*) > 0 as has_notification
    FROM notifications
    WHERE contract_id = contract_id_param AND type = 'contract_fulfilled'
  )
  SELECT 
    c.id as contract_id,
    s.name as student_name,
    t.name as teacher_name,
    COALESCE(cv.name, 
      CASE c.type
        WHEN 'ten_class_card' THEN '10er Karte'
        WHEN 'half_year' THEN 'Halbjahresvertrag'
        ELSE c.type
      END
    ) as contract_type,
    c.status,
    lc.completed as completed_lessons,
    lc.available as available_lessons,
    lc.total as total_lessons,
    lc.unavailable as unavailable_lessons,
    CASE 
      WHEN lc.available > 0 
      THEN ROUND((lc.completed::numeric / lc.available::numeric) * 100, 2)
      ELSE 0
    END as completion_percentage,
    nc.has_notification,
    (lc.completed = lc.available AND lc.available > 0) as is_fully_completed
  FROM 
    contracts c
    JOIN students s ON c.student_id = s.id
    LEFT JOIN teachers t ON s.teacher_id = t.id
    LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
    CROSS JOIN lesson_counts lc
    CROSS JOIN notification_check nc
  WHERE 
    c.id = contract_id_param;
$$;

-- Grant execute permission on check function
GRANT EXECUTE ON FUNCTION check_contract_completion_status(uuid) TO authenticated;

-- Create a function to find contracts that should have notifications but don't
CREATE OR REPLACE FUNCTION find_missing_contract_notifications()
RETURNS TABLE(
  contract_id uuid,
  student_name text,
  teacher_name text,
  contract_type text,
  status text,
  completed_lessons bigint,
  available_lessons bigint,
  completion_percentage numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  WITH contract_data AS (
    SELECT 
      c.id as contract_id,
      s.name as student_name,
      t.name as teacher_name,
      COALESCE(cv.name, 
        CASE c.type
          WHEN 'ten_class_card' THEN '10er Karte'
          WHEN 'half_year' THEN 'Halbjahresvertrag'
          ELSE c.type
        END
      ) as contract_type,
      c.status,
      COUNT(l.id) FILTER (WHERE l.date IS NOT NULL AND l.is_available = true) as completed_lessons,
      COUNT(l.id) FILTER (WHERE l.is_available = true) as available_lessons,
      CASE 
        WHEN COUNT(l.id) FILTER (WHERE l.is_available = true) > 0 
        THEN ROUND((COUNT(l.id) FILTER (WHERE l.date IS NOT NULL AND l.is_available = true)::numeric / 
                   COUNT(l.id) FILTER (WHERE l.is_available = true)::numeric) * 100, 2)
        ELSE 0
      END as completion_percentage
    FROM 
      contracts c
      JOIN students s ON c.student_id = s.id
      LEFT JOIN teachers t ON s.teacher_id = t.id
      LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
      LEFT JOIN lessons l ON c.id = l.contract_id
    GROUP BY 
      c.id, s.name, t.name, cv.name, c.type, c.status
  )
  SELECT 
    cd.*
  FROM 
    contract_data cd
    LEFT JOIN notifications n ON cd.contract_id = n.contract_id AND n.type = 'contract_fulfilled'
  WHERE 
    n.id IS NULL AND
    (
      (cd.status = 'completed') OR
      (cd.completed_lessons = cd.available_lessons AND cd.available_lessons > 0)
    )
  ORDER BY 
    cd.completion_percentage DESC, cd.student_name;
$$;

-- Grant execute permission on find missing notifications function
GRANT EXECUTE ON FUNCTION find_missing_contract_notifications() TO authenticated;

-- Run cleanup to fix any existing issues
SELECT run_notification_cleanup();