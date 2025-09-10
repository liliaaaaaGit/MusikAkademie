import { useState } from 'react';
import { supabase, Contract, ContractDiscount, generateContractPDF, PDFContractData } from '@/lib/supabase';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { AlertTriangle, Download, FileX, User, Calendar } from 'lucide-react';
import { format } from 'date-fns';
import { de } from 'date-fns/locale';
import { toast } from 'sonner';

interface DeleteContractConfirmationModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  contract: Contract;
}

export function DeleteContractConfirmationModal({
  open,
  onClose,
  onConfirm,
  contract
}: DeleteContractConfirmationModalProps) {
  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownloadPDF = async () => {
    setIsDownloading(true);
    try {
      console.log('PDF Debug - Starting PDF download...');
      
      toast.info('PDF-Download wird vorbereitet...', {
        description: `Vertrag für ${contract.student?.name} wird als PDF generiert.`
      });

      // Fetch detailed contract data with lessons if not already loaded
      let contractWithLessons = contract;
      if (!contract.lessons || contract.lessons.length === 0) {
        const { data: lessonsData, error: lessonsError } = await supabase
          .from('lessons')
          .select('*')
          .eq('contract_id', contract.id)
          .order('lesson_number');

        if (lessonsError) {
          console.error('Error fetching lessons for PDF:', lessonsError);
          toast.error('Fehler beim Laden der Stundendaten für PDF');
          return;
        }

        contractWithLessons = {
          ...contract,
          lessons: lessonsData || []
        };
      }

      // Fetch discount details if needed
      let appliedDiscounts: ContractDiscount[] = [];
      if (contract.discount_ids && contract.discount_ids.length > 0) {
        const { data: discountsData, error: discountsError } = await supabase
          .from('contract_discounts')
          .select('*')
          .in('id', contract.discount_ids);

        if (discountsError) {
          console.error('Error fetching discounts for PDF:', discountsError);
          toast.warning('Ermäßigungsdaten konnten nicht geladen werden');
        } else {
          appliedDiscounts = discountsData || [];
        }
      }

      // Prepare contract data for PDF
      let contractToExport: PDFContractData = {
        ...contractWithLessons,
        applied_discounts: appliedDiscounts
      };

      // Admin-only: fetch student and teacher bank_ids for PDF display
      // Get profile data directly since get_user_role() seems to have issues
      const { data: { user } } = await supabase.auth.getUser();
      const { data: profileData } = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user?.id)
        .single();
      
      const isAdmin = profileData?.role === 'admin';
      console.log('PDF Debug - Direct profile check:', { profileData, isAdmin });
      
      // Always fetch bank_ids for admins, regardless of what's in the contract object
      if (isAdmin) {
        // Fetch student bank_id
        const studentId = contract.student?.id;
        if (studentId) {
          const { data: studentData } = await supabase
            .from('students')
            .select('bank_id')
            .eq('id', studentId)
            .single();
          
          if (studentData) {
            contractToExport = {
              ...contractToExport,
              student: {
                ...contractToExport.student,
                bank_id: studentData.bank_id,
              } as any,
            };
            console.log('PDF Debug - Updated student bank_id:', studentData.bank_id);
          }
        }

        // Fetch teacher bank_id
        const teacherId = contract.student?.teacher?.id;
        if (teacherId) {
          const { data: teacherData } = await supabase
            .from('teachers')
            .select('bank_id')
            .eq('id', teacherId)
            .single();
          
          if (teacherData) {
            contractToExport = {
              ...contractToExport,
              student: {
                ...contractToExport.student,
                teacher: {
                  ...contractToExport.student?.teacher,
                  bank_id: teacherData.bank_id,
                } as any,
              } as any,
            };
            console.log('PDF Debug - Updated teacher bank_id:', teacherData.bank_id);
          }
        }
      }

      console.log('PDF Debug - Contract data before PDF generation:', {
        isAdmin,
        studentBankId: contractToExport.student?.bank_id,
        teacherBankId: contractToExport.student?.teacher?.bank_id,
        studentName: contractToExport.student?.name,
        teacherName: contractToExport.student?.teacher?.name,
        showBankIds: isAdmin
      });

      // Generate and download PDF (admins see bank IDs)
      await generateContractPDF(contractToExport, { showBankIds: isAdmin });
      
      toast.success('PDF erfolgreich heruntergeladen', {
        description: `Vertrag für ${contract.student?.name} wurde als PDF gespeichert.`
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

  const progress = getAttendanceProgress(contract);

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="w-full max-w-screen-lg max-h-[90vh] overflow-y-auto overflow-x-hidden p-4 md:p-6">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-red-600">
            <AlertTriangle className="h-5 w-5" />
            Vertrag löschen - Bestätigung erforderlich
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Contract Information */}
          <Card className="w-full max-w-full">
            <CardContent className="pt-6">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between mb-4 gap-2">
                <h3 className="text-lg font-medium text-gray-900">Vertragsinformationen</h3>
                <Badge variant={contract.status === 'active' ? 'default' : 'secondary'}>
                  {contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
                </Badge>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                <div className="flex items-center gap-2 min-w-0">
                  <User className="h-4 w-4 text-gray-400 flex-shrink-0" />
                  <div className="min-w-0">
                    <span className="font-medium text-gray-600">Schüler:</span>
                    <p className="break-words">{contract.student?.name}</p>
                  </div>
                </div>

                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Instrument:</span>
                  <p className="break-words">{contract.student?.instrument}</p>
                </div>

                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Typ:</span>
                  <p className="break-words">{getContractTypeDisplay(contract)}</p>
                </div>

                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Lehrer:</span>
                  <p className="break-words">{contract.student?.teacher?.name || 'Nicht zugewiesen'}</p>
                </div>

                <div className="flex items-center gap-2 min-w-0">
                  <Calendar className="h-4 w-4 text-gray-400 flex-shrink-0" />
                  <div className="min-w-0">
                    <span className="font-medium text-gray-600">Erstellt:</span>
                    <p className="break-words">{formatDate(contract.created_at)}</p>
                  </div>
                </div>

                <div>
                  <span className="font-medium text-gray-600">Fortschritt:</span>
                  <p>{contract.attendance_count}</p>
                </div>
              </div>

              {/* Progress Information */}
              <div className="mt-4 pt-4 border-t">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-gray-600">Stundenfortschritt:</span>
                  <span className="text-sm font-medium">{progress.percentage}% abgeschlossen</span>
                </div>
                <div className="w-full bg-gray-200 rounded-full h-2">
                  <div 
                    className="bg-brand-primary h-2 rounded-full transition-all duration-300"
                    style={{ width: `${progress.percentage}%` }}
                  />
                </div>
                <div className="text-xs text-gray-500 text-right mt-1">
                  {progress.current} von {progress.total} Stunden abgeschlossen
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Warning Message */}
          <Card className="border-red-200 bg-red-50 w-full max-w-full">
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <AlertTriangle className="h-5 w-5 text-red-500 mt-0.5 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-medium text-red-800">
                    Achtung: Dauerhafter Datenverlust
                  </h3>
                  <p className="text-sm text-red-700 mt-1 break-words">
                    Sie sind dabei, diesen Vertrag dauerhaft zu löschen. 
                    Möchten Sie ihn als PDF herunterladen, bevor Sie ihn löschen?
                  </p>
                  <p className="text-sm text-red-700 mt-2 font-medium">
                    Alle Stundendaten, Kommentare und der Fortschritt gehen unwiderruflich verloren!
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Data Loss Summary */}
          <Card className="border-gray-200 bg-gray-50 w-full max-w-full">
            <CardContent className="pt-6">
              <h3 className="text-sm font-medium text-gray-900 mb-3">
                Was wird gelöscht:
              </h3>
              <ul className="text-sm text-gray-700 space-y-1">
                <li>• Vertragsdaten und -konditionen</li>
                <li>• Alle {progress.total} Stundentermine und deren Status</li>
                <li>• Kommentare und Notizen zu den Stunden</li>
                <li>• Fortschrittsdaten ({progress.current}/{progress.total} abgeschlossen)</li>
                <li>• Ermäßigungen und Preisberechnungen</li>
                <li>• Verbindung zwischen Schüler und Vertrag</li>
              </ul>
            </CardContent>
          </Card>

          {/* PDF Download Recommendation */}
          <Card className="border-blue-200 bg-blue-50 w-full max-w-full">
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <Download className="h-5 w-5 text-blue-500 mt-0.5 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-medium text-blue-800">
                    Empfehlung: Vertrag als PDF sichern
                  </h3>
                  <p className="text-sm text-blue-700 mt-1 break-words">
                    Laden Sie den Vertrag als PDF herunter, um eine Kopie für Ihre Unterlagen zu behalten. 
                    Das PDF enthält alle wichtigen Informationen, Stundendaten und den aktuellen Fortschritt.
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        <DialogFooter className="flex flex-col sm:flex-row gap-3 pt-6 border-t">
          <div className="flex flex-col sm:flex-row gap-3 flex-1 order-2 sm:order-1">
            <Button
              onClick={handleDownloadPDF}
              disabled={isDownloading}
              className="bg-blue-600 hover:bg-blue-700 text-white h-11 px-6 w-full sm:flex-1"
            >
              <Download className="h-4 w-4 mr-2" />
              {isDownloading ? 'PDF wird generiert...' : 'Als PDF herunterladen'}
            </Button>
          </div>
          
          <div className="flex flex-col sm:flex-row gap-3 order-1 sm:order-2">
            <Button 
              variant="outline" 
              onClick={onClose}
              className="bg-gray-100 hover:bg-gray-200 text-gray-700 h-11 px-6 w-full sm:w-auto"
            >
              Abbrechen
            </Button>
            <Button 
              onClick={onConfirm}
              className="bg-red-600 hover:bg-red-700 text-white h-11 px-6 w-full sm:w-auto"
            >
              <FileX className="h-4 w-4 mr-2" />
              Dauerhaft löschen
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}