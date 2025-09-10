-- Comprehensive fix for auth-related issues
-- This should resolve the "Database error saving new user" issue

-- 1. Remove any problematic triggers on auth.users
DROP TRIGGER IF EXISTS enforce_signup_whitelist ON auth.users;
DROP TRIGGER IF EXISTS handle_new_user ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 2. Check and fix profiles table structure
-- Ensure the profiles table exists and has correct structure
DO $$
BEGIN
  -- Check if profiles table exists
  IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'profiles') THEN
    CREATE TABLE profiles (
      id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
      email text UNIQUE NOT NULL,
      full_name text NOT NULL,
      role text NOT NULL CHECK (role IN ('admin', 'teacher')),
      created_at timestamptz DEFAULT now()
    );
  END IF;
END $$;

-- 3. Ensure correct column types and constraints
ALTER TABLE profiles 
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN email SET NOT NULL,
  ALTER COLUMN full_name SET NOT NULL,
  ALTER COLUMN role SET NOT NULL;

-- 4. Drop and recreate RLS policies for profiles
DROP POLICY IF EXISTS "Users can read own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Allow profile creation for authenticated users" ON profiles;
DROP POLICY IF EXISTS "Allow service role profile creation" ON profiles;

-- 5. Create proper RLS policies
CREATE POLICY "Users can read own profile"
  ON profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Allow profile creation for authenticated users"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Allow service role profile creation"
  ON profiles FOR INSERT
  TO service_role
  WITH CHECK (true);

-- 6. Ensure RLS is enabled
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 7. Check for any problematic functions and recreate them
DROP FUNCTION IF EXISTS create_profile_after_signup(uuid, text);

-- 8. Create a simple, robust function
CREATE OR REPLACE FUNCTION create_profile_after_signup(
  user_id uuid,
  user_email text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  teacher_record teachers%ROWTYPE;
  profile_record profiles%ROWTYPE;
BEGIN
  -- Check if user already has a profile
  SELECT * INTO profile_record FROM profiles WHERE id = user_id;
  IF FOUND THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Profil existiert bereits für diesen Benutzer'
    );
  END IF;

  -- Find the teacher record by email (case-insensitive)
  SELECT * INTO teacher_record 
  FROM teachers 
  WHERE LOWER(email) = LOWER(user_email);
  
  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Keine Lehrkraft mit dieser E-Mail gefunden'
    );
  END IF;

  -- Check if teacher already has a profile
  IF teacher_record.profile_id IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Diese Lehrkraft hat bereits ein Konto'
    );
  END IF;

  -- Create the profile
  INSERT INTO profiles (id, email, full_name, role)
  VALUES (user_id, user_email, teacher_record.name, 'teacher')
  RETURNING * INTO profile_record;

  -- Update the teacher record to link it to the profile
  UPDATE teachers 
  SET profile_id = user_id
  WHERE id = teacher_record.id;

  -- Return success
  RETURN json_build_object(
    'success', true,
    'message', 'Profil erfolgreich erstellt',
    'profile_id', profile_record.id,
    'teacher_id', teacher_record.id
  );

EXCEPTION
  WHEN OTHERS THEN
    -- Log the error for debugging
    RAISE LOG 'create_profile_after_signup error: %', SQLERRM;
    RETURN json_build_object(
      'success', false,
      'message', 'Fehler beim Erstellen des Profils: ' || SQLERRM
    );
END;
$$;

-- 9. Grant execute permission
GRANT EXECUTE ON FUNCTION create_profile_after_signup(uuid, text) TO authenticated;

-- 10. Log completion
DO $$
BEGIN
  RAISE LOG 'Comprehensive auth fix completed successfully';
END $$; 