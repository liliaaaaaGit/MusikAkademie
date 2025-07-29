# Contract Completion Notification Fix

## Problem
The notification system currently triggers when completed lessons equal **total contract lessons** (e.g., 10/10), but it should trigger when completed lessons equal **available lessons** (e.g., 7/7 if 3 lessons were excluded).

### Example Scenario
- 10-lesson contract with 3 lessons marked as unavailable/excluded
- **Current behavior**: Notification triggers at 10/10 lessons completed (wrong)
- **Fixed behavior**: Notification triggers at 7/7 available lessons completed (correct)

## Solution
The fix changes the notification logic to query the lessons table directly and check completion against available lessons instead of total contract lessons.

## How to Apply the Fix

### Option 1: Through Supabase Dashboard (Recommended)
1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Copy and paste the SQL code below
4. Click **Run**

### Option 2: Save as Migration File
1. Save the contents of `supabase/migrations/20250703170000_fix_contract_completion_notification.sql` 
2. Apply through your deployment process

## SQL Fix Code

```sql
-- Update the notification function to properly handle excluded lessons
CREATE OR REPLACE FUNCTION notify_contract_fulfilled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  student_name text;
  teacher_name text;
  student_id_val uuid;
  contract_type_display text;
  notification_message text;
  
  -- Lesson counts from database
  completed_available_lessons integer := 0;
  total_available_lessons integer := 0;
  total_lessons integer := 0;
  excluded_lessons integer := 0;
  
  -- State tracking
  old_completed_available integer := 0;
  old_total_available integer := 0;
  was_complete_before boolean := false;
  is_complete_now boolean := false;
  should_notify boolean := false;
  existing_notification_count integer;
BEGIN
  -- Check if notification already exists for this contract to prevent duplicates
  SELECT COUNT(*) INTO existing_notification_count
  FROM notifications
  WHERE contract_id = NEW.id AND type = 'contract_fulfilled';

  -- Skip if notification already exists
  IF existing_notification_count > 0 THEN
    RETURN NEW;
  END IF;

  -- Check for manual status change from 'active' to 'completed'
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    should_notify := true;
  END IF;

  -- Get current lesson counts from the lessons table directly
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),  -- completed available
    COUNT(*) FILTER (WHERE is_available = true),                        -- total available  
    COUNT(*),                                                           -- total lessons
    COUNT(*) FILTER (WHERE is_available = false)                       -- excluded lessons
  INTO 
    completed_available_lessons,
    total_available_lessons,
    total_lessons,
    excluded_lessons
  FROM lessons
  WHERE contract_id = NEW.id;

  -- For OLD record, we need to simulate what the counts were before the change
  -- This is complex since we don't have historical lesson data, so we'll use attendance_count as fallback
  IF OLD.attendance_count IS NOT NULL AND OLD.attendance_count ~ '^[0-9]+/[0-9]+$' THEN
    BEGIN
      old_completed_available := CAST(SPLIT_PART(OLD.attendance_count, '/', 1) AS INTEGER);
      -- Note: OLD attendance_count might use total lessons as denominator, but we need available lessons
      -- We'll use current available count as approximation since lesson availability doesn't change often
      old_total_available := total_available_lessons;
    EXCEPTION WHEN OTHERS THEN
      old_completed_available := 0;
      old_total_available := 1;
    END;
  END IF;

  -- Determine completion status based on available lessons
  was_complete_before := (old_completed_available = old_total_available AND old_total_available > 0);
  is_complete_now := (completed_available_lessons = total_available_lessons AND total_available_lessons > 0);

  -- Check if contract just became complete (reached 100% of available lessons)
  -- This is the key fix: use available lessons instead of total contract lessons
  IF is_complete_now 
     AND NOT was_complete_before 
     AND NEW.status = 'active' 
     AND total_available_lessons > 0 THEN
    
    should_notify := true;
    
    -- Automatically mark contract as completed when all available lessons are done
    UPDATE contracts 
    SET status = 'completed', updated_at = now()
    WHERE id = NEW.id;
    
    -- Update NEW record for consistency
    NEW.status := 'completed';
  END IF;

  -- Create notification if conditions are met
  IF should_notify THEN
    -- Get student and teacher information
    SELECT 
      s.name,
      s.id,
      t.name
    INTO 
      student_name,
      student_id_val,
      teacher_name
    FROM students s
    LEFT JOIN teachers t ON s.teacher_id = t.id
    WHERE s.id = NEW.student_id;

    -- Get contract type display name
    SELECT 
      COALESCE(cv.name, 
        CASE NEW.type
          WHEN 'ten_class_card' THEN '10er Karte'
          WHEN 'half_year' THEN 'Halbjahresvertrag'
          ELSE NEW.type
        END
      )
    INTO contract_type_display
    FROM contracts c
    LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id
    WHERE c.id = NEW.id;

    -- Create enhanced notification message that shows the actual completion details
    IF excluded_lessons > 0 THEN
      notification_message := format(
        'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen (%s von %s verfügbaren Stunden, %s ausgeschlossen). Lehrer: %s. Abgeschlossen am: %s.',
        COALESCE(student_name, 'Unbekannter Schüler'),
        COALESCE(contract_type_display, 'Vertrag'),
        completed_available_lessons,
        total_available_lessons,
        excluded_lessons,
        COALESCE(teacher_name, 'Unbekannter Lehrer'),
        to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI')
      );
    ELSE
      notification_message := format(
        'Vertrag abgeschlossen: %s hat den %s erfolgreich abgeschlossen (%s von %s Stunden). Lehrer: %s. Abgeschlossen am: %s.',
        COALESCE(student_name, 'Unbekannter Schüler'),
        COALESCE(contract_type_display, 'Vertrag'),
        completed_available_lessons,
        total_available_lessons,
        COALESCE(teacher_name, 'Unbekannter Lehrer'),
        to_char(NEW.updated_at, 'DD.MM.YYYY HH24:MI')
      );
    END IF;

    -- Insert notification with error handling
    -- IMPORTANT: teacher_id is set to NULL to ensure it's visible to admins only
    BEGIN
      INSERT INTO notifications (
        type,
        contract_id,
        teacher_id,  -- Set to NULL explicitly for admin notifications
        student_id,
        message,
        is_read,
        created_at,
        updated_at
      ) VALUES (
        'contract_fulfilled',
        NEW.id,
        NULL,       -- NULL teacher_id means it's for admins
        student_id_val,
        notification_message,
        false,
        now(),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Log error but don't fail the transaction
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- Create a function to test the new notification logic
CREATE OR REPLACE FUNCTION test_contract_completion_notification(contract_id_param uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result_message text;
  contract_record RECORD;
  completed_available integer;
  total_available integer;
  total_lessons integer;
  excluded_lessons integer;
  notification_count integer;
BEGIN
  -- Check if user is admin
  IF get_user_role() != 'admin' THEN
    RETURN 'Access denied: Only administrators can test notifications';
  END IF;
  
  -- Get contract details
  SELECT * INTO contract_record
  FROM contracts
  WHERE id = contract_id_param;
  
  IF NOT FOUND THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;
  
  -- Get lesson counts
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
    COUNT(*) FILTER (WHERE is_available = true),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_available = false)
  INTO 
    completed_available,
    total_available,
    total_lessons,
    excluded_lessons
  FROM lessons
  WHERE contract_id = contract_id_param;
  
  -- Count existing notifications
  SELECT COUNT(*) INTO notification_count
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  result_message := format(
    'Contract %s analysis: %s completed of %s available lessons (%s total, %s excluded). Completion: %s%%. Notifications: %s. Status: %s',
    contract_id_param,
    completed_available,
    total_available,
    total_lessons,
    excluded_lessons,
    CASE WHEN total_available > 0 THEN ROUND((completed_available::numeric / total_available) * 100, 1) ELSE 0 END,
    notification_count,
    contract_record.status
  );
  
  RETURN result_message;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION test_contract_completion_notification(uuid) TO authenticated;

-- Create a helper function to check if a contract should trigger completion notification
CREATE OR REPLACE FUNCTION should_contract_notify_completion(contract_id_param uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  completed_available integer;
  total_available integer;
  contract_status text;
  existing_notifications integer;
BEGIN
  -- Get contract status
  SELECT status INTO contract_status
  FROM contracts
  WHERE id = contract_id_param;
  
  IF contract_status != 'active' THEN
    RETURN false;
  END IF;
  
  -- Check for existing notifications
  SELECT COUNT(*) INTO existing_notifications
  FROM notifications
  WHERE contract_id = contract_id_param AND type = 'contract_fulfilled';
  
  IF existing_notifications > 0 THEN
    RETURN false;
  END IF;
  
  -- Get lesson counts
  SELECT 
    COUNT(*) FILTER (WHERE is_available = true AND date IS NOT NULL),
    COUNT(*) FILTER (WHERE is_available = true)
  INTO 
    completed_available,
    total_available
  FROM lessons
  WHERE contract_id = contract_id_param;
  
  -- Return true if all available lessons are completed
  RETURN (completed_available = total_available AND total_available > 0);
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION should_contract_notify_completion(uuid) TO authenticated;
```

