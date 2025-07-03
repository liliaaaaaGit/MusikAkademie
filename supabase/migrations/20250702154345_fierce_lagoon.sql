/*
  # Fix Lesson Trigger Conflict

  1. Changes
    - Drop existing triggers that might be causing conflicts
    - Drop and recreate the fix_contract_attendance function with consistent return type
    - Recreate the update_contract_attendance function with improved logic
    - Create a new AFTER trigger to avoid "tuple already modified" errors

  2. Key Fixes
    - Use AFTER triggers instead of BEFORE triggers
    - Ensure proper handling of INSERT, UPDATE, and DELETE operations
    - Fix the return type issue with fix_contract_attendance function
    - Grant proper permissions for the fix function
*/

-- First, let's check if there are any problematic triggers
-- and drop them if they exist
DROP TRIGGER IF EXISTS trigger_update_contract_attendance_on_lesson_change ON lessons;
DROP TRIGGER IF EXISTS trigger_update_attendance_count ON lessons;
DROP TRIGGER IF EXISTS trigger_lesson_update_contract ON lessons;

-- Drop the existing fix_contract_attendance function to avoid return type conflict
DROP FUNCTION IF EXISTS fix_contract_attendance(uuid);

-- Recreate the contract attendance trigger with proper timing
-- This should be AFTER UPDATE to avoid conflicts
CREATE OR REPLACE FUNCTION update_contract_attendance()
RETURNS TRIGGER AS $$
BEGIN
  -- For INSERT and UPDATE operations
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    -- Update the contract's attendance based on lessons with dates
    UPDATE contracts 
    SET 
      attendance_count = (
        SELECT 
          COALESCE(COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true), 0) || '/' || 
          COALESCE(COUNT(*) FILTER (WHERE is_available = true), 0)
        FROM lessons 
        WHERE contract_id = NEW.contract_id
      ),
      attendance_dates = (
        SELECT COALESCE(
          jsonb_agg(date ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL AND is_available = true),
          '[]'::jsonb
        )
        FROM lessons 
        WHERE contract_id = NEW.contract_id
      ),
      updated_at = now()
    WHERE id = NEW.contract_id;
    
    RETURN NEW;
  END IF;
  
  -- For DELETE operations
  IF TG_OP = 'DELETE' THEN
    -- Update the contract's attendance based on remaining lessons
    UPDATE contracts 
    SET 
      attendance_count = (
        SELECT 
          COALESCE(COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true), 0) || '/' || 
          COALESCE(COUNT(*) FILTER (WHERE is_available = true), 0)
        FROM lessons 
        WHERE contract_id = OLD.contract_id
      ),
      attendance_dates = (
        SELECT COALESCE(
          jsonb_agg(date ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL AND is_available = true),
          '[]'::jsonb
        )
        FROM lessons 
        WHERE contract_id = OLD.contract_id
      ),
      updated_at = now()
    WHERE id = OLD.contract_id;
    
    RETURN OLD;
  END IF;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger as AFTER to avoid conflicts
CREATE TRIGGER trigger_update_contract_attendance_on_lesson_change
  AFTER INSERT OR UPDATE OR DELETE ON lessons
  FOR EACH ROW
  EXECUTE FUNCTION update_contract_attendance();

-- Create a function to manually fix contract attendance if needed
-- With text return type for consistent error reporting
CREATE OR REPLACE FUNCTION fix_contract_attendance(contract_id_param uuid)
RETURNS text AS $$
DECLARE
  result_message text;
  contract_exists boolean;
BEGIN
  -- Check if contract exists
  SELECT EXISTS(SELECT 1 FROM contracts WHERE id = contract_id_param) INTO contract_exists;
  
  IF NOT contract_exists THEN
    RETURN 'Contract not found: ' || contract_id_param;
  END IF;

  -- Update the contract attendance
  UPDATE contracts 
  SET 
    attendance_count = (
      SELECT 
        COALESCE(COUNT(*) FILTER (WHERE date IS NOT NULL AND is_available = true), 0) || '/' || 
        COALESCE(COUNT(*) FILTER (WHERE is_available = true), 0)
      FROM lessons 
      WHERE contract_id = contract_id_param
    ),
    attendance_dates = (
      SELECT COALESCE(
        jsonb_agg(date ORDER BY lesson_number) FILTER (WHERE date IS NOT NULL AND is_available = true),
        '[]'::jsonb
      )
      FROM lessons 
      WHERE contract_id = contract_id_param
    ),
    updated_at = now()
  WHERE id = contract_id_param;
  
  -- Return success message
  result_message := 'Contract attendance updated successfully for contract: ' || contract_id_param;
  RETURN result_message;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission on the fix function
GRANT EXECUTE ON FUNCTION fix_contract_attendance(uuid) TO authenticated;