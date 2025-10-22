import { supabase } from '@/lib/supabase';

export interface DeleteTeacherResult {
  deleted: {
    contracts: number;
    progress_entries: number;
    trial_lessons: number;
    students_unassigned: number;
    teacher_assignments: number;
    notifications: number;
    teacher: number;
  };
}

export async function deleteTeacherHard(teacherId: string): Promise<DeleteTeacherResult> {
  const { data, error } = await supabase.rpc('admin_delete_teacher', { 
    p_teacher_id: teacherId 
  });

  if (error) {
    // Handle permission or authentication errors
    throw new Error(`Failed to delete teacher: ${error.message}`);
  }

  if (!data) {
    throw new Error('No data returned from delete operation');
  }

  return data as DeleteTeacherResult;
}