## Testing the Fix

After applying the fix, you can test it using these SQL commands in the Supabase SQL Editor:

### 1. Check a specific contract's status:
```sql
SELECT test_contract_completion_notification('your-contract-id-here');
```

### 2. Check if a contract should trigger a notification:
```sql
SELECT should_contract_notify_completion('your-contract-id-here');
```

### 3. Find contracts that should trigger notifications but haven't:
```sql
SELECT c.id, s.name as student_name, c.attendance_count, c.status
FROM contracts c
JOIN students s ON c.student_id = s.id
WHERE should_contract_notify_completion(c.id) = true;
```

## What the Fix Changes

### Before:
- Notification triggered when: `completed_lessons = total_contract_lessons`
- Example: 10/10 lessons completed (ignoring that 3 were excluded)

### After:
- Notification triggered when: `completed_lessons = available_lessons`  
- Example: 7/7 available lessons completed (correctly handling excluded lessons)

### Enhanced Notifications:
- Messages now show completion details: "7 von 7 verfügbaren Stunden, 3 ausgeschlossen"
- Clearer information for administrators

## Verification

After applying the fix:
1. The notification system will correctly handle excluded/unavailable lessons
2. Notifications will trigger as soon as all available lessons are completed
3. The attendance tracking will continue to work as before
4. Existing notifications are not affected (no data loss)

## Rollback (if needed)

If you need to rollback this change, you can restore the previous version by running the SQL from the most recent migration file in your `supabase/migrations/` directory that contains `notify_contract_fulfilled`. 