-- Fix syntax error in update_contract_attendance function
BEGIN;

-- Fix the malformed function
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

COMMIT;
