-- Update RLS policies for students table to work with student_teachers table
-- This migration updates the existing RLS policies to support the new many-to-many relationship

-- Drop existing policies for students table
DROP POLICY IF EXISTS "Teachers can read their assigned students" ON students;
DROP POLICY IF EXISTS "Teachers can update their assigned students" ON students;
DROP POLICY IF EXISTS "Teachers can create students assigned to themselves" ON students;

-- Create updated RLS policies for students table that work with student_teachers
CREATE POLICY "Teachers can read their assigned students"
  ON students FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM student_teachers st
      WHERE st.student_id = students.id AND st.teacher_id = auth.uid()
    )
  );

CREATE POLICY "Teachers can update their assigned students"
  ON students FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM student_teachers st
      WHERE st.student_id = students.id AND st.teacher_id = auth.uid()
    )
  );

CREATE POLICY "Teachers can create students assigned to themselves"
  ON students FOR INSERT
  TO authenticated
  WITH CHECK (
    (get_user_role() = 'admin') OR 
    (
      (get_user_role() = 'teacher') AND 
      (teacher_id = auth.uid()) AND 
      (contract_id IS NULL) AND 
      (contract_type IS NULL)
    )
  );

-- Update contracts RLS policies to work with student_teachers
DROP POLICY IF EXISTS "Teachers can read contracts of their students" ON contracts;
DROP POLICY IF EXISTS "Teachers can update contracts of their students" ON contracts;
DROP POLICY IF EXISTS "Teachers can create contracts for their students" ON contracts;

CREATE POLICY "Teachers can read contracts of their students"
  ON contracts FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM student_teachers st
      WHERE st.student_id = contracts.student_id AND st.teacher_id = auth.uid()
    )
  );

CREATE POLICY "Teachers can update contracts of their students"
  ON contracts FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM student_teachers st
      WHERE st.student_id = contracts.student_id AND st.teacher_id = auth.uid()
    )
  );

CREATE POLICY "Teachers can create contracts for their students"
  ON contracts FOR INSERT
  TO authenticated
  WITH CHECK (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM student_teachers st
      WHERE st.student_id = contracts.student_id AND st.teacher_id = auth.uid()
    )
  );

-- Update lessons RLS policies to work with student_teachers
DROP POLICY IF EXISTS "Teachers can read lessons of their students" ON lessons;
DROP POLICY IF EXISTS "Teachers can update lessons of their students" ON lessons;
DROP POLICY IF EXISTS "Teachers can create lessons for their students" ON lessons;

CREATE POLICY "Teachers can read lessons of their students"
  ON lessons FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM contracts c
      JOIN student_teachers st ON st.student_id = c.student_id
      WHERE c.id = lessons.contract_id AND st.teacher_id = auth.uid()
    )
  );

CREATE POLICY "Teachers can update lessons of their students"
  ON lessons FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM contracts c
      JOIN student_teachers st ON st.student_id = c.student_id
      WHERE c.id = lessons.contract_id AND st.teacher_id = auth.uid()
    )
  );

CREATE POLICY "Teachers can create lessons for their students"
  ON lessons FOR INSERT
  TO authenticated
  WITH CHECK (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM contracts c
      JOIN student_teachers st ON st.student_id = c.student_id
      WHERE c.id = lessons.contract_id AND st.teacher_id = auth.uid()
    )
  );
