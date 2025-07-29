-- RLS: Only admins and teachers can delete contracts for their students
DROP POLICY IF EXISTS "Only admins can delete contracts" ON contracts;
CREATE POLICY "Only admins can delete contracts" ON contracts FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));
DROP POLICY IF EXISTS "Teachers can delete contracts of their students" ON contracts;
CREATE POLICY "Teachers can delete contracts of their students" ON contracts FOR DELETE TO authenticated USING ((get_user_role() = 'admin') OR ((get_user_role() = 'teacher') AND (EXISTS (SELECT 1 FROM students s JOIN teachers t ON s.teacher_id = t.id JOIN profiles p ON t.profile_id = p.id WHERE p.id = auth.uid() AND s.id = contracts.student_id))));

