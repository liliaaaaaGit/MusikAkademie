/*
  # Update Trial Appointments System

  1. Database Changes
    - Rename trial_lessons table to trial_appointments
    - Update column names and constraints
    - Add new RPC function for accepting trials
    - Update RLS policies for new permission logic

  2. New Function
    - `accept_trial(_trial_id uuid)` - Atomic function to accept trials

  3. Updated RLS Policies
    - Teachers can create, edit own, and accept open trials
    - Admins have full access
    - First-come-first-serve logic for acceptance

  4. Security
    - Prevent double acceptance through atomic operations
    - Role-based access control
*/

-- Rename trial_lessons to trial_appointments if not already done
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'trial_lessons') THEN
    -- Drop existing policies
    DROP POLICY IF EXISTS "Admins can manage all trial lessons" ON trial_lessons;
    DROP POLICY IF EXISTS "Teachers can read all trial lessons" ON trial_lessons;
    DROP POLICY IF EXISTS "Teachers can update assigned trial lessons" ON trial_lessons;
    
    -- Rename table
    ALTER TABLE trial_lessons RENAME TO trial_appointments;
    
    -- Update column names for clarity
    ALTER TABLE trial_appointments RENAME COLUMN assigned_teacher_id TO teacher_id;
    
    -- Update status constraint
    ALTER TABLE trial_appointments DROP CONSTRAINT IF EXISTS trial_lessons_status_check;
    ALTER TABLE trial_appointments ADD CONSTRAINT trial_appointments_status_check 
      CHECK (status IN ('open', 'accepted'));
    
    -- Update indexes
    DROP INDEX IF EXISTS idx_trial_lessons_assigned_teacher_id;
    CREATE INDEX IF NOT EXISTS idx_trial_appointments_teacher_id ON trial_appointments(teacher_id);
    CREATE INDEX IF NOT EXISTS idx_trial_appointments_status ON trial_appointments(status);
    
    -- Update foreign key constraint names
    ALTER TABLE trial_appointments DROP CONSTRAINT IF EXISTS trial_lessons_assigned_teacher_id_fkey;
    ALTER TABLE trial_appointments DROP CONSTRAINT IF EXISTS trial_lessons_created_by_fkey;
    
    ALTER TABLE trial_appointments ADD CONSTRAINT trial_appointments_teacher_id_fkey 
      FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE SET NULL;
    ALTER TABLE trial_appointments ADD CONSTRAINT trial_appointments_created_by_fkey 
      FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Create the accept_trial RPC function
CREATE OR REPLACE FUNCTION accept_trial(_trial_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_teacher_id uuid;
BEGIN
  -- Get the current user's teacher ID
  SELECT t.id INTO current_teacher_id
  FROM teachers t
  JOIN profiles p ON t.profile_id = p.id
  WHERE p.id = auth.uid();
  
  IF current_teacher_id IS NULL THEN
    RAISE EXCEPTION 'Teacher profile not found';
  END IF;
  
  -- Atomically update the trial appointment
  UPDATE trial_appointments
  SET
    status = 'accepted',
    teacher_id = current_teacher_id
  WHERE id = _trial_id
    AND status = 'open';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Trial already accepted or does not exist';
  END IF;
END;
$$;

-- Create new RLS policies for trial_appointments
CREATE POLICY "Admins can manage all trial appointments"
  ON trial_appointments
  FOR ALL
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read all trial appointments"
  ON trial_appointments
  FOR SELECT
  TO authenticated
  USING (get_user_role() IN ('admin', 'teacher'));

CREATE POLICY "Teachers can create trial appointments"
  ON trial_appointments
  FOR INSERT
  TO authenticated
  WITH CHECK (
    get_user_role() IN ('admin', 'teacher')
  );

CREATE POLICY "Teachers can edit own trial appointments"
  ON trial_appointments
  FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    (
      get_user_role() = 'teacher' AND
      created_by = auth.uid()
    )
  );

CREATE POLICY "Teachers can accept open trials"
  ON trial_appointments
  FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    (
      get_user_role() = 'teacher' AND
      status = 'open'
    )
  )
  WITH CHECK (
    get_user_role() = 'admin' OR
    (
      get_user_role() = 'teacher' AND
      status = 'accepted'
    )
  );

CREATE POLICY "Only admins can delete trial appointments"
  ON trial_appointments
  FOR DELETE
  TO authenticated
  USING (get_user_role() = 'admin');

-- Update any existing 'assigned' status to 'accepted'
UPDATE trial_appointments SET status = 'accepted' WHERE status = 'assigned';