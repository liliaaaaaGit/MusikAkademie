-- Fix RLS policies on lessons table that reference deprecated students.teacher_id
-- This fixes the "column s.teacher_id does not exist" error when updating lessons

BEGIN;

-- 1) Drop existing problematic RLS policies on lessons table
DROP POLICY IF EXISTS "Teachers can read lessons of their students" ON lessons;
DROP POLICY IF EXISTS "Teachers can update lessons of their students" ON lessons;
DROP POLICY IF EXISTS "Teachers can insert lessons for their students contracts" ON lessons;

-- 2) Create fixed RLS policies that use contracts.teacher_id instead of students.teacher_id

-- Policy for reading lessons
CREATE POLICY "Teachers can read lessons of their students"
  ON lessons
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) OR 
    EXISTS (
      SELECT 1
      FROM contracts c
      JOIN teachers t ON c.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE c.id = lessons.contract_id AND p.id = auth.uid()
    )
  );

-- Policy for updating lessons
CREATE POLICY "Teachers can update lessons of their students"
  ON lessons
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) OR 
    EXISTS (
      SELECT 1
      FROM contracts c
      JOIN teachers t ON c.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE c.id = lessons.contract_id AND p.id = auth.uid()
    )
  );

-- Policy for inserting lessons
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
    -- Allow teachers to insert lessons for contracts they teach
    (EXISTS (
      SELECT 1
      FROM contracts c
      JOIN teachers t ON c.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE c.id = lessons.contract_id 
      AND p.id = auth.uid()
    ))
  );

COMMIT;
