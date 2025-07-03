/*
  # Musikakademie München Database Schema

  1. New Tables
    - `profiles`
      - `id` (uuid, primary key, references auth.users)
      - `email` (text, unique)
      - `full_name` (text)
      - `role` (text, either 'admin' or 'teacher')
      - `created_at` (timestamp)
    
    - `teachers`
      - `id` (uuid, primary key)
      - `profile_id` (uuid, foreign key to profiles)
      - `name` (text)
      - `email` (text)
      - `instrument` (text)
      - `phone` (text)
      - `student_count` (integer, default 0)
      - `created_at` (timestamp)
    
    - `students`
      - `id` (uuid, primary key)
      - `name` (text)
      - `instrument` (text)
      - `email` (text)
      - `phone` (text)
      - `teacher_id` (uuid, foreign key to teachers)
      - `contract_type` (text, 'ten_class_card' or 'half_year')
      - `contract_id` (uuid, foreign key to contracts)
      - `status` (text, 'active' or 'inactive')
      - `created_at` (timestamp)
    
    - `contracts`
      - `id` (uuid, primary key)
      - `student_id` (uuid, foreign key to students)
      - `type` (text, 'ten_class_card' or 'half_year')
      - `status` (text, 'active' or 'completed')
      - `attendance_count` (text, e.g. '3/10' or '15/18')
      - `attendance_dates` (jsonb array)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
    
    - `trial_lessons`
      - `id` (uuid, primary key)
      - `student_name` (text)
      - `instrument` (text)
      - `phone` (text)
      - `email` (text)
      - `status` (text, 'open' or 'assigned')
      - `assigned_teacher_id` (uuid, foreign key to teachers, optional)
      - `created_by` (uuid, foreign key to profiles)
      - `created_at` (timestamp)
    
    - `bank_ids`
      - `id` (uuid, primary key)
      - `profile_id` (uuid, foreign key to profiles)
      - `reference_id` (text, e.g. 'ID73')
      - `entity_type` (text, 'teacher' or 'student')
      - `entity_id` (uuid)
      - `created_at` (timestamp)

  2. Security
    - Enable RLS on all tables
    - Add policies for role-based access control
    - Admins can access all data
    - Teachers can only access their assigned data
*/

-- Create profiles table (extends auth.users)
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text UNIQUE NOT NULL,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('admin', 'teacher')),
  created_at timestamptz DEFAULT now()
);

-- Create teachers table
CREATE TABLE IF NOT EXISTS teachers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text NOT NULL,
  instrument text NOT NULL,
  phone text,
  student_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- Create contracts table (created before students due to FK reference)
CREATE TABLE IF NOT EXISTS contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid, -- Will be set after students table is created
  type text NOT NULL CHECK (type IN ('ten_class_card', 'half_year')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed')),
  attendance_count text DEFAULT '0/10',
  attendance_dates jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create students table
CREATE TABLE IF NOT EXISTS students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  instrument text NOT NULL,
  email text,
  phone text,
  teacher_id uuid REFERENCES teachers(id) ON DELETE SET NULL,
  contract_type text CHECK (contract_type IN ('ten_class_card', 'half_year')),
  contract_id uuid REFERENCES contracts(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at timestamptz DEFAULT now()
);

-- Add foreign key constraint to contracts table
ALTER TABLE contracts ADD CONSTRAINT fk_contracts_student_id 
  FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

-- Create trial_lessons table
CREATE TABLE IF NOT EXISTS trial_lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_name text NOT NULL,
  instrument text NOT NULL,
  phone text,
  email text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'assigned')),
  assigned_teacher_id uuid REFERENCES teachers(id) ON DELETE SET NULL,
  created_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);

-- Create bank_ids table
CREATE TABLE IF NOT EXISTS bank_ids (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  reference_id text NOT NULL,
  entity_type text NOT NULL CHECK (entity_type IN ('teacher', 'student')),
  entity_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trial_lessons ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_ids ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Users can read own profile"
  ON profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

-- RLS Policies for teachers
CREATE POLICY "Admins can manage all teachers"
  ON teachers FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Teachers can read all teachers"
  ON teachers FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'teacher')
    )
  );

