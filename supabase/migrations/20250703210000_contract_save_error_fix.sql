/*
  # Contract Save Error Fix

  This migration fixes the "Unknown error" when saving contracts by:

  1. Contract Validation Issues
    - Fix data type mismatches and constraint violations
    - Ensure proper foreign key relationships
    - Add comprehensive validation functions

  2. Error Handling Improvements
    - Enhanced error logging with detailed messages
    - Better constraint violation handling
    - Transactional safety improvements

  3. Data Integrity
    - Fix any existing data inconsistencies
    - Ensure proper default values
    - Validate contract relationships

  4. Permission Issues
    - Verify and fix RLS policies
    - Ensure proper admin permissions
    - Add debugging functions for permission issues
*/

-- =====================================================
-- 1. FIX CONTRACT TABLE CONSTRAINTS AND DATA TYPES
-- =====================================================

-- Ensure proper data types for contract fields
ALTER TABLE contracts 
  ALTER COLUMN attendance_count SET DEFAULT '0/0',
  ALTER COLUMN attendance_dates SET DEFAULT '[]'::jsonb,
  ALTER COLUMN status SET DEFAULT 'active';

-- Fix any existing invalid data
UPDATE contracts 
SET 
  attendance_count = COALESCE(attendance_count, '0/0'),
  attendance_dates = COALESCE(attendance_dates, '[]'::jsonb),
  status = COALESCE(status, 'active')
WHERE 
  attendance_count IS NULL 
  OR attendance_dates IS NULL 
  OR status IS NULL;

-- Ensure contract_variant_id is properly constrained
DO $$
BEGIN
  -- Add foreign key constraint if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'contracts_contract_variant_id_fkey'
  ) THEN
    ALTER TABLE contracts ADD CONSTRAINT contracts_contract_variant_id_fkey 
      FOREIGN KEY (contract_variant_id) REFERENCES contract_variants(id) ON DELETE RESTRICT;
  END IF;
END $$;

-- =====================================================
-- 2. CREATE COMPREHENSIVE CONTRACT VALIDATION FUNCTION
-- =====================================================

-- Function to validate contract data before save
CREATE OR REPLACE FUNCTION validate_contract_data(
  student_id_param uuid,
  contract_variant_id_param uuid,
  type_param text,
  status_param text,
  discount_ids_param uuid[] DEFAULT NULL,
  custom_discount_percent_param numeric DEFAULT NULL
)
RETURNS text AS $$
DECLARE
  student_exists boolean;
  variant_exists boolean;
  discount_exists boolean;
  validation_message text;
BEGIN
  -- Check if student exists
  SELECT EXISTS(SELECT 1 FROM students WHERE id = student_id_param) INTO student_exists;
  IF NOT student_exists THEN
    RETURN 'Student not found';
  END IF;

  -- Check if contract variant exists
  SELECT EXISTS(SELECT 1 FROM contract_variants WHERE id = contract_variant_id_param) INTO variant_exists;
  IF NOT variant_exists THEN
    RETURN 'Contract variant not found';
  END IF;

  -- Validate contract type
  IF type_param NOT IN ('ten_class_card', 'half_year') THEN
    RETURN 'Invalid contract type. Must be ten_class_card or half_year';
  END IF;

  -- Validate status
  IF status_param NOT IN ('active', 'completed', 'cancelled') THEN
    RETURN 'Invalid status. Must be active, completed, or cancelled';
  END IF;

  -- Validate custom discount percentage
  IF custom_discount_percent_param IS NOT NULL THEN
    IF custom_discount_percent_param < 0 OR custom_discount_percent_param > 100 THEN
      RETURN 'Custom discount percentage must be between 0 and 100';
    END IF;
  END IF;

  -- Validate discount IDs if provided
  IF discount_ids_param IS NOT NULL AND array_length(discount_ids_param, 1) > 0 THEN
    SELECT EXISTS(
      SELECT 1 FROM contract_discounts 
      WHERE id = ANY(discount_ids_param) AND is_active = true
    ) INTO discount_exists;
    
    IF NOT discount_exists THEN
      RETURN 'One or more discount IDs are invalid or inactive';
    END IF;
  END IF;

  RETURN 'OK';
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 3. CREATE SAFE CONTRACT SAVE FUNCTION
-- =====================================================

