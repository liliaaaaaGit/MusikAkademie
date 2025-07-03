/*
  # Add INSERT policy for contracts table

  1. Security
    - Add INSERT policy for contracts table to allow admins and teachers to create contracts
    - Admins can create contracts for any student
    - Teachers can only create contracts for students assigned to them
*/

-- Add INSERT policy for contracts table
CREATE POLICY "Admins and teachers can create contracts"
  ON contracts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Admins can create contracts for any student
    (get_user_role() = 'admin'::text) 
    OR 
    -- Teachers can only create contracts for students assigned to them
    (
      (get_user_role() = 'teacher'::text) 
      AND 
      (EXISTS (
        SELECT 1
        FROM students s
        JOIN teachers t ON (s.teacher_id = t.id)
        JOIN profiles p ON (t.profile_id = p.id)
        WHERE (p.id = auth.uid()) AND (s.id = contracts.student_id)
      ))
    )
  );