-- Complete Fix for Notifications Query
-- This ensures the foreign key constraint is correct and the query works

BEGIN;

-- =====================================================
-- 1. VERIFY FOREIGN KEY CONSTRAINT
-- =====================================================

-- Check current foreign key constraints
SELECT 
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_name = 'notifications';

-- =====================================================
-- 2. ENSURE CORRECT FOREIGN KEY CONSTRAINT
-- =====================================================

-- Drop any existing foreign key constraint on teacher_id
ALTER TABLE notifications 
DROP CONSTRAINT IF EXISTS notifications_teacher_id_fkey;

-- Add the correct foreign key constraint to profiles
ALTER TABLE notifications 
ADD CONSTRAINT notifications_teacher_id_fkey 
FOREIGN KEY (teacher_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- =====================================================
-- 3. TEST THE QUERY
-- =====================================================

-- Test a simple notifications query
SELECT 
  id,
  type,
  contract_id,
  teacher_id,
  student_id,
  message,
  is_read,
  created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 5;

-- Test joining with profiles
SELECT 
  n.id,
  n.type,
  n.teacher_id,
  p.full_name,
  p.email,
  p.role
FROM notifications n
LEFT JOIN profiles p ON n.teacher_id = p.id
ORDER BY n.created_at DESC
LIMIT 5;

-- =====================================================
-- 4. VERIFY THE FIX
-- =====================================================

-- Check the updated foreign key constraints
SELECT 
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_name = 'notifications';

COMMIT; 