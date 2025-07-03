/*
  # Contract Model Restructure

  1. New Tables
    - `contract_categories` - Main contract types (10er Karte, Halbjahresvertrag, etc.)
    - `contract_variants` - Detailed contract options with pricing and duration
    - `contract_discounts` - Available discounts with percentages and conditions

  2. Updated Tables
    - `contracts` - Add new columns for variant and pricing
    - Remove `contract_type` from `students` table

  3. Functions
    - Update lesson generation and attendance calculation
    - Add pricing calculation function

  4. Security
    - Enable RLS on new tables
    - Add appropriate policies for role-based access
*/

-- Create contract_categories table
CREATE TABLE IF NOT EXISTS contract_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  display_name text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now()
);

-- Create contract_variants table
CREATE TABLE IF NOT EXISTS contract_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_category_id uuid NOT NULL REFERENCES contract_categories(id) ON DELETE CASCADE,
  name text NOT NULL,
  duration_months integer, -- NULL for flexible duration
  group_type text NOT NULL CHECK (group_type IN ('single', 'group', 'duo', 'varies')),
  session_length_minutes integer, -- NULL for varies
  total_lessons integer, -- Used by lesson generation
  monthly_price numeric(10,2), -- NULL if one-time payment
  one_time_price numeric(10,2), -- NULL if monthly payment
  notes text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Create contract_discounts table
CREATE TABLE IF NOT EXISTS contract_discounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  discount_percent numeric(5,2) NOT NULL CHECK (discount_percent >= 0 AND discount_percent <= 100),
  conditions text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_contract_variants_category ON contract_variants(contract_category_id);
CREATE INDEX IF NOT EXISTS idx_contract_variants_active ON contract_variants(is_active);
CREATE INDEX IF NOT EXISTS idx_contract_discounts_active ON contract_discounts(is_active);

-- Enable RLS on new tables
ALTER TABLE contract_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_discounts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for contract_categories (read-only for teachers, full access for admins)
CREATE POLICY "Everyone can read contract categories"
  ON contract_categories FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins can manage contract categories"
  ON contract_categories FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for contract_variants (read-only for teachers, full access for admins)
CREATE POLICY "Everyone can read contract variants"
  ON contract_variants FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins can manage contract variants"
  ON contract_variants FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for contract_discounts (read-only for teachers, full access for admins)
CREATE POLICY "Everyone can read contract discounts"
  ON contract_discounts FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins can manage contract discounts"
  ON contract_discounts FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Populate contract_categories with the provided data
INSERT INTO contract_categories (name, display_name, description) VALUES
  ('ten_lesson_card', '10er Karte', 'Flexible 10-lesson packages'),
  ('half_year_contract', 'Halbjahresvertrag', '6-month contracts with regular lessons'),
  ('supplement_program', 'Ergänzungsprogramme', 'Supplementary music programs'),
  ('private_diploma', 'Diplomausbildung', 'Private diploma programs'),
  ('repetition_workshop', 'Repetitions-/Workshop-Stunden', 'Repetition and workshop sessions'),
  ('trial_package', 'Schnuppermomente', 'Trial lesson packages'),
  ('special_discount', 'Sondervereinbarung', 'Special discount arrangements')
ON CONFLICT (name) DO NOTHING;

-- Populate contract_variants with the provided data
DO $$
DECLARE
  ten_lesson_id uuid;
  half_year_id uuid;
  supplement_id uuid;
  diploma_id uuid;
  repetition_id uuid;
  trial_id uuid;
  special_id uuid;
