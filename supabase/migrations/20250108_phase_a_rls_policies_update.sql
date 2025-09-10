BEGIN;

-- Helper: admin-Check via profiles.is_admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((
    SELECT p.is_admin
    FROM public.profiles p
    WHERE p.id = auth.uid()
  ), false)
$$;

-- contracts: read = admin OR contract's teacher; writes = admin only
CREATE OR REPLACE POLICY contracts_select_admin_or_owner
  ON public.contracts
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.teachers t
      JOIN public.profiles p ON p.id = t.profile_id
      WHERE t.id = public.contracts.teacher_id
        AND p.id = auth.uid()
    )
  );

CREATE OR REPLACE POLICY contracts_insert_admin_only
  ON public.contracts
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin());

CREATE OR REPLACE POLICY contracts_update_admin_only
  ON public.contracts
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE POLICY contracts_delete_admin_only
  ON public.contracts
  FOR DELETE
  TO authenticated
  USING (public.is_admin());

-- lessons: read/update allowed if user could read the parent contract OR is admin
CREATE OR REPLACE POLICY lessons_select_admin_or_contract_teacher
  ON public.lessons
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.contracts c
      JOIN public.teachers t ON t.id = c.teacher_id
      JOIN public.profiles p ON p.id = t.profile_id
      WHERE c.id = public.lessons.contract_id
        AND p.id = auth.uid()
    )
  );

CREATE OR REPLACE POLICY lessons_update_admin_or_contract_teacher
  ON public.lessons
  FOR UPDATE
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.contracts c
      JOIN public.teachers t ON t.id = c.teacher_id
      JOIN public.profiles p ON p.id = t.profile_id
      WHERE c.id = public.lessons.contract_id
        AND p.id = auth.uid()
    )
  )
  WITH CHECK (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.contracts c
      JOIN public.teachers t ON t.id = c.teacher_id
      JOIN public.profiles p ON p.id = t.profile_id
      WHERE c.id = public.lessons.contract_id
        AND p.id = auth.uid()
    )
  );

COMMIT;

-- Quick test (commented):
-- SET LOCAL "request.jwt.claims" = '{"sub":"<teacher_profile_uuid>","role":"user"}'; SELECT COUNT(*) FROM public.contracts;
-- SET LOCAL "request.jwt.claims" = '{"sub":"<admin_profile_uuid>","role":"user"}';   SELECT COUNT(*) FROM public.contracts; RESET ALL;
