/*
  # Create RPC function for teacher contract counts

  1. New Function
    - `get_teacher_contract_counts()` - Returns contract counts per teacher using proper JOIN and COUNT
    
  2. Performance
    - Uses server-side aggregation for better performance
    - Proper JOIN between contracts, students, and teachers tables
    - Returns structured data with teacher_id and contract_count
*/

-- Create RPC function to get teacher contract counts
CREATE OR REPLACE FUNCTION get_teacher_contract_counts()
RETURNS TABLE(teacher_id uuid, contract_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT 
    s.teacher_id,
    COUNT(c.id) as contract_count
  FROM teachers t
  LEFT JOIN students s ON s.teacher_id = t.id
  LEFT JOIN contracts c ON c.student_id = s.id
  WHERE t.id IS NOT NULL
  GROUP BY s.teacher_id, t.id
  HAVING s.teacher_id IS NOT NULL
  ORDER BY contract_count DESC;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_teacher_contract_counts() TO authenticated;