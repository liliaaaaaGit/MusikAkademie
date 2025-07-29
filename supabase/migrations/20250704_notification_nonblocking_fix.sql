-- Robust contract completion notification: non-blocking
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
  old_current_lessons integer := 0;
  old_available_lessons integer := 1;
  new_current_lessons integer := 0;
  new_available_lessons integer := 1;
  should_notify boolean := false;
  existing_notification_count integer;
  was_complete_before boolean := false;
  is_complete_now boolean := false;
BEGIN
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = NEW.id AND type = 'contract_fulfilled';
  IF existing_notification_count > 0 THEN
    RETURN NEW;
  END IF;
  IF OLD.attendance_count IS NOT NULL AND OLD.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
    BEGIN
      old_current_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 1) AS INTEGER);
      old_available_lessons := CAST(SPLIT_PART(OLD.attendance_count, '/', 2) AS INTEGER);
    EXCEPTION WHEN OTHERS THEN
      old_current_lessons := 0;
      old_available_lessons := 1;
    END;
  END IF;
  IF NEW.attendance_count IS NOT NULL AND NEW.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
    BEGIN
      new_current_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 1) AS INTEGER);
      new_available_lessons := CAST(SPLIT_PART(NEW.attendance_count, '/', 2) AS INTEGER);
    EXCEPTION WHEN OTHERS THEN
      new_current_lessons := 0;
      new_available_lessons := 1;
    END;
  END IF;
  was_complete_before := (old_current_lessons = old_available_lessons AND old_available_lessons > 0);
  is_complete_now := (new_current_lessons = new_available_lessons AND new_available_lessons > 0);
  IF is_complete_now AND NOT was_complete_before AND NEW.status = 'active' THEN
    should_notify := true;
    NEW.status := 'completed';
    NEW.updated_at := now();
  END IF;
  IF should_notify THEN
    SELECT s.name, s.id, t.name, t.id
    INTO student_name, student_id_val, teacher_name, teacher_id_val
    FROM students s
    LEFT JOIN teachers t ON s.teacher_id = t.id
    WHERE s.id = NEW.student_id;
    SELECT COALESCE(cv.name, 
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
    notification_message := format(
      'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen. Lehrer: %s. Abgeschlossen am: %s.',
      COALESCE(student_name, 'Unbekannter Schüler'),
      COALESCE(contract_type_display, 'Vertrag'),
      COALESCE(teacher_name, 'Unbekannter Lehrer'),
      to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI')
    );
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
      RAISE NOTICE 'Failed to create admin notification for contract %: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

