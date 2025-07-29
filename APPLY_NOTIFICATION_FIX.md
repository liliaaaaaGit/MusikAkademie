# How to Apply the Admin Notification Fix

## Step 1: Apply the Migration

### Option A: Via Supabase Dashboard (Recommended)
1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Copy the entire contents of `supabase/migrations/20250703170000_fix_contract_completion_notification.sql`
4. Paste into SQL Editor
5. Click **Run**

### Option B: Via Supabase CLI (if configured)
```bash
npx supabase db push
```

## Step 2: Verify the Fix is Applied

Run this query in the SQL Editor to check if the new functions exist:

```sql
SELECT 
  proname as function_name,
  pg_get_function_result(oid) as return_type
FROM pg_proc 
WHERE proname IN (
  'notify_contract_fulfilled',
  'verify_contract_notification_system',
  'find_missing_completion_notifications'
)
ORDER BY proname;
```

You should see 3 functions listed.

## Step 3: Test the Notification System

### Test 1: Verify Current System Status
```sql
-- Get an overview of all contracts and their notification status
SELECT * FROM verify_contract_notification_system();
```

This shows you:
- Which contracts are completed
- How many lessons are available vs excluded
- Which contracts should have notifications but don't

### Test 2: Find Contracts Missing Notifications
```sql
-- Find contracts that should have triggered notifications but didn't
SELECT * FROM find_missing_completion_notifications();
```

### Test 3: Check a Specific Contract
```sql
-- Replace 'your-contract-id' with an actual contract ID
SELECT * FROM verify_contract_notification_system('your-contract-id');
```

### Test 4: Force Completion Check (Admin Only)
```sql
-- Test the notification trigger for a specific contract
SELECT force_completion_check('your-contract-id');
```

## Step 4: Verify Admin Inbox Functionality

Check that notifications are appearing in the admin inbox:

```sql
-- View all contract completion notifications
SELECT 
  n.id,
  n.message,
  n.created_at,
  n.is_read,
  s.name as student_name,
  c.attendance_count
FROM notifications n
JOIN contracts c ON n.contract_id = c.id
JOIN students s ON c.student_id = s.id
WHERE n.type = 'contract_fulfilled'
ORDER BY n.created_at DESC;
```

## Step 5: Test with a Real Contract Completion

To test the fix thoroughly:

1. **Find a nearly complete contract:**
```sql
SELECT 
  c.id,
  s.name,
  c.attendance_count,
  COUNT(l.*) FILTER (WHERE l.is_available = true) as available_lessons,
  COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) as completed_lessons
FROM contracts c
JOIN students s ON c.student_id = s.id
LEFT JOIN lessons l ON l.contract_id = c.id
WHERE c.status = 'active'
GROUP BY c.id, s.name, c.attendance_count
HAVING COUNT(l.*) FILTER (WHERE l.is_available = true AND l.date IS NOT NULL) = 
       COUNT(l.*) FILTER (WHERE l.is_available = true) - 1  -- One lesson remaining
ORDER BY s.name;
```

2. **Complete the last lesson** through the UI
3. **Verify notification was created** immediately

## Expected Behavior After Fix

### ✅ Correct Behavior:
- **Contract with 10 total lessons, 3 excluded (7 available):**
  - Notification triggers when 7/7 available lessons are completed
  - Message shows: "7 von 7 verfügbaren Stunden, 3 ausgeschlossen"

- **Contract with 10 total lessons, 0 excluded:**
  - Notification triggers when 10/10 lessons are completed
  - Message shows: "10 von 10 Stunden"

### ❌ Previous (Incorrect) Behavior:
- Notification would only trigger at 10/10 total lessons
- Excluded lessons were ignored in completion logic

## Troubleshooting

### If notifications aren't being created:

1. **Check the trigger exists:**
```sql
SELECT * FROM pg_trigger WHERE tgname = 'trigger_contract_fulfilled_notification';
```

2. **Check for trigger errors:**
```sql
-- Look for any error messages in logs
SELECT * FROM pg_stat_activity WHERE query LIKE '%notify_contract_fulfilled%';
```

3. **Manually test the function:**
```sql
-- This will show you exactly what the function sees for a contract
SELECT * FROM verify_contract_notification_system('your-contract-id');
```

### If notifications appear but not in admin inbox:

1. **Check notification policies:**
```sql
SELECT * FROM pg_policies WHERE tablename = 'notifications';
```

2. **Verify admin user role:**
```sql
SELECT get_user_role(); -- Should return 'admin'
```

## Rollback (if needed)

If you need to rollback, restore the previous function by running the SQL from the most recent migration file that contains `notify_contract_fulfilled` before this one.

## Performance Notes

The fix includes performance optimizations:
- Added indexes for faster notification queries
- Optimized lesson availability lookups
- Efficient completion percentage calculations

Monitor query performance with:
```sql
SELECT * FROM pg_stat_user_tables WHERE relname IN ('notifications', 'lessons', 'contracts');
``` 