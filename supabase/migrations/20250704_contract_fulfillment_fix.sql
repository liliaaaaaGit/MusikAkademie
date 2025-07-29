-- Contract fulfillment fix: use available lessons, robust notification
-- 1. Update attendance calculation to use available lessons
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS 12734
DECLARE
  completed_available integer := 0;
  available_lessons integer := 0;
  contract_id uuid;
  lesson_dates jsonb := '[]'::jsonb;
BEGIN
  contract_id := COALESCE(NEW.contract_id, OLD.contract_id);
  -- Count available lessons and completed ones
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
    COUNT(*) FILTER (WHERE is_available = true),
    COALESCE(jsonb_agg(date ORDER BY lesson_number) FILTER (WHERE is_available = true AND date IS NOT NULL), '[]'::jsonb)
  INTO completed_available, available_lessons, lesson_dates
  FROM lessons
  WHERE contract_id = contract_id;
  -- Update contract with completed/available counts
  UPDATE contracts
  SET attendance_count = completed_available || '/' || available_lessons,
      attendance_dates = lesson_dates,
      updated_at = now()
  WHERE id = contract_id;
  RETURN COALESCE(NEW, OLD);
END;
12734 LANGUAGE plpgsql;

-- Recreate trigger
DROP TRIGGER IF EXISTS trigger_update_contract_attendance_on_lesson_change ON lessons;
CREATE TRIGGER trigger_update_contract_attendance_on_lesson_change
  AFTER INSERT OR UPDATE OR DELETE ON lessons
  FOR EACH ROW EXECUTE FUNCTION update_contract_attendance();

-- 2. Robust notification function (non-blocking) already created in previous migration, ensure exists
-- (No action needed if previous migration applied)

-- 3. Add view for centralized progress info
CREATE OR REPLACE VIEW contract_progress AS
SELECT
  c.id AS contract_id,
  COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) AS completed_available,
  COUNT(l.*) FILTER (WHERE l.is_available = true) AS available_lessons,
  COUNT(l.*) FILTER (WHERE l.is_available = false) AS excluded_lessons,
  (COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) = COUNT(l.*) FILTER (WHERE l.is_available = true) AND COUNT(l.*) FILTER (WHERE l.is_available = true) > 0) AS is_fulfilled
FROM contracts c
LEFT JOIN lessons l ON l.contract_id = c.id
GROUP BY c.id;

