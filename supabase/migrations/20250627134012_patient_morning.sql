/*
  # Fix Contract Attendance Update System

  1. Database Changes
    - Update trigger function to properly handle JSONB attendance_dates
    - Fix type casting for attendance_dates column
    - Improve attendance count calculation

  2. Data Migration
    - Update all existing contracts with correct attendance counts
    - Ensure attendance_dates are properly formatted as JSONB
*/

-- Drop existing trigger to recreate it
DROP TRIGGER IF EXISTS trigger_update_contract_attendance_on_lesson_change ON lessons;

-- Improved function to update contract attendance
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_count integer;
  total_count integer;
  contract_type text;
  contract_id_to_update uuid;
  lesson_dates jsonb;
BEGIN
  -- Get the contract ID to update
  contract_id_to_update := COALESCE(NEW.contract_id, OLD.contract_id);

  -- Get contract type and total lessons
  SELECT c.type INTO contract_type
  FROM contracts c
  WHERE c.id = contract_id_to_update;

  IF contract_type = 'ten_class_card' THEN
    total_count := 10;
  ELSIF contract_type = 'half_year' THEN
    total_count := 18;
  ELSE
    total_count := 10;
  END IF;

  -- Count completed lessons (those with dates) and collect dates as JSONB
  SELECT 
    COUNT(*),
    COALESCE(
      jsonb_agg(date::text ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL),
      '[]'::jsonb
    )
  INTO completed_count, lesson_dates
  FROM lessons
  WHERE contract_id = contract_id_to_update
    AND date IS NOT NULL;

  -- Handle null case
  IF lesson_dates IS NULL THEN
    lesson_dates := '[]'::jsonb;
  END IF;

  -- Update contract attendance count and dates
  UPDATE contracts
  SET 
    attendance_count = completed_count || '/' || total_count,
    attendance_dates = lesson_dates,
    updated_at = now()
  WHERE id = contract_id_to_update;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger
CREATE TRIGGER trigger_update_contract_attendance_on_lesson_change
  AFTER INSERT OR UPDATE OR DELETE ON lessons
  FOR EACH ROW
  EXECUTE FUNCTION update_contract_attendance();

-- Update all existing contracts to fix their attendance counts
DO $$
DECLARE
  contract_record RECORD;
  completed_count integer;
  total_count integer;
  lesson_dates jsonb;
BEGIN
  FOR contract_record IN SELECT id, type FROM contracts LOOP
    -- Determine total count
    IF contract_record.type = 'ten_class_card' THEN
      total_count := 10;
    ELSIF contract_record.type = 'half_year' THEN
      total_count := 18;
    ELSE
      total_count := 10;
    END IF;

    -- Count completed lessons and collect dates as JSONB
    SELECT 
      COUNT(*),
      COALESCE(
        jsonb_agg(date::text ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL),
        '[]'::jsonb
      )
    INTO completed_count, lesson_dates
    FROM lessons
    WHERE contract_id = contract_record.id
      AND date IS NOT NULL;

    -- Handle null case
    IF lesson_dates IS NULL THEN
      lesson_dates := '[]'::jsonb;
    END IF;

    -- Update the contract
    UPDATE contracts
    SET 
      attendance_count = completed_count || '/' || total_count,
      attendance_dates = lesson_dates,
      updated_at = now()
    WHERE id = contract_record.id;
  END LOOP;
END $$;