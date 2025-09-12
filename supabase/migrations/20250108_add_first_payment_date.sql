-- Add first_payment_date column to contracts table
BEGIN;

-- Add the new column
ALTER TABLE public.contracts 
ADD COLUMN IF NOT EXISTS first_payment_date timestamptz;

-- Add comment to document the column purpose
COMMENT ON COLUMN public.contracts.first_payment_date IS 'Date when the first monthly payment should be made (for monthly billing cycle contracts)';

COMMIT;
