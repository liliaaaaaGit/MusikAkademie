import { useState, useMemo } from 'react';
import { supabase, TrialAppointment, Teacher } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';

interface TrialAppointmentFormProps {
  trialAppointment?: TrialAppointment;
  teachers: Teacher[];
  onSuccess: () => void;
  onCancel: () => void;
}

export function TrialAppointmentForm({ trialAppointment, teachers, onSuccess, onCancel }: TrialAppointmentFormProps) {
  const { profile, isAdmin } = useAuth();
  
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

  // Custom instrument state
  const [showCustomInstrumentInput, setShowCustomInstrumentInput] = useState(false);
  const [customInstrumentValue, setCustomInstrumentValue] = useState('');

  const [formData, setFormData] = useState({
    student_name: trialAppointment?.student_name || '',
    instrument: trialAppointment?.instrument || '',
    email: trialAppointment?.email || '',
    phone: trialAppointment?.phone || '',
    status: trialAppointment?.status || 'open',
    teacher_id: trialAppointment?.teacher_id || ''
  });
  const [loading, setLoading] = useState(false);

  // Initialize custom instrument state based on existing data
  useState(() => {
    if (trialAppointment?.instrument && !INSTRUMENTS.includes(trialAppointment.instrument as any)) {
      setShowCustomInstrumentInput(true);
      setCustomInstrumentValue(trialAppointment.instrument);
      setFormData(prev => ({ ...prev, instrument: 'andere' }));
    }
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Validate required fields
      if (!formData.student_name.trim()) {
        toast.error('Schülername ist erforderlich');
        setLoading(false);
        return;
      }

      if (!formData.instrument.trim()) {
        toast.error('Instrument ist erforderlich');
        setLoading(false);
        return;
      }

      // Validate custom instrument if "andere" is selected
      if (showCustomInstrumentInput && !customInstrumentValue.trim()) {
        toast.error('Bitte geben Sie ein Instrument ein');
        setLoading(false);
        return;
      }

      // Determine the final instrument value
      let finalInstrument = formData.instrument;
      if (showCustomInstrumentInput && customInstrumentValue.trim()) {
        finalInstrument = customInstrumentValue.trim();
      }

      // Prepare data for submission
      const submitData = { 
        ...formData,
        instrument: finalInstrument
      };
      
      // Convert empty string to null for teacher_id
      if (submitData.teacher_id === '') {
        submitData.teacher_id = null as any;
      }

      // Set status based on teacher assignment
      if (submitData.teacher_id) {
        submitData.status = 'assigned';
      } else {
        submitData.status = 'open';
      }

      // Remove empty strings and convert to null for optional fields
      Object.keys(submitData).forEach(key => {
        if (submitData[key as keyof typeof submitData] === '') {
          (submitData as any)[key] = null;
        }
      });

      if (trialAppointment) {
        // Update existing trial appointment
        const { error } = await supabase
          .from('trial_appointments')
          .update(submitData)
          .eq('id', trialAppointment.id);

        if (error) {
          toast.error('Fehler beim Aktualisieren der Probestunde', { description: error.message });
          return;
        }

        toast.success('Probestunde erfolgreich aktualisiert');
      } else {
        // Create new trial appointment
        const { error } = await supabase
          .from('trial_appointments')
          .insert([{
            ...submitData,
            created_by: profile?.id
          }]);

        if (error) {
          toast.error('Fehler beim Erstellen der Probestunde', { description: error.message });
          return;
        }

        toast.success('Probestunde erfolgreich erstellt');
      }

      onSuccess();
    } catch (error) {
      console.error('Error saving trial appointment:', error);
      toast.error('Fehler beim Speichern der Probestunde');
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (field: string, value: string) => {
    if (field === 'teacher_id' && value === 'null') {
      setFormData(prev => ({ ...prev, [field]: '' }));
    } else {
      setFormData(prev => ({ ...prev, [field]: value }));
    }
  };

  const handleInstrumentChange = (value: string) => {
    if (value === 'andere') {
      setShowCustomInstrumentInput(true);
      setFormData(prev => ({ ...prev, instrument: value }));
    } else {
      setShowCustomInstrumentInput(false);
      setCustomInstrumentValue('');
      setFormData(prev => ({ ...prev, instrument: value }));
    }
  };

  // Filter teachers based on role - for editing, show all teachers
  const availableTeachers = teachers;

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {/* Show error if teacher profile is not resolved */}
      {profile?.role === 'teacher' && !isTeacherProfileResolved && (
        <div className="bg-red-50 border border-red-200 rounded-md p-4">
          <p className="text-sm text-red-600">
            Lehrerprofil nicht gefunden. Bitte kontaktieren Sie Ihren Administrator.
          </p>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <Label htmlFor="student_name">Schülername *</Label>
          <Input
            id="student_name"
            value={formData.student_name}
            onChange={(e) => handleChange('student_name', e.target.value)}
            required
            placeholder="Schülername eingeben"
          />
        </div>

        <div>
          <Label htmlFor="instrument">Instrument *</Label>
          <Select 
            value={formData.instrument} 
            onValueChange={handleInstrumentChange}
            required
          >
            <SelectTrigger>
              <SelectValue placeholder="Instrument auswählen..." />
            </SelectTrigger>
            <SelectContent className="max-h-64">
              {INSTRUMENTS.map((instrument) => (
                <SelectItem key={instrument} value={instrument}>
                  {instrument === 'andere' ? 'Andere' : instrument}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {showCustomInstrumentInput && (
            <div className="mt-2">
              <Input
                value={customInstrumentValue}
                onChange={(e) => setCustomInstrumentValue(e.target.value)}
                placeholder="Instrument eingeben..."
                required
              />
            </div>
          )}
        </div>

        <div>
          <Label htmlFor="email">E-Mail</Label>
          <Input
            id="email"
            type="email"
            value={formData.email}
            onChange={(e) => handleChange('email', e.target.value)}
            placeholder="student@email.com"
          />
        </div>

        <div>
          <Label htmlFor="phone">Telefon</Label>
          <Input
            id="phone"
            value={formData.phone}
            onChange={(e) => handleChange('phone', e.target.value)}
            placeholder="+49 123 456 789"
          />
        </div>

        {/* Status field - only visible to admins */}
        {isAdmin && (
          <div>
            <Label htmlFor="status">Status</Label>
            <Select value={formData.status} onValueChange={(value) => handleChange('status', value)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="open">Offen</SelectItem>
                <SelectItem value="assigned">Zugewiesen</SelectItem>
                <SelectItem value="accepted">Angenommen</SelectItem>
              </SelectContent>
            </Select>
          </div>
        )}

        {/* Teacher assignment - only visible to admins */}
        {isAdmin && (
          <div>
            <Label htmlFor="teacher">Zugewiesener Lehrer</Label>
            <Select 
              value={formData.teacher_id || 'null'} 
              onValueChange={(value) => handleChange('teacher_id', value)}
            >
              <SelectTrigger>
                <SelectValue placeholder="Lehrer auswählen" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="null">Kein Lehrer zugewiesen</SelectItem>
                {availableTeachers.map((teacher) => (
                  <SelectItem key={teacher.id} value={teacher.id}>
                    {teacher.name} ({teacher.instrument})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}
      </div>

      <div className="flex justify-end space-x-2 pt-4">
        <Button 
          type="button" 
          variant="outline" 
          onClick={onCancel}
          className="bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray"
        >
          Abbrechen
        </Button>
        <Button 
          type="submit" 
          disabled={loading || (profile?.role === 'teacher' && !isTeacherProfileResolved)}
          className="bg-brand-primary hover:bg-brand-primary/90"
        >
          {loading ? 'Speichern...' : trialAppointment ? 'Probestunde aktualisieren' : 'Probestunde erstellen'}
        </Button>
      </div>
    </form>
  );
}