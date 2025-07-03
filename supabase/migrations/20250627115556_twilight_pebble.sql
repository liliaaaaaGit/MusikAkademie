/*
  # Update teachers table for multiple instruments

  1. Changes
    - Change instrument column from text to text[] for multiple instruments
    - Update existing data to convert single instruments to arrays
    - Add index for better performance

  2. Notes
    - Preserves existing instrument data by converting to array format
    - Maintains backward compatibility
*/

-- First, add a new column for instruments array
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'teachers' AND column_name = 'instruments'
  ) THEN
    ALTER TABLE teachers ADD COLUMN instruments text[];
  END IF;
END $$;

-- Migrate existing instrument data to the new instruments array column
UPDATE teachers 
SET instruments = ARRAY[instrument] 
WHERE instruments IS NULL AND instrument IS NOT NULL AND instrument != '';

-- For teachers with empty or null instruments, set to empty array
UPDATE teachers 
SET instruments = ARRAY[]::text[] 
WHERE instruments IS NULL;

-- Drop the old instrument column and rename instruments to instrument
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'teachers' AND column_name = 'instrument'
  ) THEN
    ALTER TABLE teachers DROP COLUMN instrument;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'teachers' AND column_name = 'instruments'
  ) THEN
    ALTER TABLE teachers RENAME COLUMN instruments TO instrument;
  END IF;
END $$;

-- Add index for better performance on instrument searches
CREATE INDEX IF NOT EXISTS idx_teachers_instrument ON teachers USING GIN (instrument);