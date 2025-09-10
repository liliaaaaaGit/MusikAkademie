-- Fix parsing of discount_ids from JSON into uuid[] to avoid malformed array literal errors

BEGIN;

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
  status_update text;
  status_insert text;
  parsed_discount_ids uuid[];
BEGIN
  lock_key := CASE WHEN is_update THEN hashtext(contract_id_param::text)
                   ELSE hashtext('new_contract_' || pg_backend_pid()::text) END;
  IF NOT pg_try_advisory_xact_lock(lock_key) THEN
    RAISE EXCEPTION 'Contract operation in progress. Please try again.';
  END IF;

  -- Log start
  INSERT INTO public.contract_operation_log (contract_id, operation_type, status, created_by)
  VALUES (contract_id_param, 'save_and_sync', 'started', COALESCE(user_id, auth.uid()));

  -- Parse optional fields
  status_update := COALESCE(contract_data->>'status', NULL);
  status_insert := COALESCE(contract_data->>'status', 'active');

  -- Parse discount_ids JSON array -> uuid[]
  parsed_discount_ids := NULL;
  IF (contract_data ? 'discount_ids') AND jsonb_typeof(contract_data->'discount_ids') = 'array' THEN
    SELECT array_agg(value::uuid)
    INTO parsed_discount_ids
    FROM jsonb_array_elements_text(contract_data->'discount_ids');
  END IF;

  IF is_update THEN
    UPDATE public.contracts SET 
      student_id = (contract_data->>'student_id')::uuid,
      type = contract_data->>'type',
      contract_variant_id = (contract_data->>'contract_variant_id')::uuid,
      status = COALESCE(status_update, status),
      discount_ids = CASE WHEN array_length(parsed_discount_ids, 1) IS NOT NULL THEN parsed_discount_ids ELSE NULL END,
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
      status_insert,
      CASE WHEN array_length(parsed_discount_ids, 1) IS NOT NULL THEN parsed_discount_ids ELSE NULL END,
      CASE WHEN contract_data->>'custom_discount_percent' IS NOT NULL THEN (contract_data->>'custom_discount_percent')::numeric ELSE NULL END,
      CASE WHEN contract_data->>'final_price' IS NOT NULL THEN (contract_data->>'final_price')::numeric ELSE NULL END,
      contract_data->>'payment_type',
      '0/0',
      '[]'::jsonb
    ) RETURNING id INTO contract_id;
  END IF;

  PERFORM public.smart_sync_contract_data(contract_id);

  result := jsonb_build_object('success', true, 'contract_id', contract_id, 'message', 'Contract saved and synced successfully');

  INSERT INTO public.contract_operation_log (contract_id, operation_type, status, details, created_by)
  VALUES (contract_id, 'save_and_sync', 'success', result, COALESCE(user_id, auth.uid()));

  RETURN result;
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public.contract_operation_log (contract_id, operation_type, status, error_message, created_by)
  VALUES (COALESCE(contract_id_param, contract_id), 'save_and_sync', 'failed', SQLERRM, COALESCE(user_id, auth.uid()));
  RAISE EXCEPTION 'Failed to save contract: %', SQLERRM;
END;
$$;

COMMIT; 