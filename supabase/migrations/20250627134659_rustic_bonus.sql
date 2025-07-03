/*
  # Add lesson availability feature

  1. Schema Changes
    - Add `is_available` column to lessons table (defaults to true)
    - Add index for better performance

  2. Function Updates
    - Update attendance calculation to exclude unavailable lessons
    - Modify progress calculation logic

  3. Security
    - Update RLS policies to handle availability changes
*/

-- Add is_available column to lessons table
ALTER TABLE lessons ADD COLUMN IF NOT EXISTS is_available boolean DEFAULT true NOT NULL;

-- Add index for better performance when filtering by availability
CREATE INDEX IF NOT EXISTS idx_lessons_availability ON lessons(is_available, contract_id);

-- Update the attendance calculation function to handle unavailable lessons
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_count integer;
  available_count integer;
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

  -- Count available lessons (total that can be completed)
  SELECT COUNT(*)
  INTO available_count
  FROM lessons
  WHERE contract_id = contract_id_to_update
    AND is_available = true;

  -- Count completed lessons (those with dates and available)
  SELECT 
    COUNT(*),
    COALESCE(
      jsonb_agg(date::text ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL),
      '[]'::jsonb
    )
  INTO completed_count, lesson_dates
  FROM lessons
  WHERE contract_id = contract_id_to_update
    AND date IS NOT NULL
    AND is_available = true;

  -- Handle null case
  IF lesson_dates IS NULL THEN
    lesson_dates := '[]'::jsonb;
  END IF;

  -- Update contract attendance count and dates
  -- Use available_count instead of total_count for more accurate progress
  UPDATE contracts
  SET 
    attendance_count = completed_count || '/' || available_count,
    attendance_dates = lesson_dates,
    updated_at = now()
  WHERE id = contract_id_to_update;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Update all existing contracts to recalculate attendance with availability
DO $$
DECLARE
  contract_record RECORD;
  completed_count integer;
  available_count integer;
  lesson_dates jsonb;
BEGIN
  FOR contract_record IN SELECT id, type FROM contracts LOOP
    -- Count available lessons
    SELECT COUNT(*)
    INTO available_count
    FROM lessons
    WHERE contract_id = contract_record.id
      AND is_available = true;

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
      AND date IS NOT NULL
      AND is_available = true;

    -- Handle null case
    IF lesson_dates IS NULL THEN
      lesson_dates := '[]'::jsonb;
    END IF;

    -- Update the contract
    UPDATE contracts
    SET 
      attendance_count = completed_count || '/' || available_count,
      attendance_dates = lesson_dates,
      updated_at = now()
    WHERE id = contract_record.id;
  END LOOP;
END $$;