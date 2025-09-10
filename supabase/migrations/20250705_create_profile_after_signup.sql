-- Create function to handle profile creation after teacher signup
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
  result json;
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
    RETURN json_build_object(
      'success', false,
      'message', 'Fehler beim Erstellen des Profils: ' || SQLERRM
    );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_profile_after_signup(uuid, text) TO authenticated;

-- Add RLS policy to allow profile creation
CREATE POLICY "Allow profile creation for authenticated users"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id); 