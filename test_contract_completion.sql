-- Test Contract Completion and Notifications
-- This manually triggers the notification system to test if it works

-- 1. Find a contract that should be completed
SELECT 
  c.id as contract_id,
  c.status,
  s.name as student_name,
  t.name as teacher_name,
  t.profile_id as teacher_profile_id,
  COUNT(l.*) as total_lessons,
  COUNT(l.*) FILTER (WHERE l.date IS NOT NULL) as completed_lessons,
  COUNT(l.*) FILTER (WHERE l.is_available = false) as excluded_lessons,
  (COUNT(l.*) FILTER (WHERE l.date IS NOT NULL) + COUNT(l.*) FILTER (WHERE l.is_available = false)) as completed_plus_excluded
FROM contracts c
LEFT JOIN students s ON c.student_id = s.id
LEFT JOIN teachers t ON s.teacher_id = t.id
LEFT JOIN lessons l ON c.id = l.contract_id
WHERE c.status = 'active'
GROUP BY c.id, c.status, s.name, t.name, t.profile_id
HAVING COUNT(l.*) > 0
  AND (COUNT(l.*) FILTER (WHERE l.date IS NOT NULL) + COUNT(l.*) FILTER (WHERE l.is_available = false)) >= COUNT(l.*)
ORDER BY completed_plus_excluded DESC
LIMIT 5;

-- 2. Manually trigger contract completion for testing
-- Replace 'YOUR_CONTRACT_ID' with an actual contract ID from step 1
/*
UPDATE contracts 
SET status = 'completed', updated_at = now()
WHERE id = 'YOUR_CONTRACT_ID'::uuid;
*/

-- 3. Check if notifications were created after the update
/*
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
WHERE n.contract_id = 'YOUR_CONTRACT_ID'::uuid
ORDER BY n.created_at DESC;
*/

-- 4. Test the batch_update_lessons function
-- Replace with actual lesson data
/*
SELECT batch_update_lessons('[
  {
    "id": "YOUR_LESSON_ID",
    "contract_id": "YOUR_CONTRACT_ID",
    "date": "2024-01-01",
    "comment": "Test lesson completion",
    "is_available": true
  }
]'::jsonb);
*/ 