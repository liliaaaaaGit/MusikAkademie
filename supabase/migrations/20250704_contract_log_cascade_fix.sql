-- Fix contract_operation_log FK to cascade on contract delete
ALTER TABLE contract_operation_log DROP CONSTRAINT IF EXISTS contract_operation_log_contract_id_fkey;
ALTER TABLE contract_operation_log ADD CONSTRAINT contract_operation_log_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE;

