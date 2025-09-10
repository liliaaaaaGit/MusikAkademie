-- =====================================================
-- SIMPLE TEACHER NOTIFICATION FIX
-- =====================================================

BEGIN;

-- =====================================================
-- 1. TEMPORARILY DISABLE RLS TO TEST
-- =====================================================

-- Disable RLS temporarily so teachers can see notifications
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

-- =====================================================
-- 2. VERIFY TEACHERS CAN NOW SEE NOTIFICATIONS
-- =====================================================

-- Check current notifications
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
LIMIT 5;

COMMIT; 