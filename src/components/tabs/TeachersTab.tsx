import { useState, useEffect } from 'react';
import { supabase, Teacher } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Plus, Search, MoreHorizontal, Edit, Trash2 } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { TeacherForm } from '@/components/forms/TeacherForm';
import { DeleteTeacherConfirmationModal } from '@/components/modals/DeleteTeacherConfirmationModal';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { StudentCountTooltip } from '@/components/StudentCountTooltip';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';

export function TeachersTab() {
  const { profile, isAdmin } = useAuth();
  const [teachers, setTeachers] = useState<Teacher[]>([]);
  const [teacherContracts, setTeacherContracts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [instrumentFilter, setInstrumentFilter] = useState<string>('all');
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingTeacher, setEditingTeacher] = useState<Teacher | null>(null);
  const [deletingTeacher, setDeletingTeacher] = useState<Teacher | null>(null);

  useEffect(() => {
    fetchTeachers();
    fetchTeacherContractCounts();
  }, []);

  const fetchTeachers = async () => {
    try {
      let query = supabase
        .from('teachers')
        .select('*')
        .order('name');

      // Filter by profile for non-admin users
      if (profile?.role === 'teacher' && !isAdmin) {
        query = query.eq('profile_id', profile.id);
      }

      const { data, error } = await query;

      if (error) {
        toast.error('Failed to fetch teachers', { description: error.message });
        return;
      }

      setTeachers(data || []);
    } catch (error) {
      console.error('Error fetching teachers:', error);
      toast.error('Failed to fetch teachers');
    } finally {
      setLoading(false);
    }
  };

  const fetchTeacherContractCounts = async () => {
    try {
      const { data: contractData, error: contractError } = await supabase
        .from('contracts')
        .select(`
          id,
          student:students!fk_contracts_student_id(
            id,
            teacher_id
          )
        `);

      if (contractError) {
        console.error('Error fetching contract counts:', contractError);
        return;
      }

      // Count contracts per teacher
      const counts: Record<string, number> = {};
      (contractData)?.forEach(contract => {
        if (Array.isArray(contract.student)) {
          contract.student.forEach((s: any) => {
            if (s.teacher_id) {
              const teacherId = s.teacher_id;
              counts[teacherId] = (counts[teacherId] || 0) + 1;
            }
          });
        } else if (contract.student && (contract.student as any).teacher_id) {
          const teacherId = (contract.student as any).teacher_id;
          counts[teacherId] = (counts[teacherId] || 0) + 1;
        }
      });

      setTeacherContracts(counts);
    } catch (error) {
      console.error('Error fetching teacher contract counts:', error);
    }
  };

  const handleDeleteTeacher = async (teacher: Teacher) => {
    if (!isAdmin) {
      toast.error('Berechtigung verweigert', { description: 'Nur Administratoren können Lehrer löschen' });
      return;
    }

    setDeletingTeacher(teacher);
  };

  const handleConfirmDelete = async () => {
    if (!deletingTeacher) return;

    try {
      const { error } = await supabase
        .from('teachers')
        .delete()
        .eq('id', deletingTeacher.id);

      if (error) {
        toast.error('Fehler beim Löschen des Lehrers', { description: error.message });
        return;
      }

      toast.success('Lehrer erfolgreich gelöscht');
      setDeletingTeacher(null);
      fetchTeachers();
      fetchTeacherContractCounts();
    } catch (error) {
      console.error('Error deleting teacher:', error);
      toast.error('Fehler beim Löschen des Lehrers');
    }
  };

  const canEditTeacher = (teacher: Teacher) => {
    return isAdmin || teacher.profile_id === profile?.id;
  };

  const getInstrumentDisplay = (instrument: string | string[]) => {
    if (Array.isArray(instrument)) {
      return instrument.length > 0 ? instrument.join(', ') : '-';
    }
    return instrument || '-';
  };

  const filteredTeachers = teachers.filter(teacher => {
    const instrumentDisplay = getInstrumentDisplay(teacher.instrument);
    const matchesSearch = teacher.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         instrumentDisplay.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         teacher.email.toLowerCase().includes(searchTerm.toLowerCase());
    
    const matchesInstrument = instrumentFilter === 'all' || 
                             (Array.isArray(teacher.instrument) 
                               ? teacher.instrument.includes(instrumentFilter)
                               : teacher.instrument === instrumentFilter);
    
    return matchesSearch && matchesInstrument;
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
          <h1 className="text-3xl font-bold text-gray-900">Lehrer</h1>
          <p className="text-gray-600 mt-2">Verwalten Sie Lehrerprofile und Zuweisungen</p>
        </div>
        <div className="flex gap-3 w-full sm:w-auto">
          {isAdmin && (
            <Button onClick={() => setShowAddForm(true)} className="flex-1 sm:flex-none bg-brand-primary hover:bg-brand-primary/90">
              <Plus className="h-4 w-4 mr-2" />
              Neuer Lehrer
            </Button>
          )}
        </div>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex flex-col lg:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
                <Input
                  placeholder="Suchen nach Lehrern, Instrumenten oder E-Mail..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10"
                />
              </div>
            </div>
            <div className="flex flex-col sm:flex-row gap-4">
              <Select value={instrumentFilter} onValueChange={setInstrumentFilter}>
                <SelectTrigger className="w-full sm:w-48">
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
          </div>
        </CardContent>
      </Card>

      {/* Teachers Table */}
      <div className="flex-1 overflow-auto">
        <Card>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Lehrername</TableHead>
                  <TableHead>Instrumente</TableHead>
                  <TableHead>E-Mail</TableHead>
                  <TableHead>Telefon</TableHead>
                  <TableHead>Schüleranzahl</TableHead>
                  {isAdmin && <TableHead>Bank-ID</TableHead>}
                  <TableHead className="text-right">Aktionen</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredTeachers.map((teacher) => (
                  <TableRow key={teacher.id} className="hover:bg-gray-50">
                    <TableCell className="font-medium">{teacher.name}</TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {Array.isArray(teacher.instrument) ? (
                          teacher.instrument.length > 0 ? (
                            teacher.instrument.slice(0, 2).map((instr, index) => (
                              <Badge key={index} variant="secondary" className="bg-brand-primary/10 text-brand-primary text-xs">
                                {instr}
                              </Badge>
                            ))
                          ) : (
                            <span className="text-gray-500">-</span>
                          )
                        ) : (
                          teacher.instrument ? (
                            <Badge variant="secondary" className="bg-brand-primary/10 text-brand-primary text-xs">
                              {teacher.instrument}
                            </Badge>
                          ) : (
                            <span className="text-gray-500">-</span>
                          )
                        )}
                        {Array.isArray(teacher.instrument) && teacher.instrument.length > 2 && (
                          <Badge variant="outline" className="text-xs">
                            +{teacher.instrument.length - 2}
                          </Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell className="max-w-48 truncate">{teacher.email}</TableCell>
                    <TableCell>{teacher.phone || '-'}</TableCell>
                    <TableCell>
                      <StudentCountTooltip 
                        teacherId={teacher.id}
                        studentCount={teacher.student_count || 0}
                      />
                    </TableCell>
                    {isAdmin && (
                      <TableCell>
                        <span className="font-mono text-sm bg-gray-100 px-2 py-1 rounded">
                          {teacher.bank_id || '-'}
                        </span>
                      </TableCell>
                    )}
                    <TableCell className="text-right">
                      {canEditTeacher(teacher) && (
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
                            <DropdownMenuItem onClick={() => setEditingTeacher(teacher)}>
                              <Edit className="h-4 w-4 mr-2" />
                              Bearbeiten
                            </DropdownMenuItem>
                            {isAdmin && (
                              <DropdownMenuItem 
                                onClick={() => handleDeleteTeacher(teacher)}
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

            {filteredTeachers.length === 0 && (
              <div className="text-center py-12">
                <p className="text-gray-500">Keine Lehrer gefunden, die Ihren Kriterien entsprechen.</p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Add Teacher Dialog */}
      {isAdmin && (
        <Dialog open={showAddForm} onOpenChange={setShowAddForm}>
          <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Neuen Lehrer hinzufügen</DialogTitle>
            </DialogHeader>
            <TeacherForm
              onSuccess={() => {
                setShowAddForm(false);
                fetchTeachers();
              }}
              onCancel={() => setShowAddForm(false)}
            />
          </DialogContent>
        </Dialog>
      )}

      {/* Edit Teacher Dialog */}
      <Dialog open={!!editingTeacher} onOpenChange={() => setEditingTeacher(null)}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Lehrer bearbeiten</DialogTitle>
          </DialogHeader>
          {editingTeacher && (
            <TeacherForm
              teacher={editingTeacher}
              onSuccess={() => {
                setEditingTeacher(null);
                fetchTeachers();
              }}
              onCancel={() => setEditingTeacher(null)}
            />
          )}
        </DialogContent>
      </Dialog>

      {/* Delete Teacher Confirmation Modal */}
      {deletingTeacher && (
        <DeleteTeacherConfirmationModal
          open={!!deletingTeacher}
          onClose={() => setDeletingTeacher(null)}
          onConfirm={handleConfirmDelete}
          teacher={deletingTeacher}
          contractCount={teacherContracts[deletingTeacher.id] || 0}
        />
      )}
    </div>
  );
}