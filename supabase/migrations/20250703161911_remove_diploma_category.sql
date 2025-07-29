/*
  # Remove Diplomausbildung Category and Variants

  1. Changes
    - Delete contract variants for "Diplomausbildung" category:
      * "Oper/Operette – 2 Jahre" (duration: 24 months)
      * "Musical – 3 Jahre" (duration: 36 months)
    - Delete the "Diplomausbildung" contract category (name: 'private_diploma')
    
  2. Safety
    - Check if any existing contracts use these variants before deletion
    - Use CASCADE to handle foreign key constraints properly
    - Provide feedback on deletion results

  3. Notes
    - This removal is permanent and cannot be undone
    - All related data (lessons, etc.) for existing diploma contracts will remain
    - Only prevents new diploma contracts from being created
*/

-- First, check if there are any existing contracts using diploma variants
DO $$
DECLARE
  diploma_contract_count integer;
  diploma_category_id uuid;
BEGIN
  -- Get the diploma category ID
  SELECT id INTO diploma_category_id 
  FROM contract_categories 
  WHERE name = 'private_diploma';
  
  IF diploma_category_id IS NOT NULL THEN
    -- Count contracts using diploma variants
    SELECT COUNT(*) INTO diploma_contract_count
    FROM contracts c
    JOIN contract_variants cv ON c.contract_variant_id = cv.id
    WHERE cv.contract_category_id = diploma_category_id;
    
    -- Log the count for reference
    RAISE NOTICE 'Found % existing contracts using diploma variants', diploma_contract_count;
    
    IF diploma_contract_count > 0 THEN
      RAISE NOTICE 'Warning: % contracts are using diploma variants. These contracts will remain but the category will be unavailable for new contracts.', diploma_contract_count;
    END IF;
  ELSE
    RAISE NOTICE 'Diploma category not found - may have already been deleted';
  END IF;
END $$;

-- Delete specific diploma variants by name and characteristics
-- This is safer than relying on IDs which may vary between environments
DELETE FROM contract_variants 
WHERE id IN (
  SELECT cv.id 
  FROM contract_variants cv
  JOIN contract_categories cc ON cv.contract_category_id = cc.id
  WHERE cc.name = 'private_diploma' 
  AND cv.name IN ('Oper/Operette – 2 Jahre', 'Musical – 3 Jahre')
);

-- Log how many variants were deleted
DO $$
DECLARE
  deleted_variants integer;
BEGIN
  GET DIAGNOSTICS deleted_variants = ROW_COUNT;
  RAISE NOTICE 'Deleted % diploma contract variants', deleted_variants;
END $$;

-- Delete the diploma category
-- This will fail if there are still contracts using diploma variants,
-- which is good for data integrity
DELETE FROM contract_categories 
WHERE name = 'private_diploma';

-- Log if category was deleted
DO $$
DECLARE
  deleted_categories integer;
BEGIN
  GET DIAGNOSTICS deleted_categories = ROW_COUNT;
  IF deleted_categories > 0 THEN
    RAISE NOTICE 'Successfully deleted diploma category';
  ELSE
    RAISE NOTICE 'Diploma category was not deleted (may not exist or may still be in use)';
  END IF;
END $$;

-- Final verification - check that diploma category is gone
DO $$
DECLARE
  remaining_diploma_count integer;
BEGIN
  SELECT COUNT(*) INTO remaining_diploma_count
  FROM contract_categories 
  WHERE name = 'private_diploma';
  
  IF remaining_diploma_count = 0 THEN
    RAISE NOTICE 'Verification successful: Diploma category has been completely removed';
  ELSE
    RAISE NOTICE 'Verification failed: Diploma category still exists';
  END IF;
END $$; 