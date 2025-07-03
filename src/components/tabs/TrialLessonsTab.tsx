import { useState, useEffect, useMemo } from 'react';
import { supabase, TrialLesson, Teacher } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Plus, Search, MoreHorizontal, Edit, Check, Clock } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { TrialLessonForm } from '@/components/forms/TrialLessonForm';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';

export function TrialLessonsTab() {
  const { profile, isAdmin } = useAuth();
  const [trialLessons, setTrialLessons] = useState<TrialLesson[]>([]);
  const [teachers, setTeachers] = useState<Teacher[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [instrumentFilter, setInstrumentFilter] = useState<string>('all');
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingTrialLesson, setEditingTrialLesson] = useState<TrialLesson | null>(null);

  // Memoize current teacher lookup
  const currentTeacher = useMemo(() => 
    profile?.id ? teachers.find(t => t.profile_id === profile.id) : undefined, 
    [profile, teachers]
  );
  const currentTeacherId = currentTeacher?.id;

  useEffect(() => {
    fetchTrialLessons();
    fetchTeachers();
  }, []);

  const fetchTrialLessons = async () => {
    try {
      let query = supabase
        .from('trial_lessons')
        .select(`
          *,
          assigned_teacher:teachers(id, name, instrument)
        `)
        .order('created_at', { ascending: false });

      // Filter by assigned teacher for non-admin users
      if (profile?.role === 'teacher' && currentTeacherId) {
        query = query.eq('assigned_teacher_id', currentTeacherId);
      }

      const { data, error } = await query;

      if (error) {
        toast.error('Failed to fetch trial lessons', { description: error.message });
        return;
      }

      setTrialLessons(data || []);
    } catch (error) {
      console.error('Error fetching trial lessons:', error);
      toast.error('Failed to fetch trial lessons');
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
        toast.error('Failed to fetch teachers', { description: error.message });
        return;
      }

      setTeachers(data || []);
    } catch (error) {
      console.error('Error fetching teachers:', error);
    }
  };

  const handleAcceptTrialLesson = async (trialLesson: TrialLesson) => {
    if (!currentTeacher) {
      toast.error('Teacher profile not found');
      return;
    }

    try {
      const { error } = await supabase
        .from('trial_lessons')
        .update({
          status: 'assigned',
          assigned_teacher_id: currentTeacher.id
        })
        .eq('id', trialLesson.id);

      if (error) {
        toast.error('Failed to accept trial lesson', { description: error.message });
        return;
      }

      toast.success('Trial lesson accepted successfully');
      fetchTrialLessons();
    } catch (error) {
      console.error('Error accepting trial lesson:', error);
      toast.error('Failed to accept trial lesson');
    }
  };

  const canEditTrialLesson = (lesson: TrialLesson) => {
    return isAdmin || lesson.assigned_teacher_id === currentTeacherId;
  };

  const filteredTrialLessons = trialLessons.filter(lesson => {
    const matchesSearch = lesson.student_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         lesson.instrument.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         lesson.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         lesson.assigned_teacher?.name.toLowerCase().includes(searchTerm.toLowerCase());
    
    const matchesStatus = statusFilter === 'all' || lesson.status === statusFilter;
    const matchesInstrument = instrumentFilter === 'all' || lesson.instrument === instrumentFilter;
    
    return matchesSearch && matchesStatus && matchesInstrument;
  });

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
          <h1 className="text-2xl font-bold text-gray-900">Trial Lessons</h1>
          <p className="text-gray-600">Manage trial lesson requests and assignments</p>
        </div>
        <Button onClick={() => setShowAddForm(true)} className="w-full sm:w-auto bg-brand-primary hover:bg-brand-primary/90">
          <Plus className="h-4 w-4 mr-2" />
          Add Trial Lesson
        </Button>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex flex-col md:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
                <Input
                  placeholder="Search by student name, instrument, or teacher..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-full md:w-40">
                <SelectValue placeholder="Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Status</SelectItem>
                <SelectItem value="open">Open</SelectItem>
                <SelectItem value="assigned">Assigned</SelectItem>
              </SelectContent>
            </Select>
            <Select value={instrumentFilter} onValueChange={setInstrumentFilter}>
              <SelectTrigger className="w-full md:w-40">
                <SelectValue placeholder="Instrument" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Instruments</SelectItem>
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

      {/* Trial Lessons Grid */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {filteredTrialLessons.map((lesson) => (
          <Card key={lesson.id} className="hover:shadow-md transition-shadow">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-lg font-medium">{lesson.student_name}</CardTitle>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button 
                    variant="ghost" 
                    className="bg-transparent border-none shadow-none p-0 h-auto w-auto text-black hover:bg-transparent hover:text-black"
                  >
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  {lesson.status === 'open' && !isAdmin && (
                    <DropdownMenuItem onClick={() => handleAcceptTrialLesson(lesson)}>
                      <Check className="h-4 w-4 mr-2" />
                      Accept
                    </DropdownMenuItem>
                  )}
                  {canEditTrialLesson(lesson) && (
                    <DropdownMenuItem onClick={() => setEditingTrialLesson(lesson)}>
                      <Edit className="h-4 w-4 mr-2" />
                      Edit
                    </DropdownMenuItem>
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            </CardHeader>
            <CardContent>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-gray-600">Instrument</span>
                  <span className="text-sm">{lesson.instrument}</span>
                </div>
                
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-gray-600">Status</span>
                  <Badge 
                    variant={lesson.status === 'open' ? 'destructive' : 'default'}
                    className="flex items-center gap-1"
                  >
                    {lesson.status === 'open' ? (
                      <Clock className="h-3 w-3" />
                    ) : (
                      <Check className="h-3 w-3" />
                    )}
                    {lesson.status}
                  </Badge>
                </div>
                
                {lesson.email && (
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium text-gray-600">Email</span>
                    <span className="text-sm truncate">{lesson.email}</span>
                  </div>
                )}
                
                {lesson.phone && (
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium text-gray-600">Phone</span>
                    <span className="text-sm">{lesson.phone}</span>
                  </div>
                )}
                
                {lesson.assigned_teacher && (
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium text-gray-600">Teacher</span>
                    <span className="text-sm">{lesson.assigned_teacher.name}</span>
                  </div>
                )}
                
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-gray-600">Created</span>
                  <span className="text-sm text-gray-500">
                    {new Date(lesson.created_at).toLocaleDateString()}
                  </span>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {filteredTrialLessons.length === 0 && (
        <Card>
          <CardContent className="pt-6">
            <div className="text-center py-8">
              <p className="text-gray-500">No trial lessons found matching your criteria.</p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Add Trial Lesson Dialog */}
      <Dialog open={showAddForm} onOpenChange={setShowAddForm}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Add New Trial Lesson</DialogTitle>
          </DialogHeader>
          <TrialLessonForm
            teachers={teachers}
            onSuccess={() => {
              setShowAddForm(false);
              fetchTrialLessons();
            }}
            onCancel={() => setShowAddForm(false)}
          />
        </DialogContent>
      </Dialog>

      {/* Edit Trial Lesson Dialog */}
      <Dialog open={!!editingTrialLesson} onOpenChange={() => setEditingTrialLesson(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Edit Trial Lesson</DialogTitle>
          </DialogHeader>
          {editingTrialLesson && (
            <TrialLessonForm
              trialLesson={editingTrialLesson}
              teachers={teachers}
              onSuccess={() => {
                setEditingTrialLesson(null);
                fetchTrialLessons();
              }}
              onCancel={() => setEditingTrialLesson(null)}
            />
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}