-- Final Two Teachers Per Student Migration
-- Handles missing profile_id gracefully

-- Create the student_teachers table with correct foreign keys
CREATE TABLE IF NOT EXISTS public.student_teachers (
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
  assigned_by uuid REFERENCES auth.users(id), -- Make this nullable
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
  USING (
    EXISTS (
      SELECT 1 FROM public.teachers t
      JOIN public.profiles p ON t.profile_id = p.id
      WHERE t.id = student_teachers.teacher_id AND p.id = auth.uid()
    )
  );

CREATE POLICY "Teachers can insert their own assignments" ON public.student_teachers
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.teachers t
      JOIN public.profiles p ON t.profile_id = p.id
      WHERE t.id = student_teachers.teacher_id AND p.id = auth.uid()
    )
  );

CREATE POLICY "Teachers can delete their own assignments" ON public.student_teachers
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.teachers t
      JOIN public.profiles p ON t.profile_id = p.id
      WHERE t.id = student_teachers.teacher_id AND p.id = auth.uid()
    )
  );

-- Migrate existing data (handle missing profile_id)
INSERT INTO public.student_teachers (student_id, teacher_id, assigned_by, created_at)
SELECT 
  s.id,
  s.teacher_id,
  t.profile_id, -- This might be null for some teachers
  s.created_at
FROM public.students s
JOIN public.teachers t ON s.teacher_id = t.id
WHERE s.teacher_id IS NOT NULL
ON CONFLICT (student_id, teacher_id) DO NOTHING;
