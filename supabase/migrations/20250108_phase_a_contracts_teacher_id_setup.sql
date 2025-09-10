-- Phase A: Ensure contracts.teacher_id is properly configured for multi-teacher support
-- Migration: 20250108_phase_a_contracts_teacher_id_setup.sql
-- This migration is idempotent and non-breaking

BEGIN;

-- 1) Ensure column contracts.teacher_id (uuid)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contracts'
      AND column_name = 'teacher_id'
  ) THEN
    ALTER TABLE public.contracts
      ADD COLUMN teacher_id uuid;
  END IF;
END $$;

-- 1b) Ensure FK contracts.teacher_id -> public.teachers(id) with ON DELETE RESTRICT
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.contracts'::regclass
      AND conname = 'contracts_teacher_id_fkey'
  ) THEN
    ALTER TABLE public.contracts
      ADD CONSTRAINT contracts_teacher_id_fkey
      FOREIGN KEY (teacher_id)
      REFERENCES public.teachers(id)
      ON DELETE RESTRICT;
  END IF;
END $$;

-- 2) Backfill (no overwrite)
UPDATE public.contracts c
SET teacher_id = s.teacher_id
FROM public.students s
WHERE c.student_id = s.id
  AND c.teacher_id IS NULL
  AND s.teacher_id IS NOT NULL;

-- 3) Index
CREATE INDEX IF NOT EXISTS idx_contracts_teacher_id
  ON public.contracts(teacher_id);

-- 4) Deprecation comment (guarded)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'students'
      AND column_name = 'teacher_id'
  ) THEN
    COMMENT ON COLUMN public.students.teacher_id
      IS 'DEPRECATED: will be removed in Phase B. Use contracts.teacher_id.';
  END IF;
END $$;

COMMIT;
