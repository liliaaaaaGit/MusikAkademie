/*
  # Fix lesson insertion policy for teachers

  1. Security Changes
    - Add INSERT policy for lessons table to allow teachers to create lessons for their students' contracts
    - This policy ensures teachers can only insert lessons for contracts belonging to their assigned students
    - Maintains security by checking the relationship chain: lesson -> contract -> student -> teacher -> profile

  2. Policy Details
    - Allows authenticated users with teacher role to insert lessons
    - Validates that the contract belongs to a student assigned to the current teacher
    - Uses the existing relationship structure in the database
*/

-- Add INSERT policy for teachers to create lessons for their students' contracts
CREATE POLICY "Teachers can insert lessons for their students contracts"
  ON lessons
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Allow admins to insert any lessons
    (EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    ))
    OR
    -- Allow teachers to insert lessons for contracts of their assigned students
    (EXISTS (
      SELECT 1
      FROM contracts c
      JOIN students s ON c.student_id = s.id
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE lessons.contract_id = c.id
      AND p.id = auth.uid()
      AND p.role = 'teacher'
    ))
  );