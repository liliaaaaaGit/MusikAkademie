-- Ensure defaults and RLS for contract_operation_log, and adjust logging to avoid UPDATEs

BEGIN;

-- Enable RLS on the log table (safe if already enabled)
ALTER TABLE public.contract_operation_log ENABLE ROW LEVEL SECURITY;

-- Helpful defaults so client/functions don’t need to pass these explicitly
ALTER TABLE public.contract_operation_log
  ALTER COLUMN created_at SET DEFAULT now();

-- created_by should default to the current authenticated user
ALTER TABLE public.contract_operation_log
  ALTER COLUMN created_by SET DEFAULT auth.uid();

-- Make sure created_by is not null so policies can rely on it
ALTER TABLE public.contract_operation_log
  ALTER COLUMN created_by SET NOT NULL;

-- Minimal insert policy: only authenticated users with a valid role can insert,
-- and only for themselves (created_by must equal auth.uid())
CREATE POLICY col_insert_self_actor
  ON public.contract_operation_log
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.get_user_role() IN ('admin','teacher')
    AND created_by = auth.uid()
  );

-- Admins can read all log rows (teachers’ visibility can be added later if needed)
CREATE POLICY col_select_admin
  ON public.contract_operation_log
  FOR SELECT
  TO authenticated
  USING (public.get_user_role() = 'admin');

-- Keep default deny for UPDATE/DELETE by not creating policies for them

-- Update the atomic_save_and_sync_contract function to avoid updating the log row.
-- We write separate rows for 'started', 'success', and 'failed'.
CREATE OR REPLACE FUNCTION public.atomic_save_and_sync_contract(
  contract_data jsonb,
  is_update boolean DEFAULT false,
  contract_id_param uuid DEFAULT NULL,
  user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  result jsonb;
  lock_key bigint;
  contract_id uuid;
BEGIN
  lock_key := CASE WHEN is_update THEN hashtext(contract_id_param::text)
                   ELSE hashtext('new_contract_' || pg_backend_pid()::text) END;
  IF NOT pg_try_advisory_xact_lock(lock_key) THEN
    RAISE EXCEPTION 'Contract operation in progress. Please try again.';
  END IF;

  -- Log start (created_by defaults to auth.uid() if user_id is NULL)
  INSERT INTO public.contract_operation_log (contract_id, operation_type, status, created_by)
  VALUES (contract_id_param, 'save_and_sync', 'started', COALESCE(user_id, auth.uid()));

  IF is_update THEN
    UPDATE public.contracts SET 
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
    INSERT INTO public.contracts (
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

  PERFORM public.smart_sync_contract_data(contract_id);

  result := jsonb_build_object('success', true, 'contract_id', contract_id, 'message', 'Contract saved and synced successfully');

  -- Log success as a separate row
  INSERT INTO public.contract_operation_log (contract_id, operation_type, status, details, created_by)
  VALUES (contract_id, 'save_and_sync', 'success', result, COALESCE(user_id, auth.uid()));

  RETURN result;
EXCEPTION WHEN OTHERS THEN
  -- Log failure as a separate row
  INSERT INTO public.contract_operation_log (contract_id, operation_type, status, error_message, created_by)
  VALUES (COALESCE(contract_id_param, contract_id), 'save_and_sync', 'failed', SQLERRM, COALESCE(user_id, auth.uid()));
  RAISE EXCEPTION 'Failed to save contract: %', SQLERRM;
END;
$$;

COMMIT; 