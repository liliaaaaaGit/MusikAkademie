-- =====================================================
-- PROPER TEACHER NOTIFICATION FIX (KEEPING RLS ENABLED)
-- =====================================================

BEGIN;

-- =====================================================
-- 1. CHECK CURRENT STATE
-- =====================================================

-- Check if RLS is enabled
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'notifications';

-- Check current policies
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY policyname;

-- =====================================================
-- 2. DROP EXISTING TEACHER POLICY
-- =====================================================

DROP POLICY IF EXISTS "notifications_select_teacher" ON notifications;

-- =====================================================
-- 3. CREATE PROPER TEACHER POLICY
-- =====================================================

-- Enable RLS (in case it was disabled)
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Create proper teacher policy: teachers can see notifications where teacher_id = their profile_id
CREATE POLICY "notifications_select_teacher" ON notifications
  FOR SELECT TO authenticated
  USING (
    teacher_id = auth.uid()
  );

-- =====================================================
-- 4. VERIFY THE FIX
-- =====================================================

-- Check the new policy
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies 
WHERE tablename = 'notifications' AND policyname = 'notifications_select_teacher';

-- Verify RLS is enabled
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'notifications';

COMMIT; 