BEGIN
  -- Get category IDs
  SELECT id INTO ten_lesson_id FROM contract_categories WHERE name = 'ten_lesson_card';
  SELECT id INTO half_year_id FROM contract_categories WHERE name = 'half_year_contract';
  SELECT id INTO supplement_id FROM contract_categories WHERE name = 'supplement_program';
  SELECT id INTO diploma_id FROM contract_categories WHERE name = 'private_diploma';
  SELECT id INTO repetition_id FROM contract_categories WHERE name = 'repetition_workshop';
  SELECT id INTO trial_id FROM contract_categories WHERE name = 'trial_package';
  SELECT id INTO special_id FROM contract_categories WHERE name = 'special_discount';

  -- Insert contract variants
  INSERT INTO contract_variants (contract_category_id, name, duration_months, group_type, session_length_minutes, total_lessons, monthly_price, one_time_price, notes) VALUES
    -- 10er Karte variants
    (ten_lesson_id, '10er Karte – 30min', NULL, 'single', 30, 10, NULL, 295.00, NULL),
    (ten_lesson_id, '10er Karte – 45min', NULL, 'single', 45, 10, NULL, 445.00, NULL),
    (ten_lesson_id, '10er Karte – 60min', NULL, 'single', 60, 10, NULL, 590.00, NULL),
    
    -- Halbjahresvertrag variants
    (half_year_id, 'Einzel – 30min', 6, 'single', 30, 18, 88.00, NULL, NULL),
    (half_year_id, 'Einzel – 45min', 6, 'single', 45, 18, 130.00, NULL, NULL),
    (half_year_id, 'Einzel – 60min', 6, 'single', 60, 18, 175.00, NULL, NULL),
    (half_year_id, 'Gruppe – 60min', 6, 'group', 60, 18, 66.00, NULL, NULL),
    (half_year_id, 'Zweier – 45min', 6, 'duo', 45, 18, 66.00, NULL, NULL),
    
    -- Ergänzungsprogramme
    (supplement_id, 'Gruppe – 45min', 6, 'group', 45, 18, 50.00, NULL, 'Ergänzungsfach'),
    
    -- Diplomausbildung
    (diploma_id, 'Oper/Operette – 2 Jahre', 24, 'single', 45, 72, 1080.00, NULL, 'Diploma – Kategorie A'),
    (diploma_id, 'Musical – 3 Jahre', 36, 'single', 45, 108, 840.00, NULL, 'Diploma – Kategorie B'),
    
    -- Repetitions-/Workshop-Stunden
    (repetition_id, 'Repetitionsstunden 10x60min', NULL, 'single', 60, 10, NULL, 530.00, NULL),
    (repetition_id, 'Workshop Klassik', NULL, 'group', NULL, 1, NULL, 200.00, NULL),
    (repetition_id, 'Workshop Modern/Musical', NULL, 'group', NULL, 1, NULL, 85.00, NULL),
    
    -- Schnuppermomente
    (trial_id, 'Schnuppermoment (ohne Instrument)', NULL, 'single', 30, 4, NULL, 120.00, '4x30min'),
    (trial_id, 'Schnuppermoment (mit Instrument)', NULL, 'single', 30, 4, NULL, 140.00, '4x30min + Instrument')
  ON CONFLICT DO NOTHING;
END $$;

-- Populate contract_discounts with the provided data
INSERT INTO contract_discounts (name, discount_percent, conditions) VALUES
  ('Family/Student Discount', 5.00, 'manually assignable'),
  ('Combo Booking (2 blocks)', 5.00, 'applies if 2 active blocks exist'),
  ('Combo Booking (3 blocks)', 10.00, 'applies if 3+ active blocks exist'),
  ('Half-Year Prepayment', 5.00, 'applies if paid upfront'),
  ('Full-Year Prepayment', 10.00, 'applies if paid upfront')
ON CONFLICT DO NOTHING;

-- Add new columns to contracts table
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS contract_variant_id uuid;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS discount_ids uuid[];
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS final_price numeric(10,2);
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS payment_type text CHECK (payment_type IN ('monthly', 'one_time'));

-- Add foreign key constraint for contract_variant_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'contracts_contract_variant_id_fkey'
  ) THEN
    ALTER TABLE contracts ADD CONSTRAINT contracts_contract_variant_id_fkey 
      FOREIGN KEY (contract_variant_id) REFERENCES contract_variants(id) ON DELETE RESTRICT;
  END IF;
END $$;

-- Create index for contract_variant_id
CREATE INDEX IF NOT EXISTS idx_contracts_variant ON contracts(contract_variant_id);

-- Migrate existing contracts to new structure
DO $$
DECLARE
  contract_record RECORD;
  ten_lesson_variant_id uuid;
  half_year_variant_id uuid;
BEGIN
  -- Get default variant IDs for migration
  SELECT cv.id INTO ten_lesson_variant_id 
  FROM contract_variants cv 
  JOIN contract_categories cc ON cv.contract_category_id = cc.id 
  WHERE cc.name = 'ten_lesson_card' AND cv.name = '10er Karte – 45min';
  
  SELECT cv.id INTO half_year_variant_id 
  FROM contract_variants cv 
  JOIN contract_categories cc ON cv.contract_category_id = cc.id 
  WHERE cc.name = 'half_year_contract' AND cv.name = 'Einzel – 45min';

  -- Update existing contracts
  FOR contract_record IN SELECT id, type FROM contracts WHERE contract_variant_id IS NULL LOOP
    IF contract_record.type = 'ten_class_card' THEN
      UPDATE contracts 
      SET 
        contract_variant_id = ten_lesson_variant_id,
        payment_type = 'one_time',
        final_price = 445.00
      WHERE id = contract_record.id;
    ELSIF contract_record.type = 'half_year' THEN
      UPDATE contracts 
      SET 
        contract_variant_id = half_year_variant_id,
        payment_type = 'monthly',
        final_price = 130.00
      WHERE id = contract_record.id;
    END IF;
  END LOOP;
END $$;

-- Update auto_generate_lessons function to use contract_variants
CREATE OR REPLACE FUNCTION auto_generate_lessons()
RETURNS TRIGGER AS $$
DECLARE
  lesson_count integer;
  i integer;
