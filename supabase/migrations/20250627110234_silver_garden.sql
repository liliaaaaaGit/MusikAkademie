/*
  # Auto-insert teachers trigger

  1. New Function
    - `auto_insert_teacher()` - Function to automatically create teacher records
    
  2. New Trigger
    - Triggers after INSERT on profiles table
    - Only creates teacher record if role is 'teacher'
    - Uses profile data to populate teacher fields
    
  3. Changes
    - Automatically creates teacher records for new teacher profiles
    - Ensures all teachers are available in dropdowns immediately
    - Uses profile data for name and email fields
*/

-- Create function to automatically insert teacher records
CREATE OR REPLACE FUNCTION auto_insert_teacher()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create teacher record if the role is 'teacher'
  IF NEW.role = 'teacher' THEN
    INSERT INTO teachers (
      profile_id,
      name,
      email,
      instrument,
      phone,
      student_count,
      created_at
    ) VALUES (
      NEW.id,
      NEW.full_name,
      NEW.email,
      '', -- Empty instrument for now
      '', -- Empty phone for now
      0,  -- Default student count
      now()
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-insert teachers
DROP TRIGGER IF EXISTS trigger_auto_insert_teacher ON profiles;
CREATE TRIGGER trigger_auto_insert_teacher
  AFTER INSERT ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_insert_teacher();