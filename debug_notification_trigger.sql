-- Debug Notification Trigger
-- This helps identify why teacher notifications aren't working

-- 1. Check if the trigger exists and is properly attached
SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgfoid::regproc as function_name,
  tgenabled as enabled
FROM pg_trigger 
WHERE tgname = 'trigger_contract_fulfilled_notification';

-- 2. Check if the notification function exists
SELECT 
  proname as function_name,
  proargtypes::regtype[] as argument_types,
  prorettype::regtype as return_type
FROM pg_proc 
WHERE proname = 'notify_contract_fulfilled';

-- 3. Check recent contract status changes
SELECT 
  c.id as contract_id,
  c.status,
  c.updated_at,
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
WHERE c.status = 'completed'
  AND c.updated_at > now() - interval '1 day'
GROUP BY c.id, c.status, c.updated_at, s.name, t.name, t.profile_id
ORDER BY c.updated_at DESC;

-- 4. Check if notifications were created for completed contracts
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
  s.name as student_name,
  c.status as contract_status
FROM notifications n
LEFT JOIN teachers t ON n.teacher_id = t.profile_id
LEFT JOIN students s ON n.student_id = s.id
LEFT JOIN contracts c ON n.contract_id = c.id
WHERE n.type = 'contract_fulfilled'
  AND n.created_at > now() - interval '1 day'
ORDER BY n.created_at DESC;

-- 5. Test the contract completion check function manually
-- Replace 'YOUR_CONTRACT_ID' with an actual contract ID
/*
SELECT check_contract_completion_after_lessons('YOUR_CONTRACT_ID'::uuid);
*/

-- 6. Check if teachers have proper profile_id values
SELECT 
  t.id as teacher_id,
  t.name as teacher_name,
  t.profile_id,
  p.id as profile_id_from_profiles,
  p.role,
  p.email
FROM teachers t
LEFT JOIN profiles p ON t.profile_id = p.id
WHERE t.profile_id IS NOT NULL
ORDER BY t.name;

-- 7. Manually trigger a contract completion to test the notification
-- Replace the UUIDs with actual values from your database
/*
UPDATE contracts 
SET status = 'completed', updated_at = now()
WHERE id = 'YOUR_CONTRACT_ID'::uuid;
*/ 