BEGIN
  -- Get lesson count from contract variant
  SELECT cv.total_lessons INTO lesson_count
  FROM contract_variants cv
  WHERE cv.id = NEW.contract_variant_id;

  -- Default fallback if variant not found
  IF lesson_count IS NULL THEN
    lesson_count := 10;
  END IF;

  -- Generate lesson entries
  FOR i IN 1..lesson_count LOOP
    INSERT INTO lessons (contract_id, lesson_number)
    VALUES (NEW.id, i);
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update contract attendance calculation function
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
DECLARE
  completed_count integer;
  available_count integer;
  total_count integer;
  contract_id_to_update uuid;
  lesson_dates jsonb;
BEGIN
  -- Get the contract ID to update
  contract_id_to_update := COALESCE(NEW.contract_id, OLD.contract_id);

  -- Get total lessons from contract variant
  SELECT cv.total_lessons INTO total_count
  FROM contracts c
  JOIN contract_variants cv ON c.contract_variant_id = cv.id
  WHERE c.id = contract_id_to_update;

  -- Default fallback
  IF total_count IS NULL THEN
    total_count := 10;
  END IF;

  -- Count available lessons (total that can be completed)
  SELECT COUNT(*)
  INTO available_count
  FROM lessons
  WHERE contract_id = contract_id_to_update
    AND is_available = true;

  -- Count completed lessons (those with dates and available)
  SELECT 
    COUNT(*),
    COALESCE(
      jsonb_agg(date::text ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL),
      '[]'::jsonb
    )
  INTO completed_count, lesson_dates
  FROM lessons
  WHERE contract_id = contract_id_to_update
    AND date IS NOT NULL
    AND is_available = true;

  -- Handle null case
  IF lesson_dates IS NULL THEN
    lesson_dates := '[]'::jsonb;
  END IF;

  -- Update contract attendance count and dates
  UPDATE contracts
  SET 
    attendance_count = completed_count || '/' || available_count,
    attendance_dates = lesson_dates,
    updated_at = now()
  WHERE id = contract_id_to_update;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Remove contract_type from students table as it's now managed via contracts
ALTER TABLE students DROP COLUMN IF EXISTS contract_type;

-- Update existing contracts to recalculate attendance with new structure
DO $$
DECLARE
  contract_record RECORD;
  completed_count integer;
  available_count integer;
  lesson_dates jsonb;
BEGIN
  FOR contract_record IN SELECT id FROM contracts WHERE contract_variant_id IS NOT NULL LOOP
    -- Count available lessons
    SELECT COUNT(*)
    INTO available_count
    FROM lessons
    WHERE contract_id = contract_record.id
      AND is_available = true;

    -- Count completed lessons and collect dates as JSONB
    SELECT 
      COUNT(*),
      COALESCE(
        jsonb_agg(date::text ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL),
        '[]'::jsonb
      )
    INTO completed_count, lesson_dates
    FROM lessons
    WHERE contract_id = contract_record.id
      AND date IS NOT NULL
      AND is_available = true;

    -- Handle null case
    IF lesson_dates IS NULL THEN
      lesson_dates := '[]'::jsonb;
    END IF;

    -- Update the contract
    UPDATE contracts
    SET 
      attendance_count = completed_count || '/' || available_count,
      attendance_dates = lesson_dates,
      updated_at = now()
    WHERE id = contract_record.id;
  END LOOP;
END $$;

-- Create helper function to calculate contract pricing with discounts
CREATE OR REPLACE FUNCTION calculate_contract_price(
  variant_id uuid,
  discount_ids uuid[] DEFAULT NULL
)
RETURNS TABLE(
  base_monthly_price numeric,
  base_one_time_price numeric,
  total_discount_percent numeric,
  final_monthly_price numeric,
  final_one_time_price numeric,
  payment_type text
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  variant_record RECORD;
  discount_total numeric := 0;
BEGIN
  -- Get variant pricing
  SELECT cv.monthly_price, cv.one_time_price
  INTO variant_record
  FROM contract_variants cv
  WHERE cv.id = variant_id;

  -- Calculate total discount
  IF discount_ids IS NOT NULL AND array_length(discount_ids, 1) > 0 THEN
    SELECT COALESCE(SUM(cd.discount_percent), 0)
    INTO discount_total
    FROM contract_discounts cd
    WHERE cd.id = ANY(discount_ids) AND cd.is_active = true;
  END IF;

  -- Ensure discount doesn't exceed 100%
  discount_total := LEAST(discount_total, 100);

  -- Return calculated values
  base_monthly_price := variant_record.monthly_price;
  base_one_time_price := variant_record.one_time_price;
  total_discount_percent := discount_total;
  
  IF variant_record.monthly_price IS NOT NULL THEN
    final_monthly_price := variant_record.monthly_price * (1 - discount_total / 100);
    final_one_time_price := NULL;
    payment_type := 'monthly';
  ELSE
    final_monthly_price := NULL;
    final_one_time_price := variant_record.one_time_price * (1 - discount_total / 100);
    payment_type := 'one_time';
  END IF;

  RETURN NEXT;
END;
$$;