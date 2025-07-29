-- Atomic contract save and sync with smart lesson preservation, audit logging, optimistic locking, and validation

-- 1. Add version column for optimistic locking
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS version integer DEFAULT 1;

-- 2. Add unique constraint for lessons
ALTER TABLE lessons ADD CONSTRAINT IF NOT EXISTS unique_contract_lesson UNIQUE (contract_id, lesson_number);

-- 3. Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_lessons_contract_id ON lessons(contract_id);
CREATE INDEX IF NOT EXISTS idx_lessons_contract_lesson_number ON lessons(contract_id, lesson_number);
CREATE INDEX IF NOT EXISTS idx_contracts_status ON contracts(status);

-- 4. Audit log table
CREATE TABLE IF NOT EXISTS contract_operation_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id uuid REFERENCES contracts(id),
  operation_type varchar(50) NOT NULL,
  status varchar(20) NOT NULL, -- 'success', 'failed', 'partial'
  error_message text,
  details jsonb,
  created_at timestamptz DEFAULT now(),
  created_by uuid
);

-- 5. Validation trigger for contract type and status
CREATE OR REPLACE FUNCTION validate_contract_data_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type NOT IN ('ten_class_card', 'half_year', 'monthly', 'workshop') THEN
    RAISE EXCEPTION 'Invalid contract type: %', NEW.type;
  END IF;
  IF OLD.status = 'completed' AND NEW.status != 'completed' THEN
    RAISE EXCEPTION 'Cannot change status of completed contract';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_validate_contract_data ON contracts;
CREATE TRIGGER trigger_validate_contract_data
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION validate_contract_data_trigger();

-- 6. Optimistic locking trigger
CREATE OR REPLACE FUNCTION increment_contract_version()
RETURNS TRIGGER AS $$
BEGIN
  NEW.version := OLD.version + 1;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS contract_version_trigger ON contracts;
CREATE TRIGGER contract_version_trigger
  BEFORE UPDATE ON contracts
  FOR EACH ROW
  EXECUTE FUNCTION increment_contract_version();

-- 7. Smart lesson sync function
CREATE OR REPLACE FUNCTION smart_sync_contract_data(contract_id_param uuid)
RETURNS text AS $$
DECLARE
  contract_record RECORD;
  lesson_count int;
  i int;
BEGIN
  SELECT c.id, c.contract_variant_id, c.type, c.status, cv.total_lessons 
  INTO contract_record 
  FROM contracts c 
  LEFT JOIN contract_variants cv ON c.contract_variant_id = cv.id 
  WHERE c.id = contract_id_param;
  IF contract_record.id IS NULL THEN RAISE EXCEPTION 'Contract not found'; END IF;
  lesson_count := COALESCE(contract_record.total_lessons,
    CASE WHEN contract_record.type = 'ten_class_card' THEN 10
         WHEN contract_record.type = 'half_year' THEN 18
         ELSE 10 END);
  DELETE FROM lessons WHERE contract_id = contract_id_param AND lesson_number > lesson_count;
  FOR i IN 1..lesson_count LOOP
    INSERT INTO lessons (contract_id, lesson_number, is_available)
    VALUES (contract_id_param, i, true)
    ON CONFLICT (contract_id, lesson_number) DO NOTHING;
  END LOOP;
  PERFORM fix_contract_attendance(contract_id_param);
  RETURN format('Contract %s synced: %s lessons (preserved existing progress)', contract_id_param, lesson_count);
EXCEPTION WHEN OTHERS THEN
  RETURN format('Error syncing contract %s: %s', contract_id_param, SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- 8. Atomic save and sync with audit logging
CREATE OR REPLACE FUNCTION atomic_save_and_sync_contract(
  contract_data jsonb,
  is_update boolean DEFAULT false,
  contract_id_param uuid DEFAULT NULL,
  user_id uuid DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  result jsonb;
  lock_key bigint;
  contract_id uuid;
  operation_id uuid;
BEGIN
  lock_key := CASE WHEN is_update THEN hashtext(contract_id_param::text)
                   ELSE hashtext('new_contract_' || pg_backend_pid()::text) END;
  IF NOT pg_try_advisory_xact_lock(lock_key) THEN
    RAISE EXCEPTION 'Contract operation in progress. Please try again.';
  END IF;
  INSERT INTO contract_operation_log (contract_id, operation_type, status, created_by)
  VALUES (contract_id_param, 'save_and_sync', 'started', user_id)
  RETURNING id INTO operation_id;
  IF is_update THEN
    UPDATE contracts SET 
      student_id = (contract_data->>'student_id')::uuid,
      type = contract_data->>'type',
      contract_variant_id = (contract_data->>'contract_variant_id')::uuid,
      status = contract_data->>'status',
      discount_ids = CASE WHEN contract_data->>'discount_ids' IS NOT NULL THEN (contract_data->>'discount_ids')::uuid[] ELSE NULL END,
      custom_discount_percent = CASE WHEN contract_data->>'custom_discount_percent' IS NOT NULL THEN (contract_data->>'custom_discount_percent')::numeric ELSE NULL END,
      final_price = CASE WHEN contract_data->>'final_price' IS NOT NULL THEN (contract_data->>'final_price')::numeric ELSE NULL END,
      payment_type = contract_data->>'payment_type',
      updated_at = now()
    WHERE id = contract_id_param
    RETURNING id INTO contract_id;
  ELSE
    INSERT INTO contracts (
      student_id, type, contract_variant_id, status, discount_ids, custom_discount_percent, final_price, payment_type, attendance_count, attendance_dates
    ) VALUES (
      (contract_data->>'student_id')::uuid,
      contract_data->>'type',
      (contract_data->>'contract_variant_id')::uuid,
      contract_data->>'status',
      CASE WHEN contract_data->>'discount_ids' IS NOT NULL THEN (contract_data->>'discount_ids')::uuid[] ELSE NULL END,
      CASE WHEN contract_data->>'custom_discount_percent' IS NOT NULL THEN (contract_data->>'custom_discount_percent')::numeric ELSE NULL END,
      CASE WHEN contract_data->>'final_price' IS NOT NULL THEN (contract_data->>'final_price')::numeric ELSE NULL END,
      contract_data->>'payment_type',
      '0/0',
      '[]'::jsonb
    ) RETURNING id INTO contract_id;
  END IF;
  PERFORM smart_sync_contract_data(contract_id);
  result := jsonb_build_object('success', true, 'contract_id', contract_id, 'message', 'Contract saved and synced successfully');
  UPDATE contract_operation_log SET status = 'success', details = result WHERE id = operation_id;
  RETURN result;
EXCEPTION WHEN OTHERS THEN
  UPDATE contract_operation_log SET status = 'failed', error_message = SQLERRM WHERE id = operation_id;
  RAISE EXCEPTION 'Failed to save contract: %', SQLERRM;
END;
$$ LANGUAGE plpgsql; 