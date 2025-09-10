-- Debug script to check notification system status
-- Run this in Supabase SQL Editor

-- 1. Check if the notification function exists
SELECT 
  proname as function_name,
  prosrc as function_source
FROM pg_proc 
WHERE proname = 'notify_contract_fulfilled';

-- 2. Check if the trigger exists
SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgtype,
  proname as function_name
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE proname = 'notify_contract_fulfilled';

-- 3. Check if there are any existing notifications
SELECT 
  COUNT(*) as total_notifications,
  COUNT(*) FILTER (WHERE type = 'contract_fulfilled') as contract_fulfilled_notifications,
  COUNT(*) FILTER (WHERE is_read = false) as unread_notifications
FROM notifications;

-- 4. Check recent contracts and their status
SELECT 
  c.id,
  c.status,
  c.attendance_count,
  c.updated_at,
  s.name as student_name,
  t.name as teacher_name,
  COUNT(l.*) as total_lessons,
  COUNT(l.*) FILTER (WHERE l.date IS NOT NULL) as completed_lessons,
  COUNT(l.*) FILTER (WHERE l.is_available = false) as excluded_lessons
FROM contracts c
LEFT JOIN students s ON c.student_id = s.id
LEFT JOIN teachers t ON s.teacher_id = t.id
LEFT JOIN lessons l ON c.id = l.contract_id
GROUP BY c.id, c.status, c.attendance_count, c.updated_at, s.name, t.name
ORDER BY c.updated_at DESC
LIMIT 10;

-- 5. Test the completion detection logic manually
WITH contract_completion AS (
  SELECT 
    c.id,
    c.status,
    COUNT(l.*) as total_lessons,
    COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) as completed_lessons,
    COUNT(l.*) FILTER (WHERE l.is_available = false) as excluded_lessons,
    COUNT(l.*) FILTER (WHERE l.is_available = true) as available_lessons
  FROM contracts c
  LEFT JOIN lessons l ON c.id = l.contract_id
  GROUP BY c.id, c.status
)
SELECT 
  id,
  status,
  total_lessons,
  completed_lessons,
  excluded_lessons,
  available_lessons,
  (completed_lessons + excluded_lessons) as completed_plus_excluded,
  CASE 
    WHEN (completed_lessons + excluded_lessons >= total_lessons) AND (total_lessons > 0) 
    THEN 'SHOULD BE COMPLETED' 
    ELSE 'NOT COMPLETE' 
  END as completion_status
FROM contract_completion
WHERE total_lessons > 0
ORDER BY completed_lessons DESC, total_lessons DESC
LIMIT 10; 