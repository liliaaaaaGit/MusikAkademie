-- Test Lesson Tracking Functions
-- Run this in your Supabase SQL Editor to test the functions

-- 1. Test the batch_update_lessons function with a dummy update
SELECT batch_update_lessons('[
  {
    "id": "00000000-0000-0000-0000-000000000000",
    "contract_id": "00000000-0000-0000-0000-000000000000",
    "date": "2024-01-01",
    "comment": "Test lesson",
    "is_available": true
  }
]'::jsonb);

-- 2. Check if the function exists and is working
SELECT 
  proname as function_name,
  proargtypes::regtype[] as argument_types,
  prorettype::regtype as return_type
FROM pg_proc 
WHERE proname = 'batch_update_lessons';

-- 3. Check if the notification trigger exists
SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgfoid::regproc as function_name
FROM pg_trigger 
WHERE tgname = 'trigger_contract_fulfilled_notification';

-- 4. Check if the notification function exists
SELECT 
  proname as function_name,
  proargtypes::regtype[] as argument_types,
  prorettype::regtype as return_type
FROM pg_proc 
WHERE proname = 'notify_contract_fulfilled';

-- 5. Test with a real contract (if you have one)
-- Replace the UUIDs with actual contract and lesson IDs from your database
/*
SELECT batch_update_lessons('[
  {
    "id": "YOUR_LESSON_ID_HERE",
    "contract_id": "YOUR_CONTRACT_ID_HERE", 
    "date": "2024-01-01",
    "comment": "Test lesson",
    "is_available": true
  }
]'::jsonb);
*/ 