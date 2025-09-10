# Authentication Fix Instructions

## Problem
The registration process creates users successfully, but profiles are not being created automatically, causing login failures.

## Solution Applied
I've implemented a **dual approach** to fix this issue:

### 1. Frontend Fallback (Already Applied)
- Modified `useAuth.ts` to automatically create profiles when they don't exist
- This provides immediate relief and should work right now

### 2. Database Trigger (Optional - For Long-term Solution)
To apply the database trigger for automatic profile creation, run this SQL in your Supabase SQL Editor:

```sql
-- Create profile after email confirmation
CREATE OR REPLACE FUNCTION handle_user_confirmation()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create profile if user is confirmed and profile doesn't exist
  IF NEW.email_confirmed_at IS NOT NULL AND OLD.email_confirmed_at IS NULL THEN
    -- Check if profile already exists
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = NEW.id) THEN
      -- Create profile with data from user metadata
      INSERT INTO profiles (
        id,
        email,
        full_name,
        role,
        created_at,
        updated_at
      ) VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'Unknown'),
        COALESCE(NEW.raw_user_meta_data->>'role', 'teacher'),
        NOW(),
        NOW()
      );
      
      -- Update teacher record with profile_id if teacher_id is provided
      IF NEW.raw_user_meta_data->>'teacher_id' IS NOT NULL THEN
        UPDATE teachers 
        SET profile_id = NEW.id 
        WHERE id = (NEW.raw_user_meta_data->>'teacher_id')::uuid;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
DROP TRIGGER IF EXISTS on_auth_user_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_confirmed
  AFTER UPDATE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_user_confirmation();
```

## How to Apply the Database Fix

1. Go to your Supabase Dashboard
2. Navigate to the SQL Editor
3. Copy and paste the SQL code above
4. Click "Run" to execute

## Current Status
✅ **Frontend fix applied** - Should work immediately  
⏳ **Database trigger** - Optional, for long-term solution  

## Testing
1. Try registering a new teacher account
2. Confirm the email
3. Try logging in - it should work now!

The frontend fallback should handle the profile creation automatically, so the authentication should work right away. 