-- =====================================================
-- CHECK AND FIX NOTIFICATION RLS POLICIES
-- =====================================================

BEGIN;

-- =====================================================
-- 1. CHECK CURRENT RLS POLICIES
-- =====================================================

-- Check current policies on notifications table
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY policyname;

-- =====================================================
-- 2. DROP EXISTING POLICIES (if any conflicts)
-- =====================================================

-- Drop all existing policies to start fresh
DROP POLICY IF EXISTS "notifications_select_admin" ON notifications;
DROP POLICY IF EXISTS "notifications_select_teacher" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_admin" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_teacher" ON notifications;
DROP POLICY IF EXISTS "notifications_update_admin" ON notifications;
DROP POLICY IF EXISTS "notifications_update_teacher" ON notifications;
DROP POLICY IF EXISTS "notifications_delete_admin" ON notifications;
DROP POLICY IF EXISTS "notifications_delete_teacher" ON notifications;

-- =====================================================
-- 3. CREATE CORRECT RLS POLICIES
-- =====================================================

-- Enable RLS on notifications table
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- SELECT policies
-- Admins can see all notifications
CREATE POLICY "notifications_select_admin" ON notifications
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Teachers can see their own notifications
CREATE POLICY "notifications_select_teacher" ON notifications
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'teacher'
      AND profiles.id = notifications.teacher_id
    )
  );

-- INSERT policies
-- Admins can insert notifications
CREATE POLICY "notifications_insert_admin" ON notifications
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Teachers cannot insert notifications (only system/triggers can)
-- No policy needed - default deny

-- UPDATE policies
-- Admins can update any notification
CREATE POLICY "notifications_update_admin" ON notifications
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Teachers can update their own notifications (mark as read, etc.)
CREATE POLICY "notifications_update_teacher" ON notifications
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'teacher'
      AND profiles.id = notifications.teacher_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'teacher'
      AND profiles.id = notifications.teacher_id
    )
  );

-- DELETE policies
-- Admins can delete any notification
CREATE POLICY "notifications_delete_admin" ON notifications
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Teachers can delete their own notifications
CREATE POLICY "notifications_delete_teacher" ON notifications
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'teacher'
      AND profiles.id = notifications.teacher_id
    )
  );

-- =====================================================
-- 4. VERIFY POLICIES
-- =====================================================

-- Check the new policies
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY policyname;

-- =====================================================
-- 5. TEST NOTIFICATION ACCESS
-- =====================================================

-- Check if notifications have proper teacher_id values
SELECT 
  n.id,
  n.type,
  n.contract_id,
  n.teacher_id,
  n.student_id,
  n.message,
  n.is_read,
  n.created_at,
  p.full_name as teacher_name,
  p.role as teacher_role
FROM notifications n
LEFT JOIN profiles p ON n.teacher_id = p.id
WHERE n.type = 'contract_fulfilled'
ORDER BY n.created_at DESC
LIMIT 10;

COMMIT; 