-- Function to safely save contracts with comprehensive error handling
CREATE OR REPLACE FUNCTION safe_save_contract(
  contract_data jsonb,
  is_update boolean DEFAULT false,
  contract_id_param uuid DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  validation_result text;
  new_contract_id uuid;
  result_data jsonb;
  lock_key bigint;
  student_id_val uuid;
  contract_variant_id_val uuid;
  type_val text;
  status_val text;
  discount_ids_val uuid[];
  custom_discount_percent_val numeric;
BEGIN
  -- Extract values from contract_data
  student_id_val := (contract_data->>'student_id')::uuid;
  contract_variant_id_val := (contract_data->>'contract_variant_id')::uuid;
  type_val := contract_data->>'type';
  status_val := contract_data->>'status';
  discount_ids_val := CASE 
    WHEN contract_data->>'discount_ids' IS NOT NULL 
    THEN (contract_data->>'discount_ids')::uuid[] 
    ELSE NULL 
  END;
  custom_discount_percent_val := CASE 
    WHEN contract_data->>'custom_discount_percent' IS NOT NULL 
    THEN (contract_data->>'custom_discount_percent')::numeric 
    ELSE NULL 
  END;

  -- Use advisory lock to prevent concurrent modifications
  lock_key := hashtext(COALESCE(contract_id_param::text, student_id_val::text));
  
  IF NOT pg_try_advisory_xact_lock(lock_key) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Contract is being modified by another operation'
    );
  END IF;

  -- Validate contract data
  validation_result := validate_contract_data(
    student_id_val,
    contract_variant_id_val,
    type_val,
    status_val,
    discount_ids_val,
    custom_discount_percent_val
  );

  IF validation_result != 'OK' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', validation_result
    );
  END IF;

  -- Prepare contract data for save
  IF is_update THEN
    -- Update existing contract
    UPDATE contracts
    SET 
      student_id = student_id_val,
      type = type_val,
      contract_variant_id = contract_variant_id_val,
      status = status_val,
      discount_ids = discount_ids_val,
      custom_discount_percent = custom_discount_percent_val,
      final_price = CASE 
        WHEN contract_data->>'final_price' IS NOT NULL 
        THEN (contract_data->>'final_price')::numeric 
        ELSE NULL 
      END,
      payment_type = contract_data->>'payment_type',
      attendance_count = '0/0', -- Will be recalculated
      attendance_dates = '[]'::jsonb, -- Will be recalculated
      updated_at = now()
    WHERE id = contract_id_param
    RETURNING id INTO new_contract_id;

    IF new_contract_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Contract not found for update'
      );
    END IF;

    -- Force synchronization
    PERFORM sync_contract_data(new_contract_id);

    result_data := jsonb_build_object(
      'success', true,
      'contract_id', new_contract_id,
      'operation', 'updated'
    );
  ELSE
    -- Create new contract
    INSERT INTO contracts (
      student_id,
      type,
      contract_variant_id,
      status,
      discount_ids,
      custom_discount_percent,
      final_price,
      payment_type,
      attendance_count,
      attendance_dates
    )
    VALUES (
      student_id_val,
      type_val,
      contract_variant_id_val,
      status_val,
      discount_ids_val,
      custom_discount_percent_val,
      CASE 
        WHEN contract_data->>'final_price' IS NOT NULL 
        THEN (contract_data->>'final_price')::numeric 
        ELSE NULL 
      END,
      contract_data->>'payment_type',
      '0/0',
      '[]'::jsonb
    )
    RETURNING id INTO new_contract_id;

    -- Update student's contract reference
    UPDATE students
    SET contract_id = new_contract_id
    WHERE id = student_id_val;

    -- Force synchronization
    PERFORM sync_contract_data(new_contract_id);

    result_data := jsonb_build_object(
      'success', true,
      'contract_id', new_contract_id,
      'operation', 'created'
    );
  END IF;

  RETURN result_data;
EXCEPTION WHEN OTHERS THEN
  -- Log the error
  PERFORM log_contract_error(
    CASE WHEN is_update THEN 'contract_update' ELSE 'contract_creation' END,
    contract_id_param,
    SQLERRM
  );

  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'details', SQLSTATE
  );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 4. ENHANCE ERROR LOGGING
-- =====================================================

-- Improve error logging function with more details
CREATE OR REPLACE FUNCTION log_contract_error(
  operation text,
  contract_id_param uuid,
  error_message text,
  error_details text DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  -- Ensure error log table exists
  CREATE TABLE IF NOT EXISTS contract_error_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    operation text NOT NULL,
    contract_id uuid,
    error_message text NOT NULL,
    error_details text,
    stack_trace text,
    created_at timestamptz DEFAULT now()
  );

  INSERT INTO contract_error_logs (
    operation, 
    contract_id, 
    error_message, 
    error_details,
    stack_trace
  )
  VALUES (
    operation, 
    contract_id_param, 
    error_message, 
    error_details,
    COALESCE(current_setting('app.current_query', true), 'No query context')
  );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 5. ADD DEBUGGING FUNCTIONS
-- =====================================================

-- Function to check contract permissions
CREATE OR REPLACE FUNCTION check_contract_permissions(contract_id_param uuid)
RETURNS jsonb AS $$
DECLARE
  user_role text;
  user_id uuid;
  contract_exists boolean;
  can_access boolean;
  result jsonb;
