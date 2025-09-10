-- Apply authentication fixes
-- This file contains the fixes for the registration and login issues

-- Create a simple RPC function to create profiles
CREATE OR REPLACE FUNCTION create_profile_for_user(
  user_id uuid,
  user_email text,
  user_full_name text,
  user_role text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  profile_record profiles%ROWTYPE;
BEGIN
  -- Insert the profile
  INSERT INTO profiles (id, email, full_name, role)
  VALUES (user_id, user_email, user_full_name, user_role)
  RETURNING * INTO profile_record;
  
  -- Return the created profile as JSON
  RETURN row_to_json(profile_record);
END;
$$;

-- Create profile after email confirmation
-- This trigger will create a profile when a user confirms their email

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
        role
      ) VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'Unknown'),
        COALESCE(NEW.raw_user_meta_data->>'role', 'teacher')
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

-- Ensure RLS policies allow profile creation
DROP POLICY IF EXISTS "Allow profile creation for authenticated users" ON profiles;
CREATE POLICY "Allow profile creation for authenticated users"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Allow service role to create profiles
DROP POLICY IF EXISTS "Allow service role profile creation" ON profiles;
CREATE POLICY "Allow service role profile creation"
  ON profiles FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Also allow service role to update teachers
CREATE POLICY "Allow service role teacher updates"
  ON teachers FOR UPDATE
  TO service_role
  WITH CHECK (true); 