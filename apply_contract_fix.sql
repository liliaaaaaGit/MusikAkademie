-- Contract Save Error Fix - Apply this in Supabase SQL Editor
-- This fixes the "Unknown error" when saving contracts

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
  contract_id_param uuid DEFAULT NULL,
  is_update boolean DEFAULT false
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
  final_price_val numeric;
  payment_type_val text;
BEGIN
  -- Extract values from contract_data
  student_id_val := (contract_data->>'student_id')::uuid;
  contract_variant_id_val := (contract_data->>'contract_variant_id')::uuid;
  type_val := contract_data->>'type';
  status_val := COALESCE(contract_data->>'status', 'active');
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
  final_price_val := CASE 
    WHEN contract_data->>'final_price' IS NOT NULL 
    THEN (contract_data->>'final_price')::numeric 
    ELSE NULL 
  END;
  payment_type_val := contract_data->>'payment_type';

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
  IF is_update AND contract_id_param IS NOT NULL THEN
    -- Update existing contract
    UPDATE contracts
    SET 
      student_id = student_id_val,
      type = type_val,
      contract_variant_id = contract_variant_id_val,
      status = status_val,
      discount_ids = discount_ids_val,
      custom_discount_percent = custom_discount_percent_val,
      final_price = final_price_val,
      payment_type = payment_type_val,
      updated_at = NOW()
    WHERE id = contract_id_param
    RETURNING id INTO new_contract_id;

    IF new_contract_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Contract not found for update'
      );
    END IF;
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
    ) VALUES (
      student_id_val,
      type_val,
      contract_variant_id_val,
      status_val,
      discount_ids_val,
      custom_discount_percent_val,
      final_price_val,
      payment_type_val,
      '0/0',
      '[]'::jsonb
    )
    RETURNING id INTO new_contract_id;
  END IF;

  -- Return success with contract data
  SELECT jsonb_build_object(
    'success', true,
    'contract_id', new_contract_id,
    'message', CASE WHEN is_update THEN 'Contract updated successfully' ELSE 'Contract created successfully' END
  ) INTO result_data;

  RETURN result_data;

EXCEPTION
  WHEN OTHERS THEN
    -- Log the error for debugging
    INSERT INTO contract_error_logs (operation, contract_id, error_message, error_details)
    VALUES (
      CASE WHEN is_update THEN 'update' ELSE 'create' END,
      contract_id_param,
      SQLERRM,
      SQLSTATE
    );

    RETURN jsonb_build_object(
      'success', false,
      'error', 'Database error: ' || SQLERRM
    );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 4. CREATE ERROR LOGGING TABLE
-- =====================================================

-- Create table for logging contract errors
CREATE TABLE IF NOT EXISTS contract_error_logs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  operation text NOT NULL,
  contract_id uuid,
  error_message text NOT NULL,
  error_details text,
  created_at timestamp with time zone DEFAULT NOW()
);

-- =====================================================
-- 5. CREATE INDEXES FOR BETTER PERFORMANCE
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_contracts_student_variant ON contracts(student_id, contract_variant_id);
CREATE INDEX IF NOT EXISTS idx_contracts_status_type ON contracts(status, type);
CREATE INDEX IF NOT EXISTS idx_contract_error_logs_operation ON contract_error_logs(operation, created_at);

-- =====================================================
-- 6. VERIFY THE FUNCTION WAS CREATED
-- =====================================================

-- Test that the function exists
SELECT 
  routine_name, 
  routine_type 
FROM information_schema.routines 
WHERE routine_name = 'safe_save_contract' 
  AND routine_schema = 'public';

-- Success message
SELECT 'Contract save fix applied successfully!' as status; 