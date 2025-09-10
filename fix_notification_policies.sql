-- Fix Notification RLS Policies
-- This removes all conflicting policies and creates the correct ones

BEGIN;

-- =====================================================
-- 1. DROP ALL EXISTING NOTIFICATION POLICIES
-- =====================================================

-- Drop all existing policies to start fresh
DROP POLICY IF EXISTS "Admins can read admin notifications" ON notifications;
DROP POLICY IF EXISTS "Only admins can delete notifications" ON notifications;
DROP POLICY IF EXISTS "Only admins can update notifications" ON notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Teachers can read their own notifications" ON notifications;
DROP POLICY IF EXISTS notifications_select_policy ON notifications;
DROP POLICY IF EXISTS notifications_insert_policy ON notifications;
DROP POLICY IF EXISTS notifications_update_policy ON notifications;

-- =====================================================
-- 2. CREATE CORRECT RLS POLICIES
-- =====================================================

-- Policy 1: Users can read their own notifications
-- Admins see all notifications, teachers see notifications where teacher_id = auth.uid()
CREATE POLICY "notifications_select_policy"
  ON notifications
  FOR SELECT
  TO authenticated
  USING (
    -- Admins can see all notifications
    public.get_user_role() = 'admin'
    OR
    -- Teachers can see notifications where they are the teacher_id
    (public.get_user_role() = 'teacher' AND teacher_id = auth.uid())
  );

-- Policy 2: Allow system to create notifications
CREATE POLICY "notifications_insert_policy"
  ON notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Allow the notification function to create notifications
    public.get_user_role() IN ('admin', 'teacher')
  );

-- Policy 3: Users can update their own notifications (mark as read)
CREATE POLICY "notifications_update_policy"
  ON notifications
  FOR UPDATE
  TO authenticated
  USING (
    -- Admins can update any notification
    public.get_user_role() = 'admin'
    OR
    -- Teachers can update notifications where they are the teacher_id
    (public.get_user_role() = 'teacher' AND teacher_id = auth.uid())
  )
  WITH CHECK (
    -- Only allow updating is_read and updated_at
    public.get_user_role() = 'admin'
    OR
    (public.get_user_role() = 'teacher' AND teacher_id = auth.uid())
  );

-- Policy 4: Only admins can delete notifications
CREATE POLICY "notifications_delete_policy"
  ON notifications
  FOR DELETE
  TO authenticated
  USING (
    public.get_user_role() = 'admin'
  );

-- =====================================================
-- 3. VERIFY THE POLICIES ARE CORRECT
-- =====================================================

-- Check that we have the right policies
SELECT 
  policyname,
  cmd,
  permissive,
  roles,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY policyname;

-- =====================================================
-- 4. TEST TEACHER NOTIFICATION CREATION
-- =====================================================

-- Create a test notification to verify the policies work
-- This will help us debug if the issue is with policy or function
DO $$
DECLARE
  test_teacher_profile_id uuid;
  test_student_id uuid;
  test_contract_id uuid;
BEGIN
  -- Get a test teacher profile ID
  SELECT p.id INTO test_teacher_profile_id
  FROM profiles p
  WHERE p.role = 'teacher'
  LIMIT 1;
  
  -- Get a test student ID
  SELECT s.id INTO test_student_id
  FROM students s
  LIMIT 1;
  
  -- Get a test contract ID
  SELECT c.id INTO test_contract_id
  FROM contracts c
  LIMIT 1;
  
  -- Create a test notification
  IF test_teacher_profile_id IS NOT NULL AND test_student_id IS NOT NULL AND test_contract_id IS NOT NULL THEN
    INSERT INTO notifications (
      type,
      contract_id,
      teacher_id,
      student_id,
      message,
      is_read,
      created_at,
      updated_at
    ) VALUES (
      'test_notification',
      test_contract_id,
      test_teacher_profile_id,
      test_student_id,
      'Test notification to verify policies work',
      false,
      now(),
      now()
    );
    
    RAISE NOTICE 'Test notification created successfully for teacher profile ID: %', test_teacher_profile_id;
  ELSE
    RAISE NOTICE 'Could not create test notification - missing test data';
  END IF;
END $$;

COMMIT; 