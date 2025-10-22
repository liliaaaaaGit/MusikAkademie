// lib/students/getStudentForEdit.ts
import { supabase } from '@/lib/supabase';

export type StudentForEdit = {
  id: string;
  name: string | null;
  email: string | null;
  phone: string | null;
  status: string | null;
  teacher_id: string | null;
  contract_id: string | null;
  contract_variant_id: string | null;
  variant?: {
    id: string;
    name: string;
    session_length_minutes: number | null;
    total_lessons: number | null;
    monthly_price: number | null;
    one_time_price: number | null;
    price_version: number;
  } | null;
};

export async function getStudentForEdit(studentId: string): Promise<StudentForEdit> {

  const { data: s, error: sErr } = await supabase
    .from('students')
    .select('id,name,email,phone,status,teacher_id,price_version')
    .eq('id', studentId)
    .single();
  if (sErr || !s) throw new Error(sErr?.message ?? 'Student not found');

  const { data: c } = await supabase
    .from('contracts')
    .select('id, contract_variant_id, status, created_at')
    .eq('student_id', studentId)
    .order('status', { ascending: true })
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  let variant = null as StudentForEdit['variant'];
  if (c?.contract_variant_id) {
    const { data: v } = await supabase
      .from('contract_variants')
      .select('id,name,session_length_minutes,total_lessons,monthly_price,one_time_price,price_version')
      .eq('id', c.contract_variant_id)
      .single();
    variant = v ?? null;
  }

  return {
    id: s.id,
    name: s.name,
    email: s.email,
    phone: s.phone,
    status: s.status,
    teacher_id: s.teacher_id,
    contract_id: c?.id ?? null,
    contract_variant_id: c?.contract_variant_id ?? null,
    variant,
  };
}
