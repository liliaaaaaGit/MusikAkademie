-- Phase B: enforce NOT NULL on contracts.teacher_id and drop students.teacher_id
BEGIN;

-- 0) Safety: abort if any contract has NULL teacher_id
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.contracts WHERE teacher_id IS NULL) THEN
    RAISE EXCEPTION 'Abort Phase B: contracts.teacher_id still has NULL values';
  END IF;
END $$;

-- 1) Enforce NOT NULL if not already set
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='contracts'
      AND column_name='teacher_id'
      AND is_nullable='YES'
  ) THEN
    ALTER TABLE public.contracts
      ALTER COLUMN teacher_id SET NOT NULL;
  END IF;
END $$;

-- 2) Drop students.teacher_id if it exists (legacy, deprecated)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='students'
      AND column_name='teacher_id'
  ) THEN
    ALTER TABLE public.students DROP COLUMN teacher_id;
  END IF;
END $$;

COMMIT;

-- ===== Verification (run manually) =====
-- a) \d public.contracts  -- teacher_id should be NOT NULL
-- b) SELECT column_name FROM information_schema.columns 
--    WHERE table_schema='public' AND table_name='students';
--    -- teacher_id should NOT be present
-- c) Sanity: SELECT COUNT(*) FROM public.contracts;
