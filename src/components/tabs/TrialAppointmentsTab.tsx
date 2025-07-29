import { useState, useEffect, useMemo } from 'react';
import { supabase, TrialAppointment, Teacher, acceptTrial, declineTrial } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Plus, Search, MoreHorizontal, Edit, Check, Clock, User, Trash2, Info, X, UserCheck } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { TrialAppointmentForm } from '@/components/forms/TrialAppointmentForm';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';

export function TrialAppointmentsTab() {
  const { profile, isAdmin } = useAuth();
  const [trialAppointments, setTrialAppointments] = useState<TrialAppointment[]>([]);
  const [teachers, setTeachers] = useState<Teacher[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [instrumentFilter, setInstrumentFilter] = useState<string>('all');
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingTrialAppointment, setEditingTrialAppointment] = useState<TrialAppointment | null>(null);

  // Memoize current teacher lookup
  const currentTeacher = useMemo(() => 
    profile?.id ? teachers.find(t => t.profile_id === profile.id) : undefined, 
    [profile, teachers]
  );

  useEffect(() => {
    fetchTeachers();
  }, []);

  useEffect(() => {
    if (profile && (isAdmin || currentTeacher)) {
      fetchTrialAppointments();
    }
  }, [profile, isAdmin, currentTeacher]);

  const fetchTrialAppointments = async () => {
    try {
      let query = supabase
        .from('trial_appointments')
        .select(`
          *,
          teacher:teachers(id, name, instrument),
          created_by_profile:profiles!trial_appointments_created_by_fkey(id, full_name)
        `);

      // Apply role-based filtering
      if (profile?.role === 'teacher' && currentTeacher) {
        // Teachers see:
        // 1. Trial lessons assigned to themselves
        // 2. All open trial lessons
        // 3. Trial lessons they have accepted
        query = query.or(`teacher_id.eq.${currentTeacher.id},status.eq.open`);
      }
      // Admins see everything (no additional filtering needed)

      const { data, error } = await query.order('created_at', { ascending: false });

      if (error) {
        toast.error('Fehler beim Laden der Probestunden', { description: error.message });
        return;
      }

      setTrialAppointments(data || []);
    } catch (error) {
      console.error('Error fetching trial appointments:', error);
      toast.error('Fehler beim Laden der Probestunden');
    } finally {
      setLoading(false);
    }
  };

  const fetchTeachers = async () => {
    try {
      const { data, error } = await supabase
        .from('teachers')
        .select('*')
        .order('name');

      if (error) {
        toast.error('Fehler beim Laden der Lehrer', { description: error.message });
        return;
      }

      setTeachers(data || []);
    } catch (error) {
      console.error('Error fetching teachers:', error);
    }
  };

  const handleAcceptTrialAppointment = async (trialAppointment: TrialAppointment) => {
    if (!currentTeacher) {
      toast.error('Lehrerprofil nicht gefunden');
      return;
    }

    try {
      const { error } = await acceptTrial(trialAppointment.id);

      if (error) {
        if (error.message.includes('already accepted')) {
          toast.error('Diese Probestunde wurde bereits von einem anderen Lehrer angenommen');
        } else if (error.message.includes('not assigned')) {
          toast.error('Sie sind nicht für diese Probestunde zugewiesen');
        } else {
          toast.error('Fehler beim Annehmen der Probestunde', { description: error.message });
        }
        return;
      }

      toast.success('Probestunde erfolgreich angenommen');
      fetchTrialAppointments();
    } catch (error) {
      console.error('Error accepting trial appointment:', error);
      toast.error('Fehler beim Annehmen der Probestunde');
    }
  };

  const handleDeclineTrialAppointment = async (trialAppointment: TrialAppointment) => {
    if (!currentTeacher) {
      toast.error('Lehrerprofil nicht gefunden');
      return;
    }

    try {
      const { error } = await declineTrial(trialAppointment.id);

      if (error) {
        if (error.message.includes('not assigned')) {
          toast.error('Sie sind nicht für diese Probestunde zugewiesen');
        } else {
          toast.error('Fehler beim Ablehnen der Probestunde', { description: error.message });
        }
        return;
      }

      toast.success('Probestunde abgelehnt und wieder freigegeben');
      fetchTrialAppointments();
    } catch (error) {
      console.error('Error declining trial appointment:', error);
      toast.error('Fehler beim Ablehnen der Probestunde');
    }
  };

  const handleDeleteTrialAppointment = async (trialAppointment: TrialAppointment) => {
    if (!isAdmin) {
      toast.error('Nur Administratoren können Probestunden löschen');
      return;
    }

    if (!confirm(`Sind Sie sicher, dass Sie die Probestunde für ${trialAppointment.student_name} löschen möchten?`)) {
      return;
    }

    try {
      const { error } = await supabase
        .from('trial_appointments')
        .delete()
        .eq('id', trialAppointment.id);

      if (error) {
        toast.error('Fehler beim Löschen der Probestunde', { description: error.message });
        return;
      }

      toast.success('Probestunde erfolgreich gelöscht');
      fetchTrialAppointments();
    } catch (error) {
      console.error('Error deleting trial appointment:', error);
      toast.error('Fehler beim Löschen der Probestunde');
    }
  };

  const canEditTrialAppointment = (appointment: TrialAppointment) => {
    // Only admins can edit trial appointments
    return isAdmin;
  };

  const canDeleteTrialAppointment = () => {
    // Only admins can delete trial appointments
    return isAdmin;
  };

  const canAddTrialAppointment = () => {
    // Only admins can add trial appointments
    return isAdmin;
  };

  const canAcceptTrial = (appointment: TrialAppointment) => {
    if (!currentTeacher) return false;
    
    // For assigned trials, only the assigned teacher can accept
    if (appointment.status === 'assigned') {
      return appointment.teacher_id === currentTeacher.id;
    }
    
    // For open trials, any teacher can accept
    if (appointment.status === 'open') {
      return true;
    }
    
    return false;
  };

  const canDeclineTrial = (appointment: TrialAppointment) => {
    if (!currentTeacher) return false;
    
    // Only assigned trials can be declined, and only by the assigned teacher
    return appointment.status === 'assigned' && appointment.teacher_id === currentTeacher.id;
  };

  const filteredTrialAppointments = trialAppointments.filter(appointment => {
    const matchesSearch = appointment.student_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         appointment.instrument.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         appointment.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         appointment.teacher?.name.toLowerCase().includes(searchTerm.toLowerCase());
    
    const matchesInstrument = instrumentFilter === 'all' || appointment.instrument === instrumentFilter;
    
    return matchesSearch && matchesInstrument;
  });

  // Split appointments by status
  const assignedAppointments = filteredTrialAppointments.filter(app => app.status === 'assigned');
  const openAppointments = filteredTrialAppointments.filter(app => app.status === 'open');
  const acceptedAppointments = filteredTrialAppointments.filter(app => app.status === 'accepted');

  const renderAppointmentCard = (appointment: TrialAppointment) => (
    <Card key={appointment.id} className="hover:shadow-md transition-shadow">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-lg font-medium">{appointment.student_name}</CardTitle>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button 
              variant="ghost" 
              className="bg-transparent border-none shadow-none p-0 h-auto w-auto text-black hover:bg-transparent hover:text-black"
            >
              <MoreHorizontal className="h-5 w-5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {canAcceptTrial(appointment) && (
              <DropdownMenuItem onClick={() => handleAcceptTrialAppointment(appointment)}>
                <Check className="h-4 w-4 mr-2" />
                Annehmen
              </DropdownMenuItem>
            )}
            {canDeclineTrial(appointment) && (
              <DropdownMenuItem onClick={() => handleDeclineTrialAppointment(appointment)}>
                <X className="h-4 w-4 mr-2" />
                Ablehnen
              </DropdownMenuItem>
            )}
            {canEditTrialAppointment(appointment) && (
              <DropdownMenuItem onClick={() => setEditingTrialAppointment(appointment)}>
                <Edit className="h-4 w-4 mr-2" />
                Bearbeiten
              </DropdownMenuItem>
            )}
            {canDeleteTrialAppointment() && (
              <DropdownMenuItem 
                onClick={() => handleDeleteTrialAppointment(appointment)}
                className="text-red-600"
              >
                <Trash2 className="h-4 w-4 mr-2" />
                Löschen
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-600">Instrument</span>
            <span className="text-sm">{appointment.instrument}</span>
          </div>
          
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-600">Status</span>
            <Badge 
              variant={
                appointment.status === 'open' ? 'destructive' : 
                appointment.status === 'assigned' ? 'default' : 
                'secondary'
              }
              className="flex items-center gap-1"
            >
              {appointment.status === 'open' ? (
                <Clock className="h-3 w-3" />
              ) : appointment.status === 'assigned' ? (
                <UserCheck className="h-3 w-3" />
              ) : (
                <Check className="h-3 w-3" />
              )}
              {appointment.status === 'open' ? 'Offen' : 
               appointment.status === 'assigned' ? 'Zugewiesen' : 
               'Angenommen'}
            </Badge>
          </div>
          
          {appointment.email && (
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">E-Mail</span>
              <span className="text-sm truncate max-w-32">{appointment.email}</span>
            </div>
          )}
          
          {appointment.phone && (
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">Telefon</span>
              <span className="text-sm">{appointment.phone}</span>
            </div>
          )}
          
          {appointment.teacher && (
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">
                {appointment.status === 'assigned' ? 'Zugewiesen an' : 'Lehrer'}
              </span>
              <span className="text-sm">{appointment.teacher.name}</span>
            </div>
          )}

          {appointment.created_by_profile && (
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">Erstellt von</span>
              <span className="text-sm">{appointment.created_by_profile.full_name}</span>
            </div>
          )}
          
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-600">Erstellt</span>
            <span className="text-sm text-gray-500">
              {new Date(appointment.created_at).toLocaleDateString('de-DE')}
            </span>
          </div>

          {/* Quick action buttons */}
          {(canAcceptTrial(appointment) || canDeclineTrial(appointment)) && (
            <div className="pt-2 border-t flex gap-2">
              {canAcceptTrial(appointment) && (
                <Button
                  onClick={() => handleAcceptTrialAppointment(appointment)}
                  className="flex-1 bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
                  size="sm"
                >
                  <Check className="h-4 w-4 mr-2" />
                  Annehmen
                </Button>
              )}
              {canDeclineTrial(appointment) && (
                <Button
                  onClick={() => handleDeclineTrialAppointment(appointment)}
                  variant="outline"
                  className="flex-1"
                  size="sm"
                >
                  <X className="h-4 w-4 mr-2" />
                  Ablehnen
                </Button>
              )}
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Probestunden</h1>
          <p className="text-gray-600">
            {isAdmin 
              ? 'Probestunden-Anfragen verwalten und zuweisen'
              : 'Probestunden anzeigen und bearbeiten'
            }
          </p>
        </div>
        {canAddTrialAppointment() && (
          <Button onClick={() => setShowAddForm(true)} className="w-full sm:w-auto bg-brand-primary hover:bg-brand-primary/90">
            <Plus className="h-4 w-4 mr-2" />
            Neue Probestunde
          </Button>
        )}
      </div>

      {/* Show info message for teachers */}
      {!isAdmin && (
        <Card className="bg-gray-50 border-gray-200">
          <CardContent className="pt-6">
            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0">
                <Info className="h-5 w-5 text-gray-600" />
              </div>
              <div>
                <h3 className="text-sm font-medium text-gray-800">
                  Lehreransicht - Probestunden verwalten
                </h3>
                <p className="text-sm text-gray-700 mt-1">
                  Sie können zugewiesene Probestunden annehmen oder ablehnen und offene Probestunden annehmen. 
                  Das Erstellen und Bearbeiten von Probestunden ist nur für Administratoren möglich.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Filters */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex flex-col md:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
                <Input
                  placeholder="Suchen nach Schülername, Instrument oder Lehrer..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>
            <Select value={instrumentFilter} onValueChange={setInstrumentFilter}>
              <SelectTrigger className="w-full md:w-40">
                <SelectValue placeholder="Instrument" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Alle Instrumente</SelectItem>
                {INSTRUMENTS.map(instrument => (
                  <SelectItem key={instrument} value={instrument}>
                    {instrument}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      {/* Assigned Appointments Section */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <UserCheck className="h-5 w-5 text-blue-500" />
            <h2 className="text-xl font-semibold text-gray-900">Zugewiesene Probestunden</h2>
            <Badge variant="outline" className="bg-blue-50 text-blue-700 border-blue-200">
              {assignedAppointments.length}
            </Badge>
          </div>
        </div>

        {assignedAppointments.length > 0 ? (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {assignedAppointments.map(renderAppointmentCard)}
          </div>
        ) : (
          <Card>
            <CardContent className="pt-6">
              <div className="text-center py-8">
                <UserCheck className="h-12 w-12 text-gray-300 mx-auto mb-4" />
                <p className="text-gray-500">Keine zugewiesenen Probestunden gefunden.</p>
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      <Separator className="my-8" />

      {/* Open Appointments Section */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Clock className="h-5 w-5 text-orange-500" />
            <h2 className="text-xl font-semibold text-gray-900">Offene Probestunden</h2>
            <Badge variant="outline" className="bg-orange-50 text-orange-700 border-orange-200">
              {openAppointments.length}
            </Badge>
          </div>
        </div>

        {openAppointments.length > 0 ? (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {openAppointments.map(renderAppointmentCard)}
          </div>
        ) : (
          <Card>
            <CardContent className="pt-6">
              <div className="text-center py-8">
                <Clock className="h-12 w-12 text-gray-300 mx-auto mb-4" />
                <p className="text-gray-500">Keine offenen Probestunden gefunden.</p>
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      <Separator className="my-8" />

      {/* Accepted Appointments Section */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Check className="h-5 w-5 text-green-500" />
            <h2 className="text-xl font-semibold text-gray-900">Angenommene Probestunden</h2>
            <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
              {acceptedAppointments.length}
            </Badge>
          </div>
        </div>

        {acceptedAppointments.length > 0 ? (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {acceptedAppointments.map(renderAppointmentCard)}
          </div>
        ) : (
          <Card>
            <CardContent className="pt-6">
              <div className="text-center py-8">
                <User className="h-12 w-12 text-gray-300 mx-auto mb-4" />
                <p className="text-gray-500">Keine angenommenen Probestunden gefunden.</p>
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Add Trial Appointment Dialog - Only show for admins */}
      {isAdmin && (
        <Dialog open={showAddForm} onOpenChange={setShowAddForm}>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>Neue Probestunde hinzufügen</DialogTitle>
            </DialogHeader>
            <TrialAppointmentForm
              teachers={teachers}
              onSuccess={() => {
                setShowAddForm(false);
                fetchTrialAppointments();
              }}
              onCancel={() => setShowAddForm(false)}
            />
          </DialogContent>
        </Dialog>
      )}

      {/* Edit Trial Appointment Dialog - Only show for admins */}
      {isAdmin && (
        <Dialog open={!!editingTrialAppointment} onOpenChange={() => setEditingTrialAppointment(null)}>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>Probestunde bearbeiten</DialogTitle>
            </DialogHeader>
            {editingTrialAppointment && (
              <TrialAppointmentForm
                trialAppointment={editingTrialAppointment}
                teachers={teachers}
                onSuccess={() => {
                  setEditingTrialAppointment(null);
                  fetchTrialAppointments();
                }}
                onCancel={() => setEditingTrialAppointment(null)}
              />
            )}
          </DialogContent>
        </Dialog>
      )}

      {/* Message Notification */}
      {/* Removed: {message && ( */}
      {/* Removed:   <Card className="bg-gray-50 border-gray-200"> */}
      {/* Removed:     <CardContent className="pt-6"> */}
      {/* Removed:       <div className="flex items-start space-x-3"> */}
      {/* Removed:         <div className="flex-shrink-0"> */}
      {/* Removed:           <Info className="h-5 w-5 text-gray-600" /> */}
      {/* Removed:         </div> */}
      {/* Removed:         <div> */}
      {/* Removed:           <h3 className="text-sm font-medium text-gray-800"> */}
      {/* Removed:             {message} */}
      {/* Removed:           </h3> */}
      {/* Removed:         </div> */}
      {/* Removed:       </div> */}
      {/* Removed:     </CardContent> */}
      {/* Removed:   </Card> */}
      {/* Removed: )} */}
    </div>
  );
}