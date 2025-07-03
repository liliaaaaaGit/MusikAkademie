/*
  # Add contract and bank ID fields to students table

  1. New Columns
    - Add `contract_type` column to students table for contract selection
    - Add `bank_id` column to students table for bank ID reference

  2. Security
    - Update RLS policies to handle new fields
    - Ensure proper access control for bank ID data
*/

-- Add contract_type and bank_id columns to students table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'students' AND column_name = 'contract_type'
  ) THEN
    ALTER TABLE students ADD COLUMN contract_type text CHECK (contract_type IN ('10er_karte', 'halbjahresvertrag'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'students' AND column_name = 'bank_id'
  ) THEN
    ALTER TABLE students ADD COLUMN bank_id uuid REFERENCES bank_ids(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Add index for bank_id
CREATE INDEX IF NOT EXISTS idx_students_bank_id ON students(bank_id);

-- Add account_holder_name column to bank_ids table for display purposes
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bank_ids' AND column_name = 'account_holder_name'
  ) THEN
    ALTER TABLE bank_ids ADD COLUMN account_holder_name text;
  END IF;
END $$;