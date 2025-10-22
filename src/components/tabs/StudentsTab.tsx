import { useState, useEffect, useMemo } from 'react';
import { supabase, Student, Teacher } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { getStudentForEdit, StudentForEdit } from '@/lib/students/getStudentForEdit';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Plus, Search, MoreHorizontal, Edit, Trash2, FileText } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { StudentForm } from '@/components/forms/StudentForm';
import { DeleteStudentConfirmationModal } from '@/components/modals/DeleteStudentConfirmationModal';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';
import { ContractDetailsModal } from '@/components/modals/ContractDetailsModal';
import { StudentCardView } from './StudentCardView';
import { useIsMobile } from '@/hooks/useIsMobile';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';

export function StudentsTab() {
  const { profile, isAdmin } = useAuth();
  const isMobile = useIsMobile();
  const [students, setStudents] = useState<Student[]>([]);
  const [teachers, setTeachers] = useState<Teacher[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [instrumentFilter, setInstrumentFilter] = useState<string>('all');
  const [teacherFilter, setTeacherFilter] = useState<string>('all');
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingStudent, setEditingStudent] = useState<Student | null>(null);
  const [prefilledStudent, setPrefilledStudent] = useState<StudentForEdit | null>(null);
  const [deletingStudent, setDeletingStudent] = useState<Student | null>(null);
  const [contractModalOpen, setContractModalOpen] = useState(false);
  const [contractModalLoading, setContractModalLoading] = useState(false);
  const [contractModalData, setContractModalData] = useState(null as import('@/lib/supabase').Contract | null);

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
          contracts:contracts!fk_contracts_student_id(
            id,
            contract_variant_id,
            status,
            attendance_count,
            discount_ids,
            custom_discount_percent,
            first_payment_date,
            teacher:teachers!contracts_teacher_id_fkey(id, name, instrument),
            contract_variant:contract_variants(
              id,
              name,
              total_lessons,
              contract_category_id,
              contract_category:contract_categories(id, name, display_name)
            )
          )
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

      setStudents((data as unknown as Student[]) || []);
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

  const handleEmailClick = async (email: string) => {
    if (email && email !== '-') {
      try {
        await navigator.clipboard.writeText(email);
        toast.success('E-Mail-Adresse kopiert', {
          description: email
        });
      } catch (error) {
        // Fallback for older browsers
        const textArea = document.createElement('textarea');
        textArea.value = email;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
        toast.success('E-Mail-Adresse kopiert', {
          description: email
        });
      }
    }
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


  const canEditStudent = () => {
    // Teachers cannot edit students - only admins can
    return isAdmin;
  };

  const canDeleteStudent = () => {
    return isAdmin; // Only admins can delete students
  };

  // Teachers cannot add students
  const canAddStudent = () => {
    return isAdmin;
  };

  const handleShowContract = async (student: Student) => {
    setContractModalOpen(true);
    setContractModalLoading(true);
    setContractModalData(null);
    try {
      const { data, error } = await supabase
        .from('contracts')
        .select('*')
        .eq('student_id', student.id)
        .single();
      if (error || !data) {
        setContractModalData(null);
      } else {
        setContractModalData(data);
      }
    } catch (e) {
      setContractModalData(null);
    } finally {
      setContractModalLoading(false);
    }
  };

  const filteredStudents = students.filter(student => {
    const matchesSearch = student.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         student.instrument.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         student.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         student.contracts?.some(contract => 
                           contract.teacher?.name.toLowerCase().includes(searchTerm.toLowerCase())
                         );
    
    const matchesStatus = statusFilter === 'all' || student.status === statusFilter;
    const matchesInstrument = instrumentFilter === 'all' || student.instrument === instrumentFilter;
    
    // FIXED: Check teacher filter against the nested teacher ID from contracts array
    const matchesTeacher = teacherFilter === 'all' || 
                          (student.contracts && student.contracts.some(contract => 
                            contract.teacher?.id === teacherFilter
                          ));
    
    return matchesSearch && matchesStatus && matchesInstrument && matchesTeacher;
  });

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
      </div>
    );
  }

  // Removed debug log to avoid PII in console

  return (
    <div className="h-full flex flex-col space-y-8">
      {profile?.role === 'teacher' && isMobile ? (
        <>
          <div className="w-full max-w-[600px] mx-auto px-2">
            {/* Headline for teacher mobile view */}
            <h1 className="text-2xl font-bold text-gray-900 mb-2">Schülerübersicht</h1>
            {/* Filters */}
            <Card className="mb-4">
              <CardContent className="pt-6">
                <div className="flex flex-col gap-4">
                  <div className="relative">
                    <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
                    <Input
                      placeholder="Suchen nach Schülern, Instrumenten oder Lehrern..."
                      value={searchTerm}
                      onChange={(e) => setSearchTerm(e.target.value)}
                      className="pl-10"
                    />
                  </div>
                  <Select value={statusFilter} onValueChange={setStatusFilter}>
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Status" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Alle Status</SelectItem>
                      <SelectItem value="active">Aktiv</SelectItem>
                      <SelectItem value="inactive">Inaktiv</SelectItem>
                    </SelectContent>
                  </Select>
                  <Select value={instrumentFilter} onValueChange={setInstrumentFilter}>
                    <SelectTrigger className="w-full">
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
            {/* Card List */}
            <StudentCardView students={filteredStudents} noOuterPadding />
          </div>
        </>
      ) : (
        <>
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

      {/* Filters */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex flex-col lg:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
                <Input
                  placeholder="Suche nach Schülern"
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

          {/* Students Table or Card View */}
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
                  <TableHead>Verträge</TableHead>
                  {isAdmin && <TableHead>Bank-ID</TableHead>}
                  <TableHead>Status</TableHead>
                  {isAdmin && <TableHead className="text-right">Aktionen</TableHead>}
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredStudents.map((student) => (
                  <TableRow key={student.id} className="hover:bg-gray-50">
                    <TableCell className="font-medium">{student.name}</TableCell>
                    <TableCell>{student.instrument}</TableCell>
                    {isAdmin && (
                      <TableCell>
                        {student.contracts && student.contracts.length > 0
                          ? Array.from(new Set(
                              student.contracts
                                .map(c => c.teacher?.name)
                                .filter(Boolean)
                            )).join(', ')
                          : '-'}
                      </TableCell>
                    )}
                    <TableCell className="max-w-48 truncate">
                      <TooltipProvider>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <span 
                              className="cursor-pointer hover:underline"
                              onClick={() => handleEmailClick(student.email || '')}
                            >
                              {student.email || '-'}
                            </span>
                          </TooltipTrigger>
                          <TooltipContent>
                            <p>{student.email || '-'}</p>
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>
                    </TableCell>
                    <TableCell>{student.phone || '-'}</TableCell>
                    <TableCell>
                      {student.contracts && student.contracts.length > 0
                        ? String(student.contracts.length)
                        : '0'}
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
                    {isAdmin && (
                      <TableCell className="text-right">
                        {(canEditStudent() || canDeleteStudent()) && (
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
                              {canEditStudent() && (
                                <DropdownMenuItem onClick={async () => {
                                  setEditingStudent(student);
                                  try {
                                    const prefilledData = await getStudentForEdit(student.id);
                                    setPrefilledStudent(prefilledData);
                                  } catch (error) {
                                    console.error('Error loading student data:', error);
                                    toast.error('Fehler beim Laden der Schülerdaten');
                                  }
                                }}>
                                  <Edit className="h-4 w-4 mr-2" />
                                  Bearbeiten
                                </DropdownMenuItem>
                              )}
                              {isAdmin && (
                                <DropdownMenuItem onClick={() => handleShowContract(student)}>
                                  <FileText className="h-4 w-4 mr-2" />
                                  Vertrag anzeigen
                                </DropdownMenuItem>
                              )}
                              {canDeleteStudent() && (
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
                    )}
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
        </>
      )}

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
                prefilledStudent={prefilledStudent || undefined}
                onSuccess={() => {
                  setEditingStudent(null);
                  setPrefilledStudent(null);
                  fetchStudents();
                }}
                onCancel={() => {
                  setEditingStudent(null);
                  setPrefilledStudent(null);
                }}
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

      <ContractDetailsModal
        open={contractModalOpen}
        onClose={() => setContractModalOpen(false)}
        contract={contractModalData}
        loading={contractModalLoading}
      />
    </div>
  );
}