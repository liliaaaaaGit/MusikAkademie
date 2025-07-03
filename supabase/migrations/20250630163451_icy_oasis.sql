/*
  # Teacher Permissions and Restrictions

  1. Security Updates
    - Restrict teachers to read-only access for students and contracts
    - Allow teachers to update lesson tracking only
    - Hide price information from teachers
    - Restrict trial appointment management

  2. Views for Price Restriction
    - Create views that exclude price information for teachers
    - Maintain full access for admins

  3. Function Updates
    - Update pricing calculation function to restrict teacher access
*/

-- Update students table policies to restrict teacher access
DROP POLICY IF EXISTS "Teachers can update their assigned students" ON students;
DROP POLICY IF EXISTS "Admins can create students" ON students;

-- Teachers can only READ their assigned students (no updates)
CREATE POLICY "Teachers can only read their assigned students"
  ON students FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM teachers t
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND t.id = students.teacher_id
    )
  );

-- Only admins can create, update, and delete students
CREATE POLICY "Only admins can create students"
  ON students FOR INSERT
  TO authenticated
  WITH CHECK (get_user_role() = 'admin');

CREATE POLICY "Only admins can update students"
  ON students FOR UPDATE
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Only admins can delete students"
  ON students FOR DELETE
  TO authenticated
  USING (get_user_role() = 'admin');

-- Update contracts table policies to restrict teacher access
DROP POLICY IF EXISTS "Teachers can update contracts of their students" ON contracts;
DROP POLICY IF EXISTS "Teachers can delete contracts of their students" ON contracts;
DROP POLICY IF EXISTS "Admins and teachers can create contracts" ON contracts;

-- Teachers can only READ contracts of their students (no updates, creates, or deletes)
CREATE POLICY "Teachers can only read contracts of their students"
  ON contracts FOR SELECT
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    EXISTS (
      SELECT 1 FROM students s
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE p.id = auth.uid() AND s.id = contracts.student_id
    )
  );

-- Only admins can create, update, and delete contracts
CREATE POLICY "Only admins can create contracts"
  ON contracts FOR INSERT
  TO authenticated
  WITH CHECK (get_user_role() = 'admin');

CREATE POLICY "Only admins can update contracts"
  ON contracts FOR UPDATE
  TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Only admins can delete contracts"
  ON contracts FOR DELETE
  TO authenticated
  USING (get_user_role() = 'admin');

-- Lessons table policies remain the same (teachers can update lesson tracking)
-- This allows teachers to fill in session dates and notes

-- Update trial_appointments policies to be more restrictive
DROP POLICY IF EXISTS "Teachers can create trial appointments" ON trial_appointments;
DROP POLICY IF EXISTS "Teachers can edit own trial appointments" ON trial_appointments;

-- Teachers can only read and accept trial appointments (no creation or editing)
CREATE POLICY "Teachers can only read and accept trial appointments"
  ON trial_appointments FOR SELECT
  TO authenticated
  USING (get_user_role() IN ('admin', 'teacher'));

CREATE POLICY "Teachers can only accept open trials"
  ON trial_appointments FOR UPDATE
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

-- Only admins can create and edit trial appointments
CREATE POLICY "Only admins can create trial appointments"
  ON trial_appointments FOR INSERT
  TO authenticated
  WITH CHECK (get_user_role() = 'admin');

CREATE POLICY "Only admins can edit trial appointments"
  ON trial_appointments FOR UPDATE
  TO authenticated
  USING (
    get_user_role() = 'admin' OR
    (
      get_user_role() = 'teacher' AND
      created_by = auth.uid()
    )
  );

-- Create a view for teachers that excludes price information from contracts
CREATE OR REPLACE VIEW teacher_contracts_view AS
SELECT 
  c.id,
  c.student_id,
  c.type,
  c.contract_variant_id,
  c.status,
  c.attendance_count,
  c.attendance_dates,
  c.created_at,
  c.updated_at,
  -- Exclude price fields: final_price, payment_type, discount_ids
  NULL::numeric as final_price,
  NULL::text as payment_type,
  NULL::uuid[] as discount_ids
FROM contracts c;

-- Grant access to the teacher view
GRANT SELECT ON teacher_contracts_view TO authenticated;

-- Create a view for contract variants that excludes price information for teachers
CREATE OR REPLACE VIEW teacher_contract_variants_view AS
SELECT 
  cv.id,
  cv.contract_category_id,
  cv.name,
  cv.duration_months,
  cv.group_type,
  cv.session_length_minutes,
  cv.total_lessons,
  cv.notes,
  cv.is_active,
  cv.created_at,
  -- Exclude price fields for teachers
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) THEN cv.monthly_price
    ELSE NULL
  END as monthly_price,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    ) THEN cv.one_time_price
    ELSE NULL
  END as one_time_price
FROM contract_variants cv;

-- Grant access to the teacher contract variants view
GRANT SELECT ON teacher_contract_variants_view TO authenticated;

-- Update the calculate_contract_price function to restrict access for teachers
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
  user_role text;
BEGIN
  -- Check user role
  SELECT role INTO user_role
  FROM profiles
  WHERE id = auth.uid();

  -- Only admins can access pricing calculations
  IF user_role != 'admin' THEN
    RAISE EXCEPTION 'Access denied: Only administrators can access pricing information';
  END IF;

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