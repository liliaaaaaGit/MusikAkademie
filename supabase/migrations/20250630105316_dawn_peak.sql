/*
  # Allow teachers to assign contracts when creating students

  1. Security Changes
    - Update RLS policy for students table to allow teachers to set contract_type during creation
    - Remove the restriction that prevented teachers from setting contract_type
    - Maintain security by ensuring teachers can only create students assigned to themselves

  2. Policy Updates
    - Modify "Teachers can create students assigned to themselves" policy
    - Allow contract_type to be set by teachers during student creation
    - Keep other security constraints intact
*/

-- Drop the existing policy
DROP POLICY IF EXISTS "Teachers can create students assigned to themselves" ON students;

-- Recreate the policy with updated permissions for contract_type
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
      (contract_id IS NULL)
      -- Removed the contract_type IS NULL restriction to allow teachers to set it
    )
  );