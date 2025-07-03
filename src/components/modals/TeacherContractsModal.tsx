import { useState, useEffect } from 'react';
import { supabase, Contract, Teacher } from '@/lib/supabase';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Calendar, FileText, User, Clock } from 'lucide-react';
import { LessonTrackerModal } from './LessonTrackerModal';
import { toast } from 'sonner';

interface TeacherContractsModalProps {
  teacher: Teacher;
  open: boolean;
  onClose: () => void;
}

export function TeacherContractsModal({ teacher, open, onClose }: TeacherContractsModalProps) {
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [loading, setLoading] = useState(false);
  const [selectedContract, setSelectedContract] = useState<Contract | null>(null);

  useEffect(() => {
    if (open && teacher) {
      fetchTeacherContracts();
    }
  }, [open, teacher]);

  const fetchTeacherContracts = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('contracts')
        .select(`
          *,
          student:students!fk_contracts_student_id(id, name, instrument, email, phone)
        `)
        .eq('students.teacher_id', teacher.id)
        .order('created_at', { ascending: false });

      if (error) {
        toast.error('Fehler beim Laden der Verträge', { description: error.message });
        return;
      }

      setContracts(data || []);
    } catch (error) {
      console.error('Error fetching teacher contracts:', error);
      toast.error('Fehler beim Laden der Verträge');
    } finally {
      setLoading(false);
    }
  };

  const getContractTypeDisplay = (type: string) => {
    switch (type) {
      case 'ten_class_card':
        return '10er Karte';
      case 'half_year':
        return 'Halbjahresvertrag';
      default:
        return type;
    }
  };

  const getAttendanceProgress = (attendanceCount: string) => {
    const [current, total] = attendanceCount.split('/').map(Number);
    return { current, total, percentage: Math.round((current / total) * 100) };
  };

  const formatDate = (dateString: string) => {
    if (!dateString) return 'Unbekannt';
    
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'Ungültiges Datum';
    
    return date.toLocaleDateString('de-DE');
  };

  return (
    <>
      <Dialog open={open} onOpenChange={onClose}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <User className="h-5 w-5" />
              {teacher.name} - Schülerverträge
            </DialogTitle>
            <div className="text-sm text-gray-600">
              {contracts.length} Vertrag{contracts.length !== 1 ? 'e' : ''} gefunden
            </div>
          </DialogHeader>

          {loading ? (
            <div className="flex items-center justify-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
            </div>
          ) : (
            <div className="space-y-4">
              {contracts.length > 0 ? (
                <div className="grid gap-4 md:grid-cols-2">
                  {contracts.map((contract) => {
                    const progress = getAttendanceProgress(contract.attendance_count);
                    
                    return (
                      <Card key={contract.id} className="hover:shadow-md transition-shadow">
                        <CardHeader className="pb-3">
                          <CardTitle className="text-lg flex items-center justify-between">
                            <span>{contract.student?.name}</span>
                            <Badge 
                              variant={contract.status === 'active' ? 'default' : 'secondary'}
                              className={contract.status === 'active' ? 'bg-green-100 text-green-800' : ''}
                            >
                              {contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
                            </Badge>
                          </CardTitle>
                        </CardHeader>
                        <CardContent className="space-y-3">
                          <div className="flex items-center justify-between text-sm">
                            <span className="text-gray-600">Typ:</span>
                            <Badge variant="outline">
                              {getContractTypeDisplay(contract.type)}
                            </Badge>
                          </div>
                          
                          <div className="flex items-center justify-between text-sm">
                            <span className="text-gray-600">Instrument:</span>
                            <span>{contract.student?.instrument}</span>
                          </div>
                          
                          <div className="space-y-2">
                            <div className="flex items-center justify-between text-sm">
                              <span className="text-gray-600">Fortschritt:</span>
                              <span className="font-medium">{contract.attendance_count}</span>
                            </div>
                            <div className="w-full bg-gray-200 rounded-full h-2">
                              <div 
                                className="bg-brand-primary h-2 rounded-full transition-all duration-300"
                                style={{ width: `${progress.percentage}%` }}
                              />
                            </div>
                            <div className="text-xs text-gray-500 text-right">
                              {progress.percentage}% abgeschlossen
                            </div>
                          </div>

                          <div className="flex items-center justify-between text-sm">
                            <span className="text-gray-600">Erstellt:</span>
                            <span>{formatDate(contract.created_at)}</span>
                          </div>

                          <div className="pt-2 border-t">
                            <Button
                              onClick={() => setSelectedContract(contract)}
                              className="w-full bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
                              size="sm"
                            >
                              <Calendar className="h-4 w-4 mr-2" />
                              Stunden verfolgen
                            </Button>
                          </div>
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              ) : (
                <div className="text-center py-8">
                  <FileText className="h-12 w-12 text-gray-300 mx-auto mb-4" />
                  <p className="text-gray-500">Keine Verträge für diesen Lehrer gefunden.</p>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Lesson Tracker Modal */}
      {selectedContract && (
        <LessonTrackerModal
          contract={selectedContract}
          open={!!selectedContract}
          onClose={() => setSelectedContract(null)}
          onUpdate={fetchTeacherContracts}
        />
      )}
    </>
  );
}