-- Price Versioning Migration (idempotent)
-- - Adds price_version to students and contract_variants
-- - Backfills student cohorts
-- - RPC: get_variants_for_student(p_student_id)
-- - pricing_settings single-row table + trigger to set default price_version on new students
-- - Grants EXECUTE to authenticated

BEGIN;

-- 1) Enum not required; use smallint version numbers

-- 2) Add price_version to contract_variants (default 2)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='contract_variants' AND column_name='price_version'
  ) THEN
    ALTER TABLE public.contract_variants
      ADD COLUMN price_version smallint;
  END IF;
END$$;

-- Ensure default for future inserts (nullable to allow explicit writes)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_attrdef d
    JOIN pg_class c ON c.oid=d.adrelid
    JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=d.adnum
    WHERE c.relname='contract_variants' AND a.attname='price_version'
  ) THEN
    -- no-op; explicit default will be applied by application or via settings
    -- keep as nullable so variants can be versioned manually
    PERFORM 1;
  END IF;
END$$;

-- 3) Add price_version to students
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='price_version'
  ) THEN
    ALTER TABLE public.students
      ADD COLUMN price_version smallint;
  END IF;
END$$;

-- 4) Backfill students cohort: if had any contract created before 2025-09-11 then version=1 else 2
-- This runs safely multiple times
UPDATE public.students s
SET price_version = 1
WHERE price_version IS NULL
  AND EXISTS (
    SELECT 1 FROM public.contracts c
    WHERE c.student_id = s.id
      AND c.created_at < TIMESTAMPTZ '2025-09-11'
  );

UPDATE public.students s
SET price_version = 2
WHERE price_version IS NULL;

-- 5) Settings table to control default version for new students
CREATE TABLE IF NOT EXISTS public.pricing_settings (
  id boolean PRIMARY KEY DEFAULT true,
  current_price_version smallint NOT NULL DEFAULT 2,
  CONSTRAINT one_row CHECK (id)
);

-- Ensure single row exists
INSERT INTO public.pricing_settings (id, current_price_version)
VALUES (true, 2)
ON CONFLICT (id) DO NOTHING;

-- 6) Trigger to set NEW.students.price_version to current_price_version
CREATE OR REPLACE FUNCTION public.set_student_price_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v smallint; BEGIN
  SELECT current_price_version INTO v FROM public.pricing_settings WHERE id = true;
  IF NEW.price_version IS NULL THEN
    NEW.price_version := v;
  END IF;
  RETURN NEW;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname='trg_set_student_price_version'
  ) THEN
    CREATE TRIGGER trg_set_student_price_version
      BEFORE INSERT ON public.students
      FOR EACH ROW
      EXECUTE FUNCTION public.set_student_price_version();
  END IF;
END$$;

-- 7) RPC: get_variants_for_student
CREATE OR REPLACE FUNCTION public.get_variants_for_student(p_student_id uuid)
RETURNS TABLE (
  id uuid,
  contract_category_id uuid,
  name text,
  duration_months integer,
  group_type text,
  session_length_minutes integer,
  total_lessons integer,
  monthly_price numeric(10,2),
  one_time_price numeric(10,2)
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT v.id, v.contract_category_id, v.name, v.duration_months, v.group_type,
         v.session_length_minutes, v.total_lessons, v.monthly_price, v.one_time_price
  FROM public.contract_variants v
  JOIN public.students s ON s.id = p_student_id
  WHERE v.is_active = true
    AND (v.price_version IS NULL OR v.price_version = s.price_version)
  ORDER BY v.name;
$$;

-- 8) Permissions
GRANT EXECUTE ON FUNCTION public.get_variants_for_student(uuid) TO authenticated;

COMMIT;