CREATE POLICY "Teachers can update own record"
  ON teachers FOR UPDATE
  TO authenticated
  USING (
    profile_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for students
CREATE POLICY "Admins can manage all students"
  ON students FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Teachers can read their assigned students"
  ON students FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND t.id = students.teacher_id
    ) OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Teachers can update their assigned students"
  ON students FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND t.id = students.teacher_id
    ) OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for contracts
CREATE POLICY "Admins can manage all contracts"
  ON contracts FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Teachers can read contracts of their students"
  ON contracts FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM students s
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND s.id = contracts.student_id
    ) OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Teachers can update contracts of their students"
  ON contracts FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM students s
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND s.id = contracts.student_id
    ) OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for trial_lessons
CREATE POLICY "Admins can manage all trial lessons"
  ON trial_lessons FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Teachers can read all trial lessons"
  ON trial_lessons FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role IN ('admin', 'teacher')
    )
  );

CREATE POLICY "Teachers can update assigned trial lessons"
  ON trial_lessons FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND t.id = trial_lessons.assigned_teacher_id
    ) OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for bank_ids (Admin only access)
CREATE POLICY "Only admins can access bank IDs"
  ON bank_ids FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_teachers_profile_id ON teachers(profile_id);
CREATE INDEX IF NOT EXISTS idx_students_teacher_id ON students(teacher_id);
CREATE INDEX IF NOT EXISTS idx_contracts_student_id ON contracts(student_id);
CREATE INDEX IF NOT EXISTS idx_trial_lessons_assigned_teacher_id ON trial_lessons(assigned_teacher_id);
CREATE INDEX IF NOT EXISTS idx_bank_ids_entity ON bank_ids(entity_type, entity_id);

-- Create function to update student count on teachers table
CREATE OR REPLACE FUNCTION update_teacher_student_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE teachers 
    SET student_count = (
      SELECT COUNT(*) FROM students 
      WHERE teacher_id = OLD.teacher_id AND status = 'active'
    )
    WHERE id = OLD.teacher_id;
    RETURN OLD;
  ELSE
    UPDATE teachers 
    SET student_count = (
      SELECT COUNT(*) FROM students 
      WHERE teacher_id = NEW.teacher_id AND status = 'active'
    )
    WHERE id = NEW.teacher_id;
    
    IF TG_OP = 'UPDATE' AND OLD.teacher_id != NEW.teacher_id THEN
      UPDATE teachers 
      SET student_count = (
        SELECT COUNT(*) FROM students 
        WHERE teacher_id = OLD.teacher_id AND status = 'active'
      )
      WHERE id = OLD.teacher_id;
    END IF;
    
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for student count updates
DROP TRIGGER IF EXISTS trigger_update_teacher_student_count ON students;
CREATE TRIGGER trigger_update_teacher_student_count
  AFTER INSERT OR UPDATE OR DELETE ON students
  FOR EACH ROW EXECUTE FUNCTION update_teacher_student_count();

-- Create function to update contract attendance count
CREATE OR REPLACE FUNCTION update_attendance_count()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  
  -- Calculate attendance count based on attendance_dates array length
  IF NEW.type = 'ten_class_card' THEN
    NEW.attendance_count = (jsonb_array_length(NEW.attendance_dates) || '/10');
  ELSIF NEW.type = 'half_year' THEN
    NEW.attendance_count = (jsonb_array_length(NEW.attendance_dates) || '/18');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for attendance count updates
DROP TRIGGER IF EXISTS trigger_update_attendance_count ON contracts;
CREATE TRIGGER trigger_update_attendance_count
  BEFORE UPDATE ON contracts
  FOR EACH ROW EXECUTE FUNCTION update_attendance_count();