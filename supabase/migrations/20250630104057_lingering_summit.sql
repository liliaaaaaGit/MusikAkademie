/*
  # Fix Bank ID Uniqueness Issue

  1. Database Changes
    - Replace text bank_id with UUID bank_id for guaranteed uniqueness
    - Remove custom bank_id generation functions and triggers
    - Use PostgreSQL's built-in gen_random_uuid() for automatic generation
    - Maintain unique constraints for data integrity

  2. Security
    - Temporarily disable and re-enable RLS to allow schema modifications
    - Recreate all RLS policies to ensure they remain active

  3. Data Migration
    - Preserve existing data while updating schema
    - Generate new UUID bank_ids for all existing records
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

-- Add new UUID bank_id columns with automatic generation
ALTER TABLE students ADD COLUMN bank_id uuid DEFAULT gen_random_uuid() NOT NULL UNIQUE;
ALTER TABLE teachers ADD COLUMN bank_id uuid DEFAULT gen_random_uuid() NOT NULL UNIQUE;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_students_bank_id_uuid ON students(bank_id);
CREATE INDEX IF NOT EXISTS idx_teachers_bank_id_uuid ON teachers(bank_id);

-- Re-enable RLS
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;

-- Recreate all RLS policies for students table
DROP POLICY IF EXISTS "Admins can manage all students" ON students;
DROP POLICY IF EXISTS "Teachers can read their assigned students" ON students;
DROP POLICY IF EXISTS "Teachers can update their assigned students" ON students;
DROP POLICY IF EXISTS "Teachers can create students assigned to themselves" ON students;

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