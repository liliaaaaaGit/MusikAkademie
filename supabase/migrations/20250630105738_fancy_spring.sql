/*
  # Fix Teacher Contract Deletion Permissions

  1. Security Changes
    - Add DELETE policy for contracts table to allow teachers to delete contracts for their students
    - Ensure teachers can only delete contracts for students assigned to them
    - Maintain admin access to delete any contracts

  2. Policy Details
    - Teachers can delete contracts only for students they are assigned to
    - Uses the existing relationship chain: contract -> student -> teacher -> profile
    - Admins retain full delete access
*/

-- Drop existing DELETE policy if it exists
DROP POLICY IF EXISTS "Teachers can delete contracts of their students" ON contracts;

-- Add DELETE policy for contracts table
CREATE POLICY "Teachers can delete contracts of their students"
  ON contracts
  FOR DELETE
  TO authenticated
  USING (
    -- Allow admins to delete any contracts
    (get_user_role() = 'admin') 
    OR 
    -- Allow teachers to delete contracts for students assigned to them
    (
      (get_user_role() = 'teacher') 
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