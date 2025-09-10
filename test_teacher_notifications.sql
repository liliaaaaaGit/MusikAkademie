-- Test Teacher Notifications
-- Run this in your Supabase SQL Editor to test the fix

-- 1. Check if teachers have profile_id properly set
SELECT 
  t.id as teacher_id,
  t.name as teacher_name,
  t.profile_id,
  p.id as profile_id_from_profiles,
  p.role
FROM teachers t
LEFT JOIN profiles p ON t.profile_id = p.id
WHERE t.profile_id IS NOT NULL
ORDER BY t.name;

-- 2. Check current notifications to see the pattern
SELECT 
  n.id,
  n.type,
  n.contract_id,
  n.teacher_id,
  n.student_id,
  n.message,
  n.is_read,
  n.created_at,
  t.name as teacher_name,
  s.name as student_name
FROM notifications n
LEFT JOIN teachers t ON n.teacher_id = t.profile_id
LEFT JOIN students s ON n.student_id = s.id
WHERE n.type = 'contract_fulfilled'
ORDER BY n.created_at DESC
LIMIT 10;

-- 3. Check if there are any notifications with teacher_id that doesn't match profile_id
SELECT 
  n.id,
  n.teacher_id as notification_teacher_id,
  t.profile_id as teacher_profile_id,
  t.name as teacher_name
FROM notifications n
LEFT JOIN teachers t ON n.teacher_id = t.id
WHERE n.type = 'contract_fulfilled' 
  AND n.teacher_id != t.profile_id
  AND t.profile_id IS NOT NULL;

-- 4. Test the notification function manually (replace with actual contract ID)
-- This will help debug if the function is working correctly
/*
SELECT 
  c.id as contract_id,
  c.status,
  s.name as student_name,
  t.name as teacher_name,
  t.profile_id as teacher_profile_id,
  COUNT(l.*) as total_lessons,
  COUNT(l.*) FILTER (WHERE l.date IS NOT NULL) as completed_lessons,
  COUNT(l.*) FILTER (WHERE l.is_available = false) as excluded_lessons
FROM contracts c
LEFT JOIN students s ON c.student_id = s.id
LEFT JOIN teachers t ON s.teacher_id = t.id
LEFT JOIN lessons l ON c.id = l.contract_id
WHERE c.id = 'YOUR_CONTRACT_ID_HERE'
GROUP BY c.id, c.status, s.name, t.name, t.profile_id;
*/

-- 5. Check RLS policies for notifications
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'notifications'; 