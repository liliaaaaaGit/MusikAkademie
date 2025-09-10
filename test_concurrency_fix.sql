-- Test Concurrency Fix
-- Run this in your Supabase SQL Editor to test the fix

-- 1. Test the simplified batch_update_lessons function
SELECT batch_update_lessons('[
  {
    "id": "00000000-0000-0000-0000-000000000000",
    "contract_id": "00000000-0000-0000-0000-000000000000",
    "date": "2024-01-01",
    "comment": "Test lesson",
    "is_available": true
  }
]'::jsonb);

-- 2. Check if the new function exists
SELECT 
  proname as function_name,
  proargtypes::regtype[] as argument_types,
  prorettype::regtype as return_type
FROM pg_proc 
WHERE proname = 'check_contract_completion_after_lessons';

-- 3. Check if the notification trigger exists
SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgfoid::regproc as function_name
FROM pg_trigger 
WHERE tgname = 'trigger_contract_fulfilled_notification';

-- 4. Check current contract statuses
SELECT 
  c.id,
  c.status,
  s.name as student_name,
  COUNT(l.*) as total_lessons,
  COUNT(l.*) FILTER (WHERE l.date IS NOT NULL) as completed_lessons,
  COUNT(l.*) FILTER (WHERE l.is_available = false) as excluded_lessons
FROM contracts c
LEFT JOIN students s ON c.student_id = s.id
LEFT JOIN lessons l ON c.id = l.contract_id
WHERE c.status = 'active'
GROUP BY c.id, c.status, s.name
HAVING COUNT(l.*) > 0
ORDER BY completed_lessons DESC
LIMIT 5;

-- 5. Test the contract completion check function with a real contract
-- Replace 'YOUR_CONTRACT_ID' with an actual contract ID from your database
/*
SELECT check_contract_completion_after_lessons('YOUR_CONTRACT_ID'::uuid);
*/ 