-- Fix Notifications Query Issue
-- This checks the foreign key constraint and provides the correct query

-- 1. Check the exact foreign key constraint name
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
  AND tc.table_name = 'notifications'
  AND kcu.column_name = 'teacher_id';

-- 2. Test a simple notifications query
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

-- 3. Test joining with profiles table
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