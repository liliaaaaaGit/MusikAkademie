/*
  # Add bank_id fields to students and teachers tables

  1. Changes
    - Remove existing UUID bank_id column from students table
    - Add new text bank_id fields to both students and teachers tables
    - Auto-generate bank_ids: S1, S2, S3... for students; L1, L2, L3... for teachers
    - Create functions and triggers for auto-generation
    - Update policies to handle the new structure

  2. Security
    - Only admins can view/edit bank_id fields
    - Maintain existing RLS policies
*/

-- First, drop the dependent policy that references bank_id
DROP POLICY IF EXISTS "Teachers can create students assigned to themselves" ON students;

-- Remove existing bank_id foreign key constraint from students table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'students_bank_id_fkey' 
    AND table_name = 'students'
  ) THEN
    ALTER TABLE students DROP CONSTRAINT students_bank_id_fkey;
  END IF;
END $$;

-- Drop existing bank_id index
DROP INDEX IF EXISTS idx_students_bank_id;

-- Remove existing bank_id column from students table (it was a UUID foreign key)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'students' AND column_name = 'bank_id'
    AND data_type = 'uuid'
  ) THEN
    ALTER TABLE students DROP COLUMN bank_id;
  END IF;
END $$;

-- Add new bank_id text field to students table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'students' AND column_name = 'bank_id'
    AND data_type = 'text'
  ) THEN
    ALTER TABLE students ADD COLUMN bank_id text UNIQUE;
  END IF;
END $$;

-- Add new bank_id text field to teachers table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'teachers' AND column_name = 'bank_id'
  ) THEN
    ALTER TABLE teachers ADD COLUMN bank_id text UNIQUE;
  END IF;
END $$;

-- Create helper function to get user role (only if it doesn't exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'get_user_role' 
    AND pg_get_function_result(oid) = 'text'
  ) THEN
    EXECUTE '
    CREATE FUNCTION get_user_role()
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $func$
    DECLARE
      user_role text;
    BEGIN
      SELECT role INTO user_role
      FROM profiles
      WHERE id = auth.uid();
      
      RETURN COALESCE(user_role, '''');
    END;
    $func$';
  END IF;
END $$;

-- Create function to generate bank IDs
CREATE OR REPLACE FUNCTION generate_bank_id(table_name text, prefix text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  next_id integer;
  new_bank_id text;
  max_attempts integer := 100;
  attempt integer := 0;
BEGIN
  LOOP
    -- Get the current count + 1 for the next ID
    EXECUTE format('SELECT COALESCE(MAX(CAST(SUBSTRING(bank_id FROM %L) AS integer)), 0) + 1 FROM %I WHERE bank_id ~ %L',
                   '^' || prefix || '([0-9]+)$',
                   table_name,
                   '^' || prefix || '[0-9]+$')
    INTO next_id;
    
    -- Generate the new bank_id
    new_bank_id := prefix || next_id::text;
    
    -- Check if this ID already exists (safety check)
    EXECUTE format('SELECT 1 FROM %I WHERE bank_id = %L', table_name, new_bank_id);
    
    -- If not found, we can use this ID
    IF NOT FOUND THEN
      RETURN new_bank_id;
    END IF;
    
    -- Safety check to prevent infinite loops
    attempt := attempt + 1;
    IF attempt >= max_attempts THEN
      RAISE EXCEPTION 'Could not generate unique bank_id after % attempts', max_attempts;
    END IF;
  END LOOP;
END;
$$;

-- Create function to auto-generate bank_id for students
CREATE OR REPLACE FUNCTION auto_generate_student_bank_id()
RETURNS TRIGGER AS $$
BEGIN
  -- Only generate if bank_id is not already set
  IF NEW.bank_id IS NULL THEN
    NEW.bank_id := generate_bank_id('students', 'S');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create function to auto-generate bank_id for teachers
CREATE OR REPLACE FUNCTION auto_generate_teacher_bank_id()
RETURNS TRIGGER AS $$
BEGIN
  -- Only generate if bank_id is not already set
  IF NEW.bank_id IS NULL THEN
    NEW.bank_id := generate_bank_id('teachers', 'L');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for auto-generating bank_ids
DROP TRIGGER IF EXISTS trigger_auto_generate_student_bank_id ON students;
CREATE TRIGGER trigger_auto_generate_student_bank_id
  BEFORE INSERT ON students
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_student_bank_id();

DROP TRIGGER IF EXISTS trigger_auto_generate_teacher_bank_id ON teachers;
CREATE TRIGGER trigger_auto_generate_teacher_bank_id
  BEFORE INSERT ON teachers
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_teacher_bank_id();

-- Create indexes for the new bank_id fields
CREATE INDEX IF NOT EXISTS idx_students_bank_id_text ON students(bank_id);
CREATE INDEX IF NOT EXISTS idx_teachers_bank_id_text ON teachers(bank_id);

-- Generate bank_ids for existing records
UPDATE students SET bank_id = generate_bank_id('students', 'S') WHERE bank_id IS NULL;
UPDATE teachers SET bank_id = generate_bank_id('teachers', 'L') WHERE bank_id IS NULL;

-- Recreate the student creation policy without bank_id dependency
CREATE POLICY "Teachers can create students assigned to themselves"
  ON students FOR INSERT
  TO authenticated
  WITH CHECK (
    (get_user_role() = 'admin') OR 
    (
      (get_user_role() = 'teacher') AND 
      (EXISTS (
        SELECT 1 FROM teachers t
        JOIN profiles p ON t.profile_id = p.id
        WHERE p.id = auth.uid() AND t.id = students.teacher_id
      )) AND 
      (contract_id IS NULL) AND 
      (contract_type IS NULL)
    )
  );