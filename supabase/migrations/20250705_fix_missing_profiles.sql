-- Fix missing profiles for existing users
-- This will create profiles for users that were created but don't have profiles

-- 1. Create profiles for any users that exist in auth.users but not in profiles
INSERT INTO profiles (id, email, full_name, role)
SELECT 
  au.id,
  au.email,
  COALESCE(au.raw_user_meta_data->>'full_name', au.email) as full_name,
  COALESCE(au.raw_user_meta_data->>'role', 'teacher') as role
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL
  AND au.email_confirmed_at IS NOT NULL  -- Only confirmed users
  AND au.deleted_at IS NULL;  -- Not deleted users

-- 2. Update teacher records to link with profiles
UPDATE teachers 
SET profile_id = p.id
FROM profiles p
WHERE teachers.email = p.email 
  AND teachers.profile_id IS NULL;

-- 3. Log what was created
DO $$
DECLARE
  profile_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO profile_count 
  FROM profiles 
  WHERE created_at >= NOW() - INTERVAL '1 hour';
  
  RAISE LOG 'Created % new profiles for existing users', profile_count;
END $$; 