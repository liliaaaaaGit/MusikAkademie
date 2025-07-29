import { useState } from 'react';
import { supabase, Student, Contract, ContractDiscount, generateContractPDF, PDFContractData } from '@/lib/supabase';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { AlertTriangle, Download, UserX, UserCheck, User, FileText } from 'lucide-react';
import { format } from 'date-fns';
import { de } from 'date-fns/locale';
import { toast } from 'sonner';

interface DeleteStudentConfirmationModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  onMarkInactive: () => void;
  student: Student;
}

export function DeleteStudentConfirmationModal({
  open,
  onClose,
  onConfirm,
  onMarkInactive,
  student
}: DeleteStudentConfirmationModalProps) {
  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownloadPDF = async () => {
    if (!student.contract) {
      toast.error('Kein Vertrag für diesen Schüler gefunden');
      return;
    }

    setIsDownloading(true);
    try {
      toast.info('PDF-Download wird vorbereitet...', {
        description: `Vertrag für ${student.name} wird als PDF generiert.`
      });

      // Fetch detailed contract data with lessons and discounts
      const { data: contractData, error: contractError } = await supabase
        .from('contracts')
        .select(`
          *,
          student:students!fk_contracts_student_id(
            id, name, instrument, 
            teacher:teachers(id, name, bank_id)
          ),
          contract_variant:contract_variants(
            id, name, duration_months, group_type, session_length_minutes, total_lessons, monthly_price, one_time_price,
            contract_category:contract_categories(id, name, display_name)
          ),
          lessons:lessons(id, lesson_number, date, is_available, comment)
        `)
        .eq('id', student.contract.id)
        .single();

      if (contractError) {
        toast.error('Fehler beim Laden der Vertragsdaten', { description: contractError.message });
        return;
      }

      // Fetch discount details if needed
      let appliedDiscounts: ContractDiscount[] = [];
      if (contractData.discount_ids && contractData.discount_ids.length > 0) {
        const { data: discountsData, error: discountsError } = await supabase
          .from('contract_discounts')
          .select('*')
          .in('id', contractData.discount_ids);

        if (discountsError) {
          console.error('Error fetching discounts for PDF:', discountsError);
          toast.warning('Ermäßigungsdaten konnten nicht geladen werden');
        } else {
          appliedDiscounts = discountsData || [];
        }
      }

      // Prepare contract data for PDF
      const contractToExport: PDFContractData = {
        ...contractData,
        applied_discounts: appliedDiscounts
      };

      // Generate and download PDF
      await generateContractPDF(contractToExport);
      
      toast.success('PDF erfolgreich heruntergeladen', {
        description: `Vertrag für ${student.name} wurde als PDF gespeichert.`
      });
      
    } catch (error) {
      console.error('Error downloading PDF:', error);
      toast.error('PDF konnte nicht generiert werden. Bitte erneut versuchen.');
    } finally {
      setIsDownloading(false);
    }
  };

  const getContractTypeDisplay = (contract: Contract) => {
    if (contract.contract_variant) {
      return contract.contract_variant.name;
    }
    
    // Fallback to legacy type system
    switch (contract.type) {
      case 'ten_class_card':
        return '10er Karte';
      case 'half_year':
        return 'Halbjahresvertrag';
      default:
        return contract.type;
    }
  };

  const getAttendanceProgress = (contract: Contract) => {
    const [current, total] = contract.attendance_count.split('/').map(Number);
    return { current, total, percentage: Math.round((current / total) * 100) };
  };

  const formatDate = (dateString: string) => {
    if (!dateString) return 'Unbekannt';
    
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'Ungültiges Datum';
    
    return format(date, 'dd.MM.yyyy', { locale: de });
  };

  const progress = student.contract ? getAttendanceProgress(student.contract) : null;

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="w-full max-w-screen-lg max-h-[90vh] overflow-y-auto overflow-x-hidden p-4 md:p-6">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-red-600">
            <AlertTriangle className="h-5 w-5" />
            Schüler löschen - Bestätigung erforderlich
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Student Information */}
          <Card className="bg-gray-50 border-gray-200 w-full max-w-full">
            <CardContent className="pt-6">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between mb-4 gap-2">
                <div className="flex items-center gap-2">
                  <User className="h-5 w-5 text-gray-600" />
                  <h3 className="text-lg font-medium text-gray-900">Schülerinformationen</h3>
                </div>
                <Badge variant={student.status === 'active' ? 'default' : 'secondary'}>
                  {student.status === 'active' ? 'Aktiv' : 'Inaktiv'}
                </Badge>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Name:</span>
                  <p className="text-gray-900 break-words">{student.name}</p>
                </div>
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Instrument:</span>
                  <p className="text-gray-900 break-words">{student.instrument}</p>
                </div>
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Lehrer:</span>
                  <p className="text-gray-900 break-words">{student.teacher?.name || 'Nicht zugewiesen'}</p>
                </div>
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Bank-ID:</span>
                  <p className="font-mono text-gray-900 break-all">{student.bank_id}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Contract Overview */}
          {student.contract && (
            <Card className="bg-blue-50 border-blue-200 w-full max-w-full">
              <CardContent className="pt-6">
                <div className="flex items-center gap-2 mb-4">
                  <FileText className="h-5 w-5 text-blue-600" />
                  <h3 className="text-lg font-medium text-gray-900">Zugehöriger Vertrag</h3>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm mb-4">
                  <div className="min-w-0">
                    <span className="font-medium text-gray-600">Typ:</span>
                    <p className="text-gray-900 break-words">{getContractTypeDisplay(student.contract)}</p>
                  </div>
                  <div>
                    <span className="font-medium text-gray-600">Status:</span>
                    <div className="mt-1">
                      <Badge variant={student.contract.status === 'active' ? 'default' : 'secondary'}>
                        {student.contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
                      </Badge>
                    </div>
                  </div>
                  <div className="min-w-0">
                    <span className="font-medium text-gray-600">Erstellt:</span>
                    <p className="text-gray-900 break-words">
                      {formatDate(student.contract.created_at)}
                    </p>
                  </div>
                  <div className="min-w-0">
                    <span className="font-medium text-gray-600">Fortschritt:</span>
                    <p className="text-gray-900">{student.contract.attendance_count}</p>
                  </div>
                </div>

                {/* Progress Bar */}
                {progress && (
                  <div className="space-y-2">
                    <div className="flex items-center justify-between text-sm">
                      <span className="font-medium text-gray-600">Stundenfortschritt:</span>
                      <span className="font-medium text-blue-600">{progress.percentage}% abgeschlossen</span>
                    </div>
                    <div className="w-full bg-gray-200 rounded-full h-2">
                      <div 
                        className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                        style={{ width: `${progress.percentage}%` }}
                      />
                    </div>
                    <div className="text-xs text-gray-500 text-right">
                      {progress.current} von {progress.total} Stunden abgeschlossen
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {/* Red Warning Box */}
          <Card className="border-red-200 w-full max-w-full" style={{ backgroundColor: '#FEE2E2' }}>
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <AlertTriangle className="h-5 w-5 text-red-500 mt-0.5 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-bold text-red-800">
                    Achtung: Irreversible Aktion
                  </h3>
                  <p className="text-sm text-red-700 mt-2 break-words">
                    Das Löschen dieses Schülers löscht auch alle zugehörigen Verträge. 
                    Möchten Sie den Schüler stattdessen als inaktiv markieren?
                  </p>
                  <p className="text-sm text-red-700 mt-2 font-bold">
                    Diese Aktion kann nicht rückgängig gemacht werden!
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Suggestion Box (Inaktiv) */}
          <Card className="border-green-200 bg-green-50 w-full max-w-full">
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <UserCheck className="h-5 w-5 text-green-600 mt-0.5 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-bold text-green-800">
                    Empfehlung: Als inaktiv markieren
                  </h3>
                  <p className="text-sm text-green-700 mt-2 break-words">
                    Anstatt den Schüler zu löschen, können Sie ihn als "inaktiv" markieren. 
                    Dadurch bleiben alle Daten erhalten, aber der Schüler wird nicht mehr in aktiven Listen angezeigt.
                  </p>
                  <p className="text-sm text-green-700 mt-2 font-medium">
                    Diese Option ist reversibel und schützt Ihre Daten.
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Action Buttons Row */}
        <DialogFooter className="flex flex-col sm:flex-row gap-3 pt-6 border-t">
          <div className="flex flex-col sm:flex-row gap-3 flex-1 order-2 sm:order-1">
            <Button
              onClick={onMarkInactive}
              className="bg-green-600 hover:bg-green-700 text-white w-full sm:flex-1 h-11 px-6"
            >
              <UserCheck className="h-4 w-4 mr-2" />
              Als inaktiv markieren
            </Button>
            
            {student.contract && (
              <Button
                onClick={handleDownloadPDF}
                disabled={isDownloading}
                variant="outline"
                className="bg-blue-50 hover:bg-blue-100 text-blue-700 border-blue-200 w-full sm:flex-1 h-11 px-6"
              >
                <Download className="h-4 w-4 mr-2" />
                {isDownloading ? 'PDF wird generiert...' : 'Vertrag als PDF herunterladen'}
              </Button>
            )}
          </div>
          
          <div className="flex flex-col sm:flex-row gap-3 order-1 sm:order-2">
            <Button 
              variant="outline" 
              onClick={onClose}
              className="bg-gray-100 hover:bg-gray-200 text-gray-700 border-gray-300 h-11 px-6 w-full sm:w-auto"
            >
              Abbrechen
            </Button>
            <Button 
              onClick={onConfirm}
              className="bg-red-600 hover:bg-red-700 text-white h-11 px-6 w-full sm:w-auto"
            >
              <UserX className="h-4 w-4 mr-2" />
              Löschen fortsetzen (Irreversibel)
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}