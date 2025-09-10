-- Debug and fix auth-related database issues
-- This should help identify why user creation is failing

-- 1. Check if there are any problematic constraints
DO $$
DECLARE
  trigger_info RECORD;
BEGIN
  -- Check for any triggers on auth.users that might be causing issues
  RAISE LOG 'Checking for triggers on auth.users...';
  
  -- List all triggers on auth.users
  FOR trigger_info IN 
    SELECT trigger_name, event_manipulation, action_statement 
    FROM information_schema.triggers 
    WHERE event_object_table = 'users' 
    AND event_object_schema = 'auth'
  LOOP
    RAISE LOG 'Found trigger: % on % event', trigger_info.trigger_name, trigger_info.event_manipulation;
  END LOOP;
END $$;

-- 2. Check if there are any problematic functions
DO $$
DECLARE
  func_info RECORD;
BEGIN
  -- Check for functions that might be called during user creation
  RAISE LOG 'Checking for potentially problematic functions...';
  
  FOR func_info IN 
    SELECT routine_name, routine_definition 
    FROM information_schema.routines 
    WHERE routine_schema = 'public' 
    AND routine_definition ILIKE '%auth.users%'
  LOOP
    RAISE LOG 'Found function that references auth.users: %', func_info.routine_name;
  END LOOP;
END $$;

-- 3. Check database health
DO $$
DECLARE
  lock_info RECORD;
BEGIN
  -- Check if there are any locks or issues
  RAISE LOG 'Checking database health...';
  
  -- Check for any active locks
  FOR lock_info IN 
    SELECT locktype, database::regclass, relation::regclass, mode, granted 
    FROM pg_locks 
    WHERE database = (SELECT oid FROM pg_database WHERE datname = current_database())
  LOOP
    RAISE LOG 'Found lock: % on % (granted: %)', lock_info.locktype, lock_info.relation, lock_info.granted;
  END LOOP;
END $$;

-- 4. Ensure auth schema is accessible
GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO service_role;

-- 5. Check if there are any problematic RLS policies
DO $$
DECLARE
  policy_info RECORD;
BEGIN
  RAISE LOG 'Checking RLS policies...';
  
  FOR policy_info IN 
    SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
    FROM pg_policies 
    WHERE schemaname = 'auth'
  LOOP
    RAISE LOG 'Found RLS policy: % on %.%', policy_info.policyname, policy_info.schemaname, policy_info.tablename;
  END LOOP;
END $$;

-- 6. Try to create a test user to see what happens
DO $$
DECLARE
  test_user_id uuid;
BEGIN
  RAISE LOG 'Attempting to create a test user...';
  
  -- This is just for testing - we'll delete it immediately
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
    'test@example.com',
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
  
  -- Clean up the test user
  DELETE FROM auth.users WHERE id = test_user_id;
  RAISE LOG 'Test user cleaned up successfully';
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'Error creating test user: %', SQLERRM;
END $$; 