/*
  # Fix attendance count calculation to use total lessons from contract variant

  1. Changes
    - Update `update_contract_attendance()` function to use `total_count` instead of `available_count`
    - This ensures the denominator always reflects the total lessons for the contract variant
    - Prevents the progress bar from changing when lessons are marked as unavailable

  2. Function Updates
    - Use contract variant's `total_lessons` as the denominator
    - Keep using `available_count` for internal calculations but display `total_count`
    - Maintain backward compatibility with existing contracts
*/

-- Update the attendance calculation function to use total lessons as denominator
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_count integer;
  available_count integer;
  total_count integer;
  contract_id_to_update uuid;
  lesson_dates jsonb;
BEGIN
  -- Get the contract ID to update
  contract_id_to_update := COALESCE(NEW.contract_id, OLD.contract_id);

  -- Get total lessons from contract variant (this is the key fix)
  SELECT cv.total_lessons INTO total_count
  FROM contracts c
  JOIN contract_variants cv ON c.contract_variant_id = cv.id
  WHERE c.id = contract_id_to_update;

  -- Default fallback for contracts without variants
  IF total_count IS NULL THEN
    -- Try to get from legacy type system
    SELECT 
      CASE 
        WHEN c.type = 'ten_class_card' THEN 10
        WHEN c.type = 'half_year' THEN 18
        ELSE 10
      END
    INTO total_count
    FROM contracts c
    WHERE c.id = contract_id_to_update;
    
    -- Final fallback
    IF total_count IS NULL THEN
      total_count := 10;
    END IF;
  END IF;

  -- Count available lessons (for internal tracking)
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
  -- KEY FIX: Use total_count instead of available_count for the denominator
  UPDATE contracts
  SET 
    attendance_count = completed_count || '/' || total_count,
    attendance_dates = lesson_dates,
    updated_at = now()
  WHERE id = contract_id_to_update;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Update all existing contracts to recalculate attendance with the fixed function
DO $$
DECLARE
  contract_record RECORD;
  completed_count integer;
  total_count integer;
  lesson_dates jsonb;
BEGIN
  FOR contract_record IN SELECT id, contract_variant_id, type FROM contracts LOOP
    -- Get total lessons from contract variant
    SELECT cv.total_lessons INTO total_count
    FROM contract_variants cv
    WHERE cv.id = contract_record.contract_variant_id;

    -- Fallback to legacy type system if no variant
    IF total_count IS NULL THEN
      total_count := CASE 
        WHEN contract_record.type = 'ten_class_card' THEN 10
        WHEN contract_record.type = 'half_year' THEN 18
        ELSE 10
      END;
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
      AND date IS NOT NULL
      AND is_available = true;

    -- Handle null case
    IF lesson_dates IS NULL THEN
      lesson_dates := '[]'::jsonb;
    END IF;

    -- Update the contract with fixed calculation
    UPDATE contracts
    SET 
      attendance_count = completed_count || '/' || total_count,
      attendance_dates = lesson_dates,
      updated_at = now()
    WHERE id = contract_record.id;
  END LOOP;
END $$;