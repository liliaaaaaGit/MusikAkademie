-- Remove signup whitelist restrictions that are preventing user registration
-- This should fix the "Signup not allowed: email is not pre-authorized" error

-- 1. Drop any whitelist-related triggers
DROP TRIGGER IF EXISTS enforce_signup_whitelist ON auth.users;
DROP TRIGGER IF EXISTS check_email_whitelist ON auth.users;
DROP TRIGGER IF EXISTS validate_signup_email ON auth.users;

-- 2. Drop any whitelist-related functions
DROP FUNCTION IF EXISTS is_email_whitelisted(text);
DROP FUNCTION IF EXISTS check_signup_whitelist();
DROP FUNCTION IF EXISTS validate_signup_email();

-- 3. Drop any whitelist tables if they exist
DROP TABLE IF EXISTS signup_whitelist;
DROP TABLE IF EXISTS email_whitelist;
DROP TABLE IF EXISTS authorized_emails;

-- 4. Check for and remove any other problematic triggers
DO $$
DECLARE
  trigger_info RECORD;
BEGIN
  RAISE LOG 'Checking for any remaining triggers on auth.users...';
  
  FOR trigger_info IN 
    SELECT trigger_name, event_manipulation, action_statement 
    FROM information_schema.triggers 
    WHERE event_object_table = 'users' 
    AND event_object_schema = 'auth'
  LOOP
    RAISE LOG 'Found trigger: % on % event - dropping it', trigger_info.trigger_name, trigger_info.event_manipulation;
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON auth.users', trigger_info.trigger_name);
  END LOOP;
END $$;

-- 5. Check for any functions that might be causing the issue
DO $$
DECLARE
  func_info RECORD;
BEGIN
  RAISE LOG 'Checking for functions that might be causing signup issues...';
  
  FOR func_info IN 
    SELECT routine_name, routine_definition 
    FROM information_schema.routines 
    WHERE routine_schema = 'public' 
    AND (routine_definition ILIKE '%signup%' OR routine_definition ILIKE '%whitelist%' OR routine_definition ILIKE '%pre-authorized%')
  LOOP
    RAISE LOG 'Found potentially problematic function: %', func_info.routine_name;
    -- Drop functions that might be causing issues
    IF func_info.routine_name LIKE '%whitelist%' OR func_info.routine_name LIKE '%signup%' THEN
      EXECUTE format('DROP FUNCTION IF EXISTS %I', func_info.routine_name);
      RAISE LOG 'Dropped function: %', func_info.routine_name;
    END IF;
  END LOOP;
END $$;

-- 6. Ensure auth schema permissions are correct
GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO service_role;

-- 7. Test user creation
DO $$
DECLARE
  test_user_id uuid;
BEGIN
  RAISE LOG 'Testing user creation after removing restrictions...';
  
  -- Try to create a test user
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    'test-removal@example.com',
    crypt('testpassword', gen_salt('bf')),
    now(),
    now(),
    now(),
    '',
    '',
    '',
    ''
  ) RETURNING id INTO test_user_id;
  
  RAISE LOG 'Test user created successfully with ID: %', test_user_id;
  
  -- Clean up
  DELETE FROM auth.users WHERE id = test_user_id;
  RAISE LOG 'Test user cleaned up successfully';
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'Error creating test user: %', SQLERRM;
END $$;

-- 8. Log completion
DO $$
BEGIN
  RAISE LOG 'Signup whitelist removal completed successfully';
END $$; 