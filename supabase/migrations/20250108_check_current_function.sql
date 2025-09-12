-- Check which version of atomic_save_and_sync_contract is currently active
-- This will help us see if our fixes were applied

-- First, let's see the current function definition
SELECT 
    p.proname as function_name,
    p.prosrc as function_source
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
AND p.proname = 'atomic_save_and_sync_contract';

-- Also check if there are multiple versions
SELECT 
    p.proname as function_name,
    p.oid as function_oid,
    pg_get_function_identity_arguments(p.oid) as arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
AND p.proname LIKE '%atomic_save_and_sync_contract%';
