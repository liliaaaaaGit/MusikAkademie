/*
  # Create lessons tracking system

  1. New Tables
    - `lessons`
      - `id` (uuid, primary key)
      - `contract_id` (uuid, foreign key to contracts)
      - `lesson_number` (integer, 1-18)
      - `date` (date, nullable)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)

  2. Security
    - Enable RLS on `lessons` table
    - Add policies for admins and teachers to manage lessons
    - Teachers can only access lessons for their assigned students

  3. Functions
    - Auto-generate lessons when contracts are created
    - Update contract attendance count based on completed lessons

  4. Triggers
    - Auto-generate lessons on contract creation
    - Update attendance count when lessons are modified

  5. Data Migration
    - Generate lessons for existing contracts
*/

-- Create lessons table
CREATE TABLE IF NOT EXISTS lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id uuid NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
  lesson_number integer NOT NULL,
  date date,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT lessons_lesson_number_check CHECK (lesson_number >= 1 AND lesson_number <= 18),
  CONSTRAINT lessons_unique_contract_lesson UNIQUE (contract_id, lesson_number)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_lessons_contract_id ON lessons(contract_id);
CREATE INDEX IF NOT EXISTS idx_lessons_date ON lessons(date) WHERE date IS NOT NULL;

-- Enable RLS
ALTER TABLE lessons ENABLE ROW LEVEL SECURITY;

-- Create policies for lessons
CREATE POLICY "Admins can manage all lessons"
  ON lessons
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Teachers can read lessons of their students"
  ON lessons
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) OR 
    EXISTS (
      SELECT 1
      FROM contracts c
      JOIN students s ON c.student_id = s.id
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE c.id = lessons.contract_id AND p.id = auth.uid()
    )
  );

CREATE POLICY "Teachers can update lessons of their students"
  ON lessons
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) OR 
    EXISTS (
      SELECT 1
      FROM contracts c
      JOIN students s ON c.student_id = s.id
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE c.id = lessons.contract_id AND p.id = auth.uid()
    )
  );

-- Function to auto-generate lessons when contract is created
CREATE OR REPLACE FUNCTION auto_generate_lessons()
RETURNS TRIGGER AS $$
DECLARE
  lesson_count integer;
  i integer;
BEGIN
  -- Determine lesson count based on contract type
  IF NEW.type = 'ten_class_card' THEN
    lesson_count := 10;
  ELSIF NEW.type = 'half_year' THEN
    lesson_count := 18;
  ELSE
    lesson_count := 10; -- Default fallback
  END IF;

  -- Generate lesson entries
  FOR i IN 1..lesson_count LOOP
    INSERT INTO lessons (contract_id, lesson_number)
    VALUES (NEW.id, i);
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update attendance count based on completed lessons
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_count integer;
  total_count integer;
  contract_type text;
  contract_id_to_update uuid;
BEGIN
  -- Get the contract ID to update
  contract_id_to_update := COALESCE(NEW.contract_id, OLD.contract_id);

  -- Get contract type and total lessons
  SELECT c.type INTO contract_type
  FROM contracts c
  WHERE c.id = contract_id_to_update;

  IF contract_type = 'ten_class_card' THEN
    total_count := 10;
  ELSIF contract_type = 'half_year' THEN
    total_count := 18;
  ELSE
    total_count := 10;
  END IF;

  -- Count completed lessons (those with dates)
  SELECT COUNT(*)
  INTO completed_count
  FROM lessons
  WHERE contract_id = contract_id_to_update
    AND date IS NOT NULL;

  -- Update contract attendance count
  UPDATE contracts
  SET 
    attendance_count = completed_count || '/' || total_count,
    updated_at = now()
  WHERE id = contract_id_to_update;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS trigger_auto_generate_lessons ON contracts;
CREATE TRIGGER trigger_auto_generate_lessons
  AFTER INSERT ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_lessons();

DROP TRIGGER IF EXISTS trigger_update_contract_attendance_on_lesson_change ON lessons;
CREATE TRIGGER trigger_update_contract_attendance_on_lesson_change
  AFTER INSERT OR UPDATE OR DELETE ON lessons
  FOR EACH ROW
  EXECUTE FUNCTION update_contract_attendance();

-- Update existing contracts to generate lessons
DO $$
DECLARE
  contract_record RECORD;
  lesson_count integer;
  i integer;
BEGIN
  FOR contract_record IN SELECT id, type FROM contracts LOOP
    -- Check if lessons already exist for this contract
    IF NOT EXISTS (SELECT 1 FROM lessons WHERE contract_id = contract_record.id) THEN
      -- Determine lesson count
      IF contract_record.type = 'ten_class_card' THEN
        lesson_count := 10;
      ELSIF contract_record.type = 'half_year' THEN
        lesson_count := 18;
      ELSE
        lesson_count := 10;
      END IF;

      -- Generate lessons
      FOR i IN 1..lesson_count LOOP
        INSERT INTO lessons (contract_id, lesson_number)
        VALUES (contract_record.id, i);
      END LOOP;
    END IF;
  END LOOP;
END $$;

-- Update attendance counts for existing contracts
UPDATE contracts 
SET attendance_count = (
  SELECT 
    COALESCE(COUNT(l.date), 0) || '/' || 
    CASE 
      WHEN contracts.type = 'ten_class_card' THEN '10'
      WHEN contracts.type = 'half_year' THEN '18'
      ELSE '10'
    END
  FROM lessons l 
  WHERE l.contract_id = contracts.id
);