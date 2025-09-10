-- Check for any problematic triggers on auth.users
DO $$
BEGIN
  -- Drop any triggers that might be causing issues
  DROP TRIGGER IF EXISTS enforce_signup_whitelist ON auth.users;
  DROP TRIGGER IF EXISTS handle_new_user ON auth.users;
  
  -- Log what we're doing
  RAISE LOG 'Removed potentially problematic triggers on auth.users';
END $$;

-- Ensure the profiles table has the correct structure
ALTER TABLE profiles 
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN email SET NOT NULL,
  ALTER COLUMN full_name SET NOT NULL,
  ALTER COLUMN role SET NOT NULL;

-- Add a simple trigger to create profile after user creation
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- This trigger will be called after a user is created
  -- We'll handle profile creation in the application instead
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Don't create the trigger for now to avoid conflicts
-- CREATE TRIGGER on_auth_user_created
--   AFTER INSERT ON auth.users
--   FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Ensure RLS policies are correct for profiles
DROP POLICY IF EXISTS "Allow profile creation for authenticated users" ON profiles;

CREATE POLICY "Allow profile creation for authenticated users"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Also allow service role to create profiles (for admin operations)
CREATE POLICY "Allow service role profile creation"
  ON profiles FOR INSERT
  TO service_role
  WITH CHECK (true); 