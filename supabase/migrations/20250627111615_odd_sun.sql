/*
  # Add INSERT policy for teachers to create students

  1. Security Changes
    - Add INSERT policy for `students` table
    - Allow teachers to create students assigned to themselves
    - Prevent teachers from setting admin-only fields (bank_id, contract_id, contract_type)
    
  2. Policy Details
    - Teachers can only create students where they are the assigned teacher
    - Admin-specific fields must be NULL during creation
    - Maintains existing security constraints
*/

-- Add INSERT policy for teachers to create students
CREATE POLICY "Teachers can create students assigned to themselves"
  ON students
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Allow if user is admin
    (get_user_role() = 'admin'::text) 
    OR 
    -- Allow if teacher is creating student assigned to themselves
    -- and admin-only fields are NULL
    (
      get_user_role() = 'teacher'::text
      AND EXISTS (
        SELECT 1 
        FROM teachers t
        JOIN profiles p ON t.profile_id = p.id
        WHERE p.id = auth.uid() AND t.id = teacher_id
      )
      AND bank_id IS NULL
      AND contract_id IS NULL
      AND contract_type IS NULL
    )
  );