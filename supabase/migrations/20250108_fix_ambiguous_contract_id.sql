-- Fix atomic_save_and_sync_contract function to resolve ambiguous contract_id column reference
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
    operation_id uuid;
    discount_array uuid[];
BEGIN
    lock_key := CASE WHEN is_update THEN hashtext(contract_id_param::text) ELSE hashtext('new_contract_' || pg_backend_pid()::text) END;

    IF NOT pg_try_advisory_xact_lock(lock_key) THEN
        RAISE EXCEPTION 'Contract operation in progress. Please try again.';
    END IF;

    INSERT INTO public.contract_operation_log (contract_id, operation_type, status, created_by)
    VALUES (contract_id_param, 'save_and_sync', 'started', COALESCE(user_id, auth.uid()))
    RETURNING id INTO operation_id;

    -- Handle discount_ids properly - check if it's actually a JSON array before extracting elements
    IF contract_data ? 'discount_ids' 
       AND contract_data->'discount_ids' IS NOT NULL 
       AND jsonb_typeof(contract_data->'discount_ids') = 'array' THEN
        SELECT array_agg(elem::text::uuid) INTO discount_array
        FROM jsonb_array_elements_text(contract_data->'discount_ids') AS elem;
    ELSE
        discount_array := NULL;
    END IF;

    IF is_update THEN
        UPDATE public.contracts
        SET
            student_id = (contract_data->>'student_id')::uuid,
            teacher_id = (contract_data->>'teacher_id')::uuid,
            type = contract_data->>'type',
            contract_variant_id = (contract_data->>'contract_variant_id')::uuid,
            status = COALESCE(contract_data->>'status', 'active'),
            discount_ids = discount_array,
            custom_discount_percent = CASE WHEN contract_data->>'custom_discount_percent' IS NOT NULL THEN (contract_data->>'custom_discount_percent')::numeric ELSE NULL END,
            payment_type = contract_data->>'payment_type',
            billing_cycle = CASE WHEN contract_data->>'billing_cycle' IS NOT NULL THEN (contract_data->>'billing_cycle')::billing_cycle ELSE NULL END,
            paid_at = CASE WHEN contract_data->>'paid_at' IS NOT NULL THEN (contract_data->>'paid_at')::timestamptz ELSE NULL END,
            paid_through = CASE WHEN contract_data->>'paid_through' IS NOT NULL THEN (contract_data->>'paid_through')::timestamptz ELSE NULL END,
            term_start = CASE WHEN contract_data->>'term_start' IS NOT NULL THEN (contract_data->>'term_start')::timestamptz ELSE NULL END,
            term_end = CASE WHEN contract_data->>'term_end' IS NOT NULL THEN (contract_data->>'term_end')::timestamptz ELSE NULL END,
            term_label = contract_data->>'term_label',
            cancelled_at = CASE WHEN contract_data->>'cancelled_at' IS NOT NULL THEN (contract_data->>'cancelled_at')::timestamptz ELSE NULL END,
            updated_at = now()
        WHERE id = contract_id_param
        RETURNING id INTO contract_id;
    ELSE
        INSERT INTO public.contracts (
            student_id,
            teacher_id,
            type,
            contract_variant_id,
            status,
            discount_ids,
            custom_discount_percent,
            payment_type,
            billing_cycle,
            paid_at,
            paid_through,
            term_start,
            term_end,
            term_label,
            cancelled_at,
            attendance_count,
            attendance_dates
        ) VALUES (
            (contract_data->>'student_id')::uuid,
            (contract_data->>'teacher_id')::uuid,
            contract_data->>'type',
            (contract_data->>'contract_variant_id')::uuid,
            COALESCE(contract_data->>'status', 'active'),
            discount_array,
            CASE WHEN contract_data->>'custom_discount_percent' IS NOT NULL THEN (contract_data->>'custom_discount_percent')::numeric ELSE NULL END,
            contract_data->>'payment_type',
            CASE WHEN contract_data->>'billing_cycle' IS NOT NULL THEN (contract_data->>'billing_cycle')::billing_cycle ELSE NULL END,
            CASE WHEN contract_data->>'paid_at' IS NOT NULL THEN (contract_data->>'paid_at')::timestamptz ELSE NULL END,
            CASE WHEN contract_data->>'paid_through' IS NOT NULL THEN (contract_data->>'paid_through')::timestamptz ELSE NULL END,
            CASE WHEN contract_data->>'term_start' IS NOT NULL THEN (contract_data->>'term_start')::timestamptz ELSE NULL END,
            CASE WHEN contract_data->>'term_end' IS NOT NULL THEN (contract_data->>'term_end')::timestamptz ELSE NULL END,
            contract_data->>'term_label',
            CASE WHEN contract_data->>'cancelled_at' IS NOT NULL THEN (contract_data->>'cancelled_at')::timestamptz ELSE NULL END,
            COALESCE((contract_data->>'attendance_count')::integer, 0),
            COALESCE((contract_data->'attendance_dates')::jsonb, '[]'::jsonb)
        )
        RETURNING id INTO contract_id;
    END IF;

    -- FIXED: Update contract_operation_log status with explicit table reference
    UPDATE public.contract_operation_log
    SET status = 'completed', contract_id = contract_id
    WHERE contract_operation_log.id = operation_id;

    -- Return the saved contract data
    SELECT to_jsonb(c) INTO result
    FROM public.contracts c
    WHERE c.id = contract_id;

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        -- FIXED: Log the error in contract_operation_log with explicit table reference
        UPDATE public.contract_operation_log
        SET status = 'failed', error_message = SQLERRM
        WHERE contract_operation_log.id = operation_id;
        RAISE EXCEPTION 'Failed to save contract: %', SQLERRM;
END;
$$;

COMMIT;
