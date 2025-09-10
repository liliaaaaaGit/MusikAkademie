-- Simple Two Teachers Per Student Migration
-- Just the essential parts without complex syntax

-- Create the student_teachers table
CREATE TABLE IF NOT EXISTS public.student_teachers (
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  assigned_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (student_id, teacher_id)
);

-- Enable RLS
ALTER TABLE public.student_teachers ENABLE ROW LEVEL SECURITY;

-- Simple RLS policies
CREATE POLICY "Admins can manage all student_teachers" ON public.student_teachers
  FOR ALL TO authenticated
  USING (get_user_role() = 'admin');

CREATE POLICY "Teachers can read their own assignments" ON public.student_teachers
  FOR SELECT TO authenticated
  USING (teacher_id = auth.uid());

CREATE POLICY "Teachers can insert their own assignments" ON public.student_teachers
  FOR INSERT TO authenticated
  WITH CHECK (teacher_id = auth.uid());

CREATE POLICY "Teachers can delete their own assignments" ON public.student_teachers
  FOR DELETE TO authenticated
  USING (teacher_id = auth.uid());

-- Migrate existing data
INSERT INTO public.student_teachers (student_id, teacher_id, assigned_by, created_at)
SELECT 
  s.id,
  s.teacher_id,
  s.teacher_id,
  s.created_at
FROM public.students s
WHERE s.teacher_id IS NOT NULL
ON CONFLICT (student_id, teacher_id) DO NOTHING;
