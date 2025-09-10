-- Fix notifications.teacher_id foreign key to reference teachers(id)
-- Idempotent and safe to run multiple times

BEGIN;

-- Drop existing FK if present (regardless of current target table)
ALTER TABLE public.notifications
DROP CONSTRAINT IF EXISTS notifications_teacher_id_fkey;

-- Recreate FK to teachers(id)
ALTER TABLE public.notifications
ADD CONSTRAINT notifications_teacher_id_fkey
FOREIGN KEY (teacher_id) REFERENCES public.teachers(id) ON DELETE CASCADE;

-- Helpful index (noop if already exists)
CREATE INDEX IF NOT EXISTS idx_notifications_teacher_id ON public.notifications(teacher_id);

COMMIT; 