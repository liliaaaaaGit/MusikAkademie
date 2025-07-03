import { useState, useEffect, useMemo } from 'react';
import { supabase, Student, Teacher } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Plus, Search, MoreHorizontal, Edit, Trash2, FileText, Info } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { StudentForm } from '@/components/forms/StudentForm';
import { DeleteStudentConfirmationModal } from '@/components/modals/DeleteStudentConfirmationModal';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';

export function StudentsTab() {
  const { profile, isAdmin } = useAuth();
  const [students, setStudents] = useState<Student[]>([]);
  const [teachers, setTeachers] = useState<Teacher[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [instrumentFilter, setInstrumentFilter] = useState<string>('all');
  const [teacherFilter, setTeacherFilter] = useState<string>('all');
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingStudent, setEditingStudent] = useState<Student | null>(null);
  const [deletingStudent, setDeletingStudent] = useState<Student | null>(null);

  // Memoize current teacher lookup
  const currentTeacher = useMemo(() => 
    profile?.id ? teachers.find(t => t.profile_id === profile.id) : undefined, 
    [profile, teachers]
  );
  const currentTeacherId = currentTeacher?.id;

  useEffect(() => {
    fetchStudents();
    fetchTeachers();
  }, []);

  const fetchStudents = async () => {
    try {
      let query = supabase
        .from('students')
        .select(`
          *,
          teacher:teachers(id, name, instrument),
          contract:contracts!students_contract_id_fkey(id, contract_variant_id, status, attendance_count, contract_variant:contract_variants(name, total_lessons))
        `)
        .order('name', { ascending: true });

      // Filter by teacher for non-admin users
      if (profile?.role === 'teacher' && currentTeacherId) {
        query = query.eq('teacher_id', currentTeacherId);
      }

      const { data, error } = await query;

      if (error) {
        toast.error('Failed to fetch students', { description: error.message });
        return;
      }

      setStudents(data || []);
    } catch (error) {
      console.error('Error fetching students:', error);
      toast.error('Failed to fetch students');
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

  const handleDeleteStudent = async (student: Student) => {
    if (!isAdmin) {
      toast.error('Berechtigung verweigert', { description: 'Nur Administratoren können Schüler löschen' });
      return;
    }

    setDeletingStudent(student);
  };

  const handleConfirmDelete = async () => {
    if (!deletingStudent) return;

    try {
      const { error } = await supabase
        .from('students')
        .delete()
        .eq('id', deletingStudent.id);

      if (error) {
        toast.error('Fehler beim Löschen des Schülers', { description: error.message });
        return;
      }

      toast.success('Schüler erfolgreich gelöscht');
      setDeletingStudent(null);
      fetchStudents();
    } catch (error) {
      console.error('Error deleting student:', error);
      toast.error('Fehler beim Löschen des Schülers');
    }
  };

  const handleMarkInactive = async () => {
    if (!deletingStudent) return;

    try {
      const { error } = await supabase
        .from('students')
        .update({ status: 'inactive' })
        .eq('id', deletingStudent.id);

      if (error) {
        toast.error('Fehler beim Markieren als inaktiv', { description: error.message });
        return;
      }

      toast.success('Schüler erfolgreich als inaktiv markiert');
      setDeletingStudent(null);
      fetchStudents();
    } catch (error) {
      console.error('Error marking student as inactive:', error);
      toast.error('Fehler beim Markieren als inaktiv');
    }
  };

  const getContractDisplay = (student: Student) => {
    if (student.contract?.contract_variant?.name) {
      return student.contract.contract_variant.name;
    }
    return '-';
  };

  // Helper function to get the correct contract progress display
  const getContractProgress = (student: Student) => {
    if (!student.contract) {
      return '-';
    }

    // Parse the attendance_count string to get completed lessons
    const attendanceCount = student.contract.attendance_count;
    if (!attendanceCount || !attendanceCount.includes('/')) {
      return attendanceCount || '-';
    }

    const [completedStr] = attendanceCount.split('/');
    const completed = parseInt(completedStr, 10) || 0;

    // Get total lessons from contract variant if available
    const totalLessons = student.contract.contract_variant?.total_lessons;
    
    if (totalLessons && totalLessons > 0) {
      // Use the actual total lessons from the contract variant
      return `${completed}/${totalLessons}`;
    }

    // Fallback to the original attendance_count if contract variant data is not available
    return attendanceCount;
  };

  const canEditStudent = (student: Student) => {
    // Teachers cannot edit students - only admins can
    return isAdmin;
  };

  const canDeleteStudent = (student: Student) => {
    return isAdmin; // Only admins can delete students
  };

  // Teachers cannot add students
  const canAddStudent = () => {
    return isAdmin;
  };

  const filteredStudents = students.filter(student => {
    const matchesSearch = student.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         student.instrument.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         student.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         student.teacher?.name.toLowerCase().includes(searchTerm.toLowerCase());
    
    const matchesStatus = statusFilter === 'all' || student.status === statusFilter;
    const matchesInstrument = instrumentFilter === 'all' || student.instrument === instrumentFilter;
    const matchesTeacher = teacherFilter === 'all' || student.teacher_id === teacherFilter;
    
    return matchesSearch && matchesStatus && matchesInstrument && matchesTeacher;
  });

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col space-y-8">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Schüler</h1>
          <p className="text-gray-600 mt-2">
            {isAdmin 
              ? 'Verwalten Sie Schülerdaten und Zuweisungen' 
              : 'Ihre zugewiesenen Schüler anzeigen'
            }
          </p>
        </div>
        {canAddStudent() && (
          <Button onClick={() => setShowAddForm(true)} className="w-full sm:w-auto bg-brand-primary hover:bg-brand-primary/90">
            <Plus className="h-4 w-4 mr-2" />
            Neuer Schüler
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
                  Lehreransicht - Nur Lesen
                </h3>
                <p className="text-sm text-gray-700 mt-1">
                  Sie können nur Ihre zugewiesenen Schüler anzeigen. Das Hinzufügen, Bearbeiten oder Löschen von Schülern ist nur für Administratoren möglich.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Filters */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex flex-col lg:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
                <Input
                  placeholder="Suchen nach Schülern, Instrumenten oder Lehrern..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>
            <div className="flex flex-col sm:flex-row gap-4">
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="w-full sm:w-40">
                  <SelectValue placeholder="Status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">Alle Status</SelectItem>
                  <SelectItem value="active">Aktiv</SelectItem>
                  <SelectItem value="inactive">Inaktiv</SelectItem>
                </SelectContent>
              </Select>
              <Select value={instrumentFilter} onValueChange={setInstrumentFilter}>
                <SelectTrigger className="w-full sm:w-40">
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
              {isAdmin && (
                <Select value={teacherFilter} onValueChange={setTeacherFilter}>
                  <SelectTrigger className="w-full sm:w-40">
                    <SelectValue placeholder="Lehrer" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Alle Lehrer</SelectItem>
                    {teachers.map(teacher => (
                      <SelectItem key={teacher.id} value={teacher.id}>
                        {teacher.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Students Table */}
      <div className="flex-1 overflow-auto">
        <Card>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Schülername</TableHead>
                  <TableHead>Instrument</TableHead>
                  {isAdmin && <TableHead>Lehrer</TableHead>}
                  <TableHead>E-Mail</TableHead>
                  <TableHead>Telefon</TableHead>
                  <TableHead>Vertrag</TableHead>
                  {isAdmin && <TableHead>Bank-ID</TableHead>}
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Aktionen</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredStudents.map((student) => (
                  <TableRow key={student.id} className="hover:bg-gray-50">
                    <TableCell className="font-medium">{student.name}</TableCell>
                    <TableCell>{student.instrument}</TableCell>
                    {isAdmin && <TableCell>{student.teacher?.name || '-'}</TableCell>}
                    <TableCell className="max-w-48 truncate">{student.email || '-'}</TableCell>
                    <TableCell>{student.phone || '-'}</TableCell>
                    <TableCell>
                      {student.contract ? (
                        <div className="flex flex-col">
                          <span className="text-sm font-medium text-gray-900">
                            {getContractDisplay(student)}
                          </span>
                          <span className="text-xs text-gray-500 mt-1">
                            {getContractProgress(student)}
                          </span>
                        </div>
                      ) : (
                        '-'
                      )}
                    </TableCell>
                    {isAdmin && (
                      <TableCell>
                        <span className="font-mono text-sm bg-gray-100 px-2 py-1 rounded">
                          {student.bank_id || '-'}
                        </span>
                      </TableCell>
                    )}
                    <TableCell>
                      <Badge variant={student.status === 'active' ? 'default' : 'secondary'}>
                        {student.status === 'active' ? 'Aktiv' : 'Inaktiv'}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      {(canEditStudent(student) || canDeleteStudent(student)) && (
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
                            {canEditStudent(student) && (
                              <DropdownMenuItem onClick={() => setEditingStudent(student)}>
                                <Edit className="h-4 w-4 mr-2" />
                                Bearbeiten
                              </DropdownMenuItem>
                            )}
                            {student.contract && (
                              <DropdownMenuItem>
                                <FileText className="h-4 w-4 mr-2" />
                                Vertrag anzeigen
                              </DropdownMenuItem>
                            )}
                            {canDeleteStudent(student) && (
                              <DropdownMenuItem 
                                onClick={() => handleDeleteStudent(student)}
                                className="text-red-600"
                              >
                                <Trash2 className="h-4 w-4 mr-2" />
                                Löschen
                              </DropdownMenuItem>
                            )}
                          </DropdownMenuContent>
                        </DropdownMenu>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>

            {filteredStudents.length === 0 && (
              <div className="text-center py-12">
                <p className="text-gray-500">
                  {!isAdmin && students.length === 0 
                    ? 'Ihnen sind noch keine Schüler zugewiesen.'
                    : 'Keine Schüler gefunden, die Ihren Kriterien entsprechen.'
                  }
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Add Student Dialog - Only show for admins */}
      {isAdmin && (
        <Dialog open={showAddForm} onOpenChange={setShowAddForm}>
          <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Neuen Schüler hinzufügen</DialogTitle>
            </DialogHeader>
            <StudentForm
              teachers={teachers}
              onSuccess={() => {
                setShowAddForm(false);
                fetchStudents();
              }}
              onCancel={() => setShowAddForm(false)}
            />
          </DialogContent>
        </Dialog>
      )}

      {/* Edit Student Dialog - Only show for admins */}
      {isAdmin && (
        <Dialog open={!!editingStudent} onOpenChange={() => setEditingStudent(null)}>
          <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Schüler bearbeiten</DialogTitle>
            </DialogHeader>
            {editingStudent && (
              <StudentForm
                student={editingStudent}
                teachers={teachers}
                onSuccess={() => {
                  setEditingStudent(null);
                  fetchStudents();
                }}
                onCancel={() => setEditingStudent(null)}
              />
            )}
          </DialogContent>
        </Dialog>
      )}

      {/* Delete Student Confirmation Modal */}
      {deletingStudent && (
        <DeleteStudentConfirmationModal
          open={!!deletingStudent}
          onClose={() => setDeletingStudent(null)}
          onConfirm={handleConfirmDelete}
          onMarkInactive={handleMarkInactive}
          student={deletingStudent}
        />
      )}
    </div>
  );
}