BEGIN
  -- Get current user info
  user_id := auth.uid();
  SELECT role INTO user_role FROM profiles WHERE id = user_id;

  -- Check if contract exists
  SELECT EXISTS(SELECT 1 FROM contracts WHERE id = contract_id_param) INTO contract_exists;

  IF NOT contract_exists THEN
    RETURN jsonb_build_object(
      'can_access', false,
      'reason', 'Contract not found',
      'user_role', user_role,
      'user_id', user_id
    );
  END IF;

  -- Check permissions based on role
  IF user_role = 'admin' THEN
    can_access := true;
  ELSIF user_role = 'teacher' THEN
    -- Teachers can only access contracts for their students
    SELECT EXISTS(
      SELECT 1 
      FROM contracts c
      JOIN students s ON c.student_id = s.id
      JOIN teachers t ON s.teacher_id = t.id
      WHERE c.id = contract_id_param AND t.profile_id = user_id
    ) INTO can_access;
  ELSE
    can_access := false;
  END IF;

  result := jsonb_build_object(
    'can_access', can_access,
    'user_role', user_role,
    'user_id', user_id,
    'contract_exists', contract_exists
  );

  IF NOT can_access THEN
    result := result || jsonb_build_object(
      'reason', 'Insufficient permissions for this contract'
    );
  END IF;

  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to diagnose contract save issues
CREATE OR REPLACE FUNCTION diagnose_contract_save_issue(contract_data jsonb)
RETURNS jsonb AS $$
DECLARE
  student_id_val uuid;
  contract_variant_id_val uuid;
  validation_result text;
  permission_result jsonb;
  result jsonb;
BEGIN
  -- Extract key values
  student_id_val := (contract_data->>'student_id')::uuid;
  contract_variant_id_val := (contract_data->>'contract_variant_id')::uuid;

  -- Check validation
  validation_result := validate_contract_data(
    student_id_val,
    contract_variant_id_val,
    contract_data->>'type',
    contract_data->>'status',
    CASE 
      WHEN contract_data->>'discount_ids' IS NOT NULL 
      THEN (contract_data->>'discount_ids')::uuid[] 
      ELSE NULL 
    END,
    CASE 
      WHEN contract_data->>'custom_discount_percent' IS NOT NULL 
      THEN (contract_data->>'custom_discount_percent')::numeric 
      ELSE NULL 
    END
  );

  -- Check permissions
  permission_result := check_contract_permissions(NULL);

  result := jsonb_build_object(
    'validation_result', validation_result,
    'permission_check', permission_result,
    'student_exists', EXISTS(SELECT 1 FROM students WHERE id = student_id_val),
    'variant_exists', EXISTS(SELECT 1 FROM contract_variants WHERE id = contract_variant_id_val),
    'user_role', permission_result->>'user_role'
  );

  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 6. FIX EXISTING DATA INCONSISTENCIES
-- =====================================================

-- Fix any contracts with invalid foreign keys
DELETE FROM contracts 
WHERE student_id IS NOT NULL 
  AND NOT EXISTS(SELECT 1 FROM students WHERE id = contracts.student_id);

DELETE FROM contracts 
WHERE contract_variant_id IS NOT NULL 
  AND NOT EXISTS(SELECT 1 FROM contract_variants WHERE id = contracts.contract_variant_id);

-- Fix any students with invalid contract references
UPDATE students 
SET contract_id = NULL 
WHERE contract_id IS NOT NULL 
  AND NOT EXISTS(SELECT 1 FROM contracts WHERE id = students.contract_id);

-- =====================================================
-- 7. VERIFY AND FIX RLS POLICIES
-- =====================================================

-- Ensure proper admin permissions
DROP POLICY IF EXISTS "Only admins can create contracts" ON contracts;
CREATE POLICY "Only admins can create contracts"
  ON contracts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Only admins can update contracts" ON contracts;
CREATE POLICY "Only admins can update contracts"
  ON contracts
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Only admins can delete contracts" ON contracts;
CREATE POLICY "Only admins can delete contracts"
  ON contracts
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Ensure teachers can view contracts for their students
DROP POLICY IF EXISTS "Teachers can view contracts of their students" ON contracts;
CREATE POLICY "Teachers can view contracts of their students"
  ON contracts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
    OR
    EXISTS (
      SELECT 1
      FROM students s
      JOIN teachers t ON s.teacher_id = t.id
      JOIN profiles p ON t.profile_id = p.id
      WHERE s.id = contracts.student_id AND p.id = auth.uid()
    )
  );

-- =====================================================
-- 8. GRANT PERMISSIONS
-- =====================================================

-- Grant execute permissions on new functions
GRANT EXECUTE ON FUNCTION validate_contract_data(uuid, uuid, text, text, uuid[], numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION safe_save_contract(jsonb, boolean, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION check_contract_permissions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION diagnose_contract_save_issue(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION log_contract_error(text, uuid, text, text) TO authenticated;

-- =====================================================
-- 9. ADD INDEXES FOR BETTER PERFORMANCE
-- =====================================================

-- Add indexes for better contract operations
CREATE INDEX IF NOT EXISTS idx_contracts_student_variant ON contracts(student_id, contract_variant_id);
CREATE INDEX IF NOT EXISTS idx_contracts_status_type ON contracts(status, type);
CREATE INDEX IF NOT EXISTS idx_contract_error_logs_operation ON contract_error_logs(operation, created_at); 