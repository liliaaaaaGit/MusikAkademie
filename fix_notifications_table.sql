-- Fix Notifications Table Structure
-- This updates the foreign key constraints to work with RLS

BEGIN;

-- =====================================================
-- 1. CHECK CURRENT STRUCTURE
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
-- 2. DROP EXISTING FOREIGN KEY CONSTRAINTS
-- =====================================================

-- Drop the foreign key constraint that's causing the issue
ALTER TABLE notifications 
DROP CONSTRAINT IF EXISTS notifications_teacher_id_fkey;

-- =====================================================
-- 3. ADD NEW FOREIGN KEY CONSTRAINT TO PROFILES
-- =====================================================

-- Add foreign key constraint to profiles table instead
ALTER TABLE notifications 
ADD CONSTRAINT notifications_teacher_id_fkey 
FOREIGN KEY (teacher_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- =====================================================
-- 4. VERIFY THE CHANGE
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

-- =====================================================
-- 5. TEST NOTIFICATION CREATION
-- =====================================================

-- Test creating a notification with a profile ID
DO $$
DECLARE
  test_teacher_profile_id uuid;
  test_student_id uuid;
  test_contract_id uuid;
BEGIN
  -- Get a test teacher profile ID
  SELECT p.id INTO test_teacher_profile_id
  FROM profiles p
  WHERE p.role = 'teacher'
  LIMIT 1;
  
  -- Get a test student ID
  SELECT s.id INTO test_student_id
  FROM students s
  LIMIT 1;
  
  -- Get a test contract ID
  SELECT c.id INTO test_contract_id
  FROM contracts c
  LIMIT 1;
  
  -- Create a test notification
  IF test_teacher_profile_id IS NOT NULL AND test_student_id IS NOT NULL AND test_contract_id IS NOT NULL THEN
    INSERT INTO notifications (
      type,
      contract_id,
      teacher_id,
      student_id,
      message,
      is_read,
      created_at,
      updated_at
    ) VALUES (
      'test_notification',
      test_contract_id,
      test_teacher_profile_id,
      test_student_id,
      'Test notification after fixing foreign key constraint',
      false,
      now(),
      now()
    );
    
    RAISE NOTICE 'Test notification created successfully for teacher profile ID: %', test_teacher_profile_id;
  ELSE
    RAISE NOTICE 'Could not create test notification - missing test data';
  END IF;
END $$;

COMMIT; 