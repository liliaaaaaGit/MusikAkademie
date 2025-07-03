/*
  # Sequential Bank IDs and Updated Student Creation Policy

  1. Changes
    - Replace UUID bank_id columns with sequential text IDs (L1, L2, L3... for teachers; S1, S2, S3... for students)
    - Update student creation policy to only allow admins to create students
    - Ensure no duplicate bank IDs are generated

  2. Security
    - Only admins can create new students
    - Teachers can still edit their assigned students
    - Bank IDs are auto-generated and unique
*/

-- Temporarily disable RLS to allow schema modifications
ALTER TABLE students DISABLE ROW LEVEL SECURITY;
ALTER TABLE teachers DISABLE ROW LEVEL SECURITY;

-- Drop existing triggers and functions for bank_id generation
DROP TRIGGER IF EXISTS trigger_auto_generate_student_bank_id ON students;
DROP TRIGGER IF EXISTS trigger_auto_generate_teacher_bank_id ON teachers;
DROP FUNCTION IF EXISTS auto_generate_student_bank_id();
DROP FUNCTION IF EXISTS auto_generate_teacher_bank_id();
DROP FUNCTION IF EXISTS generate_bank_id(text, text);

-- Drop existing bank_id columns (this will also drop the unique constraints)
ALTER TABLE students DROP COLUMN IF EXISTS bank_id;
ALTER TABLE teachers DROP COLUMN IF EXISTS bank_id;

-- Add new text bank_id columns with unique constraints
ALTER TABLE students ADD COLUMN bank_id text UNIQUE DEFAULT gen_random_uuid()::text NOT NULL;
ALTER TABLE teachers ADD COLUMN bank_id text UNIQUE DEFAULT gen_random_uuid()::text NOT NULL;

-- Create function to generate sequential bank IDs
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
  IF NEW.bank_id IS NULL OR NEW.bank_id = '' THEN
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
  IF NEW.bank_id IS NULL OR NEW.bank_id = '' THEN
    NEW.bank_id := generate_bank_id('teachers', 'L');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for auto-generating bank_ids
CREATE TRIGGER trigger_auto_generate_student_bank_id
  BEFORE INSERT ON students
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_student_bank_id();

CREATE TRIGGER trigger_auto_generate_teacher_bank_id
  BEFORE INSERT ON teachers
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_teacher_bank_id();

-- Create indexes for the new bank_id fields
CREATE INDEX IF NOT EXISTS idx_students_bank_id_text ON students(bank_id);
CREATE INDEX IF NOT EXISTS idx_teachers_bank_id_text ON teachers(bank_id);

-- Generate sequential bank_ids for existing records
DO $$
DECLARE
  student_record RECORD;
  teacher_record RECORD;
  student_counter integer := 1;
  teacher_counter integer := 1;
BEGIN
  -- Update existing students with sequential IDs
  FOR student_record IN SELECT id FROM students ORDER BY created_at LOOP
    UPDATE students 
    SET bank_id = 'S' || student_counter::text 
    WHERE id = student_record.id;
    student_counter := student_counter + 1;
  END LOOP;
  
  -- Update existing teachers with sequential IDs
  FOR teacher_record IN SELECT id FROM teachers ORDER BY created_at LOOP
    UPDATE teachers 
    SET bank_id = 'L' || teacher_counter::text 
    WHERE id = teacher_record.id;
    teacher_counter := teacher_counter + 1;
  END LOOP;
END $$;

-- Re-enable RLS
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;

-- Drop existing policies for students table
DROP POLICY IF EXISTS "Admins can manage all students" ON students;
DROP POLICY IF EXISTS "Teachers can read their assigned students" ON students;
DROP POLICY IF EXISTS "Teachers can update their assigned students" ON students;
DROP POLICY IF EXISTS "Teachers can create students assigned to themselves" ON students;

-- Create new RLS policies for students table - Only admins can create students
CREATE POLICY "Admins can manage all students"
  ON students FOR ALL
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read their assigned students"
  ON students FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND t.id = students.teacher_id
    )
  );

CREATE POLICY "Teachers can update their assigned students"
  ON students FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND t.id = students.teacher_id
    )
  );

-- NEW POLICY: Only admins can create students
CREATE POLICY "Admins can create students"
  ON students FOR INSERT
  TO authenticated
  WITH CHECK (get_user_role() = 'admin');

-- Recreate all RLS policies for teachers table
DROP POLICY IF EXISTS "Admins can manage all teachers" ON teachers;
DROP POLICY IF EXISTS "Teachers can read all teachers" ON teachers;
DROP POLICY IF EXISTS "Teachers can update own record" ON teachers;
DROP POLICY IF EXISTS "Teachers see own record or if admin" ON teachers;

CREATE POLICY "Admins can manage all teachers"
  ON teachers FOR ALL
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read all teachers"
  ON teachers FOR SELECT
  TO authenticated
  USING (get_user_role() IN ('admin', 'teacher'));

CREATE POLICY "Teachers can update own record"
  ON teachers FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR 
    profile_id = auth.uid()
  );

CREATE POLICY "Teachers see own record or if admin"
  ON teachers FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR 
    profile_id = auth.uid()
  );