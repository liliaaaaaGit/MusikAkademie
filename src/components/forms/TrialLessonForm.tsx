import { useState, useMemo } from 'react';
import { supabase, TrialLesson, Teacher } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';

interface TrialLessonFormProps {
  trialLesson?: TrialLesson;
  teachers: Teacher[];
  onSuccess: () => void;
  onCancel: () => void;
}

export function TrialLessonForm({ trialLesson, teachers, onSuccess, onCancel }: TrialLessonFormProps) {
  const { profile } = useAuth();
  
  // Enhanced teacher profile resolution with robust string comparison
  const currentTeacher = useMemo(() => {
    if (!profile?.id) return undefined;
    
    return teachers.find(t => {
      // Ensure both values exist and are strings before comparison
      if (!t.profile_id || !profile.id) return false;
      
      // Trim whitespace and compare
      const teacherProfileId = String(t.profile_id).trim();
      const userProfileId = String(profile.id).trim();
      
      return teacherProfileId === userProfileId;
    });
  }, [profile, teachers]);
  
  const currentTeacherId = currentTeacher?.id;
  const isTeacherProfileResolved = profile?.role === 'teacher' ? !!currentTeacher : true;

  const [formData, setFormData] = useState({
    student_name: trialLesson?.student_name || '',
    instrument: trialLesson?.instrument || '',
    email: trialLesson?.email || '',
    phone: trialLesson?.phone || '',
    status: trialLesson?.status || 'open',
    assigned_teacher_id: trialLesson?.assigned_teacher_id || (profile?.role === 'teacher' && currentTeacher?.id ? currentTeacher.id : '')
  });
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Prepare data for submission
      const submitData = { ...formData };
      
      // For teachers, ensure they can only assign trial lessons to themselves
      if (profile?.role === 'teacher' && currentTeacher?.id) {
        submitData.assigned_teacher_id = currentTeacher.id;
      }
      
      // Convert empty string to null for assigned_teacher_id
      if (submitData.assigned_teacher_id === '') {
        submitData.assigned_teacher_id = null as any;
      }

      if (trialLesson) {
        // Transform data to match current database structure
        const { assigned_teacher_id, ...baseData } = submitData;
        const dbData = {
          ...baseData,
          teacher_id: assigned_teacher_id, // Map legacy field to current field
        };

        // Update existing trial lesson
        const { error } = await supabase
          .from('trial_appointments')
          .update(dbData)
          .eq('id', trialLesson.id);

        if (error) {
          toast.error('Failed to update trial lesson', { description: error.message });
          return;
        }

        toast.success('Trial lesson updated successfully');
      } else {
        // Transform data to match current database structure
        const { assigned_teacher_id, ...baseData } = submitData;
        const dbData = {
          ...baseData,
          teacher_id: assigned_teacher_id, // Map legacy field to current field
          created_by: profile?.id
        };

        // Create new trial lesson
        const { error } = await supabase
          .from('trial_appointments')
          .insert([dbData]);

        if (error) {
          toast.error('Failed to create trial lesson', { description: error.message });
          return;
        }

        toast.success('Trial lesson created successfully');
      }

      onSuccess();
    } catch (error) {
      console.error('Error saving trial lesson:', error);
      toast.error('Failed to save trial lesson');
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (field: string, value: string) => {
    if (field === 'assigned_teacher_id' && value === 'null') {
      setFormData(prev => ({ ...prev, [field]: '' }));
    } else {
      setFormData(prev => ({ ...prev, [field]: value }));
    }
  };

  // Filter teachers based on role
  const availableTeachers = profile?.role === 'teacher' && currentTeacher 
    ? [currentTeacher] 
    : teachers;

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {/* Show error if teacher profile is not resolved */}
      {profile?.role === 'teacher' && !isTeacherProfileResolved && (
        <div className="bg-red-50 border border-red-200 rounded-md p-4">
          <p className="text-sm text-red-600">
            Teacher profile not found. Please contact your administrator.
          </p>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <Label htmlFor="student_name">Student Name *</Label>
          <Input
            id="student_name"
            value={formData.student_name}
            onChange={(e) => handleChange('student_name', e.target.value)}
            required
            placeholder="Enter student name"
          />
        </div>

        <div>
          <Label htmlFor="instrument">Instrument *</Label>
          <Select 
            value={formData.instrument} 
            onValueChange={(value) => handleChange('instrument', value)}
            required
          >
            <SelectTrigger>
              <SelectValue placeholder="Instrument auswählen..." />
            </SelectTrigger>
            <SelectContent className="max-h-64">
              {INSTRUMENTS.map((instrument) => (
                <SelectItem key={instrument} value={instrument}>
                  {instrument}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div>
          <Label htmlFor="email">Email</Label>
          <Input
            id="email"
            type="email"
            value={formData.email}
            onChange={(e) => handleChange('email', e.target.value)}
            placeholder="student@email.com"
          />
        </div>

        <div>
          <Label htmlFor="phone">Phone</Label>
          <Input
            id="phone"
            value={formData.phone}
            onChange={(e) => handleChange('phone', e.target.value)}
            placeholder="+49 123 456 789"
          />
        </div>

        <div>
          <Label htmlFor="status">Status</Label>
          <Select value={formData.status} onValueChange={(value) => handleChange('status', value)}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="open">Open</SelectItem>
              <SelectItem value="assigned">Assigned</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <div>
          <Label htmlFor="assigned_teacher">Assigned Teacher</Label>
          <Select 
            value={formData.assigned_teacher_id} 
            onValueChange={(value) => handleChange('assigned_teacher_id', value)}
            disabled={profile?.role === 'teacher'}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select a teacher" />
            </SelectTrigger>
            <SelectContent>
              {profile?.role === 'admin' && (
                <SelectItem value="null">No teacher assigned</SelectItem>
              )}
              {availableTeachers.map((teacher) => (
                <SelectItem key={teacher.id} value={teacher.id}>
                  {teacher.name} ({teacher.instrument})
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <div className="flex justify-end space-x-2 pt-4">
        <Button 
          type="button" 
          variant="outline" 
          onClick={onCancel}
          className="bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray"
        >
          Cancel
        </Button>
        <Button 
          type="submit" 
          disabled={loading || (profile?.role === 'teacher' && !isTeacherProfileResolved)}
          className="bg-brand-primary hover:bg-brand-primary/90"
        >
          {loading ? 'Saving...' : trialLesson ? 'Update Trial Lesson' : 'Create Trial Lesson'}
        </Button>
      </div>
    </form>
  );
}