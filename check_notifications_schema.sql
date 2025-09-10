-- Check Notifications Table Schema
-- This helps understand the foreign key constraints

-- 1. Check the notifications table structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'notifications'
ORDER BY ordinal_position;

-- 2. Check foreign key constraints on notifications table
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

-- 3. Check what's in the teachers table
SELECT 
  id,
  name,
  profile_id,
  created_at
FROM teachers
LIMIT 5;

-- 4. Check what's in the profiles table
SELECT 
  id,
  email,
  role,
  created_at
FROM profiles
WHERE role = 'teacher'
LIMIT 5;

-- 5. Check if there's a mismatch between teachers and profiles
SELECT 
  t.id as teacher_id,
  t.name as teacher_name,
  t.profile_id,
  p.id as profile_id_from_profiles,
  p.email,
  p.role
FROM teachers t
LEFT JOIN profiles p ON t.profile_id = p.id
WHERE t.profile_id IS NOT NULL
ORDER BY t.name; 