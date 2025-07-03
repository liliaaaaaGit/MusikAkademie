/*
  # Add Custom Discount Percent to Contracts Table

  1. Changes
    - Add `custom_discount_percent` column to contracts table
    - This allows storing custom discount percentages separate from predefined discounts
    - Ensures custom discounts are preserved and can be displayed in PDFs

  2. Data Type
    - numeric(5,2) to store percentages with 2 decimal places
    - Allows values from 0 to 100 with precision
    - NULL by default (no custom discount applied)

  3. Constraints
    - CHECK constraint ensures values are between 0 and 100
    - Maintains data integrity for percentage values
*/

-- Add custom_discount_percent column to contracts table
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS custom_discount_percent numeric(5,2) DEFAULT NULL;

-- Add constraint to ensure values are between 0 and 100
ALTER TABLE contracts ADD CONSTRAINT contracts_custom_discount_percent_check 
  CHECK (custom_discount_percent IS NULL OR (custom_discount_percent >= 0 AND custom_discount_percent <= 100));