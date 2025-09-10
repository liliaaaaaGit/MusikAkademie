-- Test script to manually trigger notifications
-- Run this in Supabase SQL Editor after applying the migration

-- 1. First, apply the migration if not already done
-- Copy and paste the content of 20250705_restore_contract_completion_notifications.sql

-- 2. Test function to manually trigger a notification for a specific contract
CREATE OR REPLACE FUNCTION test_trigger_notification(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  contract_record RECORD;
  result_message text;
BEGIN
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;
  
  -- Manually trigger the notification by updating contract status
  UPDATE contracts 
  SET status = 'completed', updated_at = now()
  WHERE id = contract_id_param;
  
  RETURN 'Notification triggered for contract: ' || contract_id_param;
END;
$$;

-- 3. Test function to check completion status for all contracts
CREATE OR REPLACE FUNCTION check_all_contract_completion()
RETURNS TABLE(
  contract_id uuid,
  student_name text,
  teacher_name text,
  status text,
  total_lessons bigint,
  completed_lessons bigint,
  excluded_lessons bigint,
  should_be_completed boolean,
  has_notification boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH contract_stats AS (
    SELECT 
      c.id,
      s.name as student_name,
      t.name as teacher_name,
      c.status,
      COUNT(l.*) as total_lessons,
      COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) as completed_lessons,
      COUNT(l.*) FILTER (WHERE l.is_available = false) as excluded_lessons
    FROM contracts c
    LEFT JOIN students s ON c.student_id = s.id
    LEFT JOIN teachers t ON s.teacher_id = t.id
    LEFT JOIN lessons l ON c.id = l.contract_id
    GROUP BY c.id, c.status, s.name, t.name
  )
  SELECT 
    cs.id,
    cs.student_name,
    cs.teacher_name,
    cs.status,
    cs.total_lessons,
    cs.completed_lessons,
    cs.excluded_lessons,
    (cs.completed_lessons + cs.excluded_lessons >= cs.total_lessons) AND (cs.total_lessons > 0) as should_be_completed,
    EXISTS(SELECT 1 FROM notifications n WHERE n.contract_id = cs.id AND n.type = 'contract_fulfilled') as has_notification
  FROM contract_stats cs
  WHERE cs.total_lessons > 0
  ORDER BY cs.completed_lessons DESC, cs.total_lessons DESC;
END;
$$;

-- 4. Grant execute permissions
GRANT EXECUTE ON FUNCTION test_trigger_notification(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION check_all_contract_completion() TO authenticated;

-- 5. Test the functions
-- Check all contracts:
SELECT * FROM check_all_contract_completion();

-- To manually trigger a notification for a specific contract (replace with actual contract ID):
-- SELECT test_trigger_notification('your-contract-id-here'); 