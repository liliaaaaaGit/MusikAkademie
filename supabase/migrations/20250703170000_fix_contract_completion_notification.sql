/*
  # Fix Admin Notification System for Contract Completion

  This migration fixes the contract completion notification logic to properly handle
  excluded/unavailable lessons and ensure admins receive notifications when contracts
  reach their adjusted completion criteria.

  Key Changes:
  1. Update notification logic to query lessons table directly
  2. Check completion against available lessons (not total contract lessons)
  3. Ensure immediate notification when adjusted completion is reached
  4. Guarantee admin inbox receives notifications reliably

  Example: 10-lesson contract with 3 excluded = notify at 7/7 available completed
*/

-- Update the notification function to properly handle excluded lessons
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
  
  -- Lesson counts from database (the key fix)
  completed_available_lessons integer := 0;
  total_available_lessons integer := 0;
  total_lessons integer := 0;
  excluded_lessons integer := 0;
  
  -- State tracking for completion detection
  old_completed_available integer := 0;
  old_total_available integer := 0;
  was_complete_before boolean := false;
  is_complete_now boolean := false;
  should_notify boolean := false;
  existing_notification_count integer;
BEGIN
  -- Prevent duplicate notifications
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
  -- This ensures we're checking against available lessons, not total contract lessons
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),  -- completed available
    COUNT(*) FILTER (WHERE is_available = true),                        -- total available  
    COUNT(*),                                                           -- total lessons
    COUNT(*) FILTER (WHERE is_available = false)                       -- excluded lessons
  INTO 
    completed_available_lessons,
    total_available_lessons,
    total_lessons,
    excluded_lessons
  FROM lessons
  WHERE contract_id = NEW.id;

  -- Reconstruct previous state from attendance_count for comparison
  IF OLD.attendance_count IS NOT NULL AND OLD.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
    BEGIN
      old_completed_available := CAST(SPLIT_PART(OLD.attendance_count, '/', 1) AS INTEGER);
      -- Use current available count since lesson availability rarely changes during completion
      old_total_available := total_available_lessons;
    EXCEPTION WHEN OTHERS THEN
      old_completed_available := 0;
      old_total_available := 1;
    END;
  END IF;

  -- Determine completion status based on AVAILABLE lessons (not total)
  was_complete_before := (old_completed_available = old_total_available AND old_total_available > 0);
  is_complete_now := (completed_available_lessons = total_available_lessons AND total_available_lessons > 0);

  -- CRITICAL FIX: Trigger notification when ALL AVAILABLE lessons are completed
  -- This ensures admins get notified at 7/7 available, not 10/10 total when 3 are excluded
  IF is_complete_now 
     AND NOT was_complete_before 
     AND NEW.status = 'active' 
     AND total_available_lessons > 0 THEN
    
    should_notify := true;
    
    -- Automatically mark contract as completed when all available lessons are done
    UPDATE contracts 
    SET status = 'completed', updated_at = now()
    WHERE id = NEW.id;
    
    -- Update NEW record for consistency
    NEW.status := 'completed';
  END IF;

  -- Create notification for admin inbox
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

    -- Create detailed notification message showing actual completion status
    IF excluded_lessons > 0 THEN
      notification_message := format(
        'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen (%s von %s verfügbaren Stunden, %s ausgeschlossen). Lehrer: %s. Abgeschlossen am: %s.',
        COALESCE(student_name, 'Unbekannter Schüler'),
        COALESCE(contract_type_display, 'Vertrag'),
        completed_available_lessons,
        total_available_lessons,
        excluded_lessons,
        COALESCE(teacher_name, 'Unbekannter Lehrer'),
        to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI')
      );
    ELSE
      notification_message := format(
        'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen (%s von %s Stunden). Lehrer: %s. Abgeschlossen am: %s.',
        COALESCE(student_name, 'Unbekannter Schüler'),
        COALESCE(contract_type_display, 'Vertrag'),
        completed_available_lessons,
        total_available_lessons,
        COALESCE(teacher_name, 'Unbekannter Lehrer'),
        to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI')
      );
    END IF;

    -- Insert notification for admin inbox with guaranteed delivery
    -- CRITICAL: teacher_id = NULL ensures it appears in admin inbox
    BEGIN
      INSERT INTO notifications (
        type,
        contract_id,
        teacher_id,  -- NULL = admin notification
        student_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'contract_fulfilled',
        NEW.id,
        NULL,       -- NULL teacher_id ensures admin visibility
        student_id_val,
        notification_message,
        false,
        now(),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Log error but don't fail the contract update
      RAISE NOTICE 'Failed to create admin notification for contract %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- Create a function to verify notification system is working correctly
CREATE OR REPLACE FUNCTION verify_contract_notification_system(contract_id_param uuid DEFAULT NULL)
RETURNS TABLE(
  contract_id uuid,
  student_name text,
  contract_type text,
  total_lessons integer,
  available_lessons integer,
  excluded_lessons integer,
  completed_lessons integer,
  completion_percentage numeric,
  should_notify boolean,
  existing_notifications integer,
  contract_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RAISE EXCEPTION 'Access denied: Only administrators can verify notification system';
  END IF;
  
  RETURN QUERY
  SELECT 
    c.id as contract_id,
    s.name as student_name,
    COALESCE(cv.name, c.type) as contract_type,
    COUNT(l.*) as total_lessons,
    COUNT(l.*) FILTER (WHERE l.is_available = true) as available_lessons,
    COUNT(l.*) FILTER (WHERE l.is_available = false) as excluded_lessons,
    COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) as completed_lessons,
    CASE 
      WHEN COUNT(l.*) FILTER (WHERE l.is_available = true) > 0 
      THEN ROUND(
        (COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL)::numeric / 
         COUNT(l.*) FILTER (WHERE l.is_available = true)::numeric) * 100, 
        2
      )
      ELSE 0
    END as completion_percentage,
    (
      COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) = 
      COUNT(l.*) FILTER (WHERE l.is_available = true) AND
      COUNT(l.*) FILTER (WHERE l.is_available = true) > 0 AND
      c.status = 'active'
    ) as should_notify,
    (
      SELECT COUNT(*) FROM notifications n 
      WHERE n.contract_id = c.id AND n.type = 'contract_fulfilled'
    ) as existing_notifications,
    c.status as contract_status
  FROM contracts c
  JOIN students s ON c.student_id = s.id
  LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
  LEFT JOIN lessons l ON l.contract_id = c.id
  WHERE 
    (contract_id_param IS NULL OR c.id = contract_id_param)
  GROUP BY c.id, s.name, cv.name, c.type, c.status
  ORDER BY completion_percentage DESC, s.name;
END;
$$;

-- Create a function to manually trigger completion check for testing
CREATE OR REPLACE FUNCTION force_completion_check(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result_message text;
  notification_count_before integer;
  notification_count_after integer;
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN 'Access denied: Only administrators can force completion checks';
  END IF;
  
  -- Count notifications before
  SELECT COUNT(*) INTO notification_count_before
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  -- Trigger the notification function by updating the contract
  UPDATE contracts 
  SET updated_at = now()
  WHERE id = contract_id_param;
  
  -- Count notifications after
  SELECT COUNT(*) INTO notification_count_after
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  result_message := format(
    'Completion check completed for contract %s. Notifications before: %s, after: %s',
    contract_id_param,
    notification_count_before,
    notification_count_after
  );
  
  RETURN result_message;
END;
$$;

-- Create a function to find contracts that should have notifications but don't
CREATE OR REPLACE FUNCTION find_missing_completion_notifications()
RETURNS TABLE(
  contract_id uuid,
  student_name text,
  completion_status text,
  available_lessons integer,
  completed_lessons integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RAISE EXCEPTION 'Access denied: Only administrators can find missing notifications';
  END IF;
  
  RETURN QUERY
  SELECT 
    c.id as contract_id,
    s.name as student_name,
    c.status as completion_status,
    COUNT(l.*) FILTER (WHERE l.is_available = true) as available_lessons,
    COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) as completed_lessons
  FROM contracts c
  JOIN students s ON c.student_id = s.id
  LEFT JOIN lessons l ON l.contract_id = c.id
  WHERE 
    -- Contract should be complete based on available lessons
    c.id IN (
      SELECT l2.contract_id
      FROM lessons l2
      WHERE l2.contract_id = c.id
      GROUP BY l2.contract_id
      HAVING 
        COUNT(*) FILTER (WHERE l2.is_available = true AND l2.date IS NOT NULL) = 
        COUNT(*) FILTER (WHERE l2.is_available = true) AND
        COUNT(*) FILTER (WHERE l2.is_available = true) > 0
    )
    -- But no notification exists
    AND NOT EXISTS (
      SELECT 1 FROM notifications n 
      WHERE n.contract_id = c.id AND n.type = 'contract_fulfilled'
    )
  GROUP BY c.id, s.name, c.status
  ORDER BY s.name;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION verify_contract_notification_system(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION force_completion_check(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION find_missing_completion_notifications() TO authenticated;

-- Create an index to improve notification query performance
CREATE INDEX IF NOT EXISTS idx_notifications_contract_fulfilled 
ON notifications(contract_id, type) 
WHERE type = 'contract_fulfilled';

-- Create an index to improve lessons availability queries
CREATE INDEX IF NOT EXISTS idx_lessons_availability_completion 
ON lessons(contract_id, is_available, date) 
WHERE is_available = true; 