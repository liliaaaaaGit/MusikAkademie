/*
  # Add Role-Based Access Control with get_user_role Function

  1. New Function
    - `get_user_role()` - Returns the role of the currently authenticated user

  2. Updated RLS Policies
    - Replace existing policies with cleaner role-based checks
    - Use the new get_user_role() function for consistent role checking
    - Ensure teachers can only see their own records and assigned students
    - Ensure admins have full access to all data

  3. Policy Updates
    - Teachers table: Add policy for teachers to see own record or if admin
    - Students table: Maintain existing logic but use get_user_role()
    - Trial lessons table: Use get_user_role() for cleaner policies
    - Contracts table: Use get_user_role() for cleaner policies
*/

-- Create the get_user_role function
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

-- Drop existing policies and recreate with role-based access

-- Teachers table policies
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

-- Students table policies
DROP POLICY IF EXISTS "Admins can manage all students" ON students;
DROP POLICY IF EXISTS "Teachers can read their assigned students" ON students;
DROP POLICY IF EXISTS "Teachers can update their assigned students" ON students;

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

-- Contracts table policies
DROP POLICY IF EXISTS "Admins can manage all contracts" ON contracts;
DROP POLICY IF EXISTS "Teachers can read contracts of their students" ON contracts;
DROP POLICY IF EXISTS "Teachers can update contracts of their students" ON contracts;

CREATE POLICY "Admins can manage all contracts"
  ON contracts FOR ALL
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read contracts of their students"
  ON contracts FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM students s
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND s.id = contracts.student_id
    )
  );

CREATE POLICY "Teachers can update contracts of their students"
  ON contracts FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM students s
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND s.id = contracts.student_id
    )
  );

-- Trial lessons table policies
DROP POLICY IF EXISTS "Admins can manage all trial lessons" ON trial_lessons;
DROP POLICY IF EXISTS "Teachers can read all trial lessons" ON trial_lessons;
DROP POLICY IF EXISTS "Teachers can update assigned trial lessons" ON trial_lessons;

CREATE POLICY "Admins can manage all trial lessons"
  ON trial_lessons FOR ALL
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read all trial lessons"
  ON trial_lessons FOR SELECT
  TO authenticated
  USING (get_user_role() IN ('admin', 'teacher'));

CREATE POLICY "Teachers can update assigned trial lessons"
  ON trial_lessons FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND t.id = trial_lessons.assigned_teacher_id
    )
  );

-- Bank IDs table policy (already uses role-based access, but update for consistency)
DROP POLICY IF EXISTS "Only admins can access bank IDs" ON bank_ids;

CREATE POLICY "Only admins can access bank IDs"
  ON bank_ids FOR ALL
  TO authenticated
  USING (get_user_role() = 'admin');