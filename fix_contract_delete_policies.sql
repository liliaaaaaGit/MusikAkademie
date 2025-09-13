-- Fix infinite recursion in contract DELETE policies
-- This script removes all conflicting policies and creates a simple, clean one

-- Drop ALL existing DELETE policies for contracts
DROP POLICY IF EXISTS "Only admins can delete contracts" ON contracts;
DROP POLICY IF EXISTS "Teachers can delete contracts of their students" ON contracts;
DROP POLICY IF EXISTS "Admins can manage all contracts" ON contracts;
DROP POLICY IF EXISTS "Admins and teachers can delete contracts" ON contracts;

-- Create a single, simple DELETE policy for admins only
CREATE POLICY "Only admins can delete contracts"
  ON contracts
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Verify the policy was created
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'contracts' AND cmd = 'DELETE';
