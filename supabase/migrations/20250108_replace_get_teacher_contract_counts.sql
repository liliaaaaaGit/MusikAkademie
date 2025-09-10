BEGIN;

CREATE OR REPLACE FUNCTION public.get_teacher_contract_counts()
RETURNS TABLE(teacher_id uuid, contract_count bigint)
LANGUAGE sql
STABLE
AS $$
  SELECT c.teacher_id, COUNT(*)::bigint
  FROM public.contracts c
  GROUP BY c.teacher_id
$$;

COMMIT;
