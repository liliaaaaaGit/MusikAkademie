/*
  # Custom Bank ID Format Implementation

  1. Functions
    - Create auto_generate_student_bank_id function for S1, S2, S3... format
    - Create auto_generate_teacher_bank_id function for L1, L2, L3... format

  2. Table Updates
    - Remove default values from bank_id columns
    - Ensure bank_id columns are properly configured

  3. Triggers
    - Create BEFORE INSERT triggers to auto-generate custom bank IDs
    - Ensure triggers only run for new records without existing bank_id

  4. Validation
    - Ensure uniqueness and proper sequential numbering
    - Handle edge cases and fallbacks
*/

-- Drop existing triggers if they exist
DROP TRIGGER IF EXISTS trigger_auto_generate_student_bank_id ON students;
DROP TRIGGER IF EXISTS trigger_auto_generate_teacher_bank_id ON teachers;

-- Drop existing functions if they exist
DROP FUNCTION IF EXISTS auto_generate_student_bank_id();
DROP FUNCTION IF EXISTS auto_generate_teacher_bank_id();

-- Remove default values from bank_id columns
ALTER TABLE students ALTER COLUMN bank_id DROP DEFAULT;
ALTER TABLE teachers ALTER COLUMN bank_id DROP DEFAULT;

-- Function to generate sequential student bank IDs (S1, S2, S3...)
CREATE OR REPLACE FUNCTION auto_generate_student_bank_id()
RETURNS TRIGGER AS $$
DECLARE
  next_number INTEGER;
  new_bank_id TEXT;
BEGIN
  -- Only generate bank_id if it's not already set
  IF NEW.bank_id IS NULL OR NEW.bank_id = '' THEN
    -- Find the highest existing number for student bank IDs starting with 'S'
    SELECT COALESCE(
      MAX(
        CASE 
          WHEN bank_id ~ '^S[0-9]+$' 
          THEN CAST(SUBSTRING(bank_id FROM 2) AS INTEGER)
          ELSE 0
        END
      ), 0
    ) + 1
    INTO next_number
    FROM students
    WHERE bank_id IS NOT NULL AND bank_id != '';
    
    -- Generate the new bank_id
    new_bank_id := 'S' || next_number::TEXT;
    
    -- Ensure uniqueness (in case of race conditions)
    WHILE EXISTS (SELECT 1 FROM students WHERE bank_id = new_bank_id) LOOP
      next_number := next_number + 1;
      new_bank_id := 'S' || next_number::TEXT;
    END LOOP;
    
    -- Set the new bank_id
    NEW.bank_id := new_bank_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to generate sequential teacher bank IDs (L1, L2, L3...)
CREATE OR REPLACE FUNCTION auto_generate_teacher_bank_id()
RETURNS TRIGGER AS $$
DECLARE
  next_number INTEGER;
  new_bank_id TEXT;
BEGIN
  -- Only generate bank_id if it's not already set
  IF NEW.bank_id IS NULL OR NEW.bank_id = '' THEN
    -- Find the highest existing number for teacher bank IDs starting with 'L'
    SELECT COALESCE(
      MAX(
        CASE 
          WHEN bank_id ~ '^L[0-9]+$' 
          THEN CAST(SUBSTRING(bank_id FROM 2) AS INTEGER)
          ELSE 0
        END
      ), 0
    ) + 1
    INTO next_number
    FROM teachers
    WHERE bank_id IS NOT NULL AND bank_id != '';
    
    -- Generate the new bank_id
    new_bank_id := 'L' || next_number::TEXT;
    
    -- Ensure uniqueness (in case of race conditions)
    WHILE EXISTS (SELECT 1 FROM teachers WHERE bank_id = new_bank_id) LOOP
      next_number := next_number + 1;
      new_bank_id := 'L' || next_number::TEXT;
    END LOOP;
    
    -- Set the new bank_id
    NEW.bank_id := new_bank_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to auto-generate bank IDs
CREATE TRIGGER trigger_auto_generate_student_bank_id
  BEFORE INSERT ON students
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_student_bank_id();

CREATE TRIGGER trigger_auto_generate_teacher_bank_id
  BEFORE INSERT ON teachers
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_teacher_bank_id();

-- Update any existing NULL or empty bank_id values for students
DO $$
DECLARE
  student_record RECORD;
  next_number INTEGER;
  new_bank_id TEXT;
BEGIN
  -- Find the highest existing student bank ID number
  SELECT COALESCE(
    MAX(
      CASE 
        WHEN bank_id ~ '^S[0-9]+$' 
        THEN CAST(SUBSTRING(bank_id FROM 2) AS INTEGER)
        ELSE 0
      END
    ), 0
  ) INTO next_number
  FROM students
  WHERE bank_id IS NOT NULL AND bank_id != '';
  
  -- Update students with NULL or empty bank_id
  FOR student_record IN 
    SELECT id FROM students 
    WHERE bank_id IS NULL OR bank_id = '' OR bank_id !~ '^S[0-9]+$'
    ORDER BY created_at
  LOOP
    next_number := next_number + 1;
    new_bank_id := 'S' || next_number::TEXT;
    
    -- Ensure uniqueness
    WHILE EXISTS (SELECT 1 FROM students WHERE bank_id = new_bank_id) LOOP
      next_number := next_number + 1;
      new_bank_id := 'S' || next_number::TEXT;
    END LOOP;
    
    UPDATE students 
    SET bank_id = new_bank_id 
    WHERE id = student_record.id;
  END LOOP;
END $$;

-- Update any existing NULL or empty bank_id values for teachers
DO $$
DECLARE
  teacher_record RECORD;
  next_number INTEGER;
  new_bank_id TEXT;
BEGIN
  -- Find the highest existing teacher bank ID number
  SELECT COALESCE(
    MAX(
      CASE 
        WHEN bank_id ~ '^L[0-9]+$' 
        THEN CAST(SUBSTRING(bank_id FROM 2) AS INTEGER)
        ELSE 0
      END
    ), 0
  ) INTO next_number
  FROM teachers
  WHERE bank_id IS NOT NULL AND bank_id != '';
  
  -- Update teachers with NULL or empty bank_id
  FOR teacher_record IN 
    SELECT id FROM teachers 
    WHERE bank_id IS NULL OR bank_id = '' OR bank_id !~ '^L[0-9]+$'
    ORDER BY created_at
  LOOP
    next_number := next_number + 1;
    new_bank_id := 'L' || next_number::TEXT;
    
    -- Ensure uniqueness
    WHILE EXISTS (SELECT 1 FROM teachers WHERE bank_id = new_bank_id) LOOP
      next_number := next_number + 1;
      new_bank_id := 'L' || next_number::TEXT;
    END LOOP;
    
    UPDATE teachers 
    SET bank_id = new_bank_id 
    WHERE id = teacher_record.id;
  END LOOP;
END $$;

-- Ensure bank_id columns are NOT NULL and have proper constraints
ALTER TABLE students ALTER COLUMN bank_id SET NOT NULL;
ALTER TABLE teachers ALTER COLUMN bank_id SET NOT NULL;

-- Add unique constraints if they don't exist
DO $$
BEGIN
  -- Add unique constraint for students bank_id if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'students_bank_id_key' 
    AND table_name = 'students'
  ) THEN
    ALTER TABLE students ADD CONSTRAINT students_bank_id_key UNIQUE (bank_id);
  END IF;
  
  -- Add unique constraint for teachers bank_id if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'teachers_bank_id_key' 
    AND table_name = 'teachers'
  ) THEN
    ALTER TABLE teachers ADD CONSTRAINT teachers_bank_id_key UNIQUE (bank_id);
  END IF;
END $$;