-- =====================================================
-- DEBUG TEACHER NOTIFICATIONS
-- =====================================================

BEGIN;

-- =====================================================
-- 1. CHECK CURRENT NOTIFICATIONS
-- =====================================================

-- See what notifications exist and their teacher_id values
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

-- =====================================================
-- 2. CHECK TEACHER-PROFILE MAPPING
-- =====================================================

-- Check if teachers have profile_id set correctly
SELECT 
  t.id as teacher_id,
  t.name as teacher_name,
  t.profile_id,
  p.id as profile_id,
  p.full_name as profile_name,
  p.role as profile_role
FROM teachers t
LEFT JOIN profiles p ON t.profile_id = p.id
WHERE t.name LIKE '%Daniela%' OR t.name LIKE '%Papadopoulos%';

-- =====================================================
-- 3. CHECK RLS POLICIES
-- =====================================================

-- Check current RLS policies on notifications
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
-- 4. SIMPLE FIX - DROP AND RECREATE TEACHER POLICY
-- =====================================================

-- Drop the teacher select policy
DROP POLICY IF EXISTS "notifications_select_teacher" ON notifications;

-- Create a simpler, more permissive teacher policy
CREATE POLICY "notifications_select_teacher" ON notifications
  FOR SELECT TO authenticated
  USING (
    teacher_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'teacher'
      AND profiles.id = notifications.teacher_id
    )
  );

-- =====================================================
-- 5. ALTERNATIVE FIX - DISABLE RLS TEMPORARILY FOR TESTING
-- =====================================================

-- If the above doesn't work, let's temporarily disable RLS to test
-- ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

-- =====================================================
-- 6. VERIFY THE FIX
-- =====================================================

-- Check the new policy
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'notifications' AND policyname = 'notifications_select_teacher';

COMMIT; 