import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { AlertTriangle, Download, FileText, Calendar, User } from 'lucide-react';
import { supabase, Contract, ContractDiscount, generateContractPDF, PDFContractData } from '@/lib/supabase';
import { format } from 'date-fns';
import { de } from 'date-fns/locale';
import { toast } from 'sonner';

interface ReplaceContractConfirmationModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  contractToReplace: Contract & {
    lessons?: any[];
    applied_discounts?: ContractDiscount[];
  };
}

export function ReplaceContractConfirmationModal({
  open,
  onClose,
  onConfirm,
  contractToReplace
}: ReplaceContractConfirmationModalProps) {
  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownloadPDF = async () => {
    setIsDownloading(true);
    try {
      toast.info('PDF-Download wird vorbereitet...', {
        description: `Vertrag für ${contractToReplace.student?.name} wird als PDF generiert.`
      });

      // Prepare contract data for PDF with all required information
      const contractToExport: PDFContractData = {
        ...contractToReplace,
        applied_discounts: contractToReplace.applied_discounts || []
      };

      // Generate and download PDF (admins see bank IDs)
      const { data: roleResult } = await supabase.rpc('get_user_role');
      const isAdmin = roleResult === 'admin';
      await generateContractPDF(contractToExport, { showBankIds: isAdmin });
      
      toast.success('PDF erfolgreich heruntergeladen', {
        description: `Vertrag für ${contractToReplace.student?.name} wurde als PDF gespeichert.`
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

  const getContractPriceDisplay = (contract: Contract) => {
    if (contract.final_price && contract.payment_type) {
      return contract.payment_type === 'monthly' 
        ? `${contract.final_price.toFixed(2)}€ / Monat`
        : `${contract.final_price.toFixed(2)}€ einmalig`;
    }

    if (contract.contract_variant) {
      if (contract.contract_variant.monthly_price) {
        return `${contract.contract_variant.monthly_price.toFixed(2)}€ / Monat`;
      } else if (contract.contract_variant.one_time_price) {
        return `${contract.contract_variant.one_time_price.toFixed(2)}€ einmalig`;
      }
    }

    return 'Preis nicht verfügbar';
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

  const progress = getAttendanceProgress(contractToReplace);

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-hidden flex flex-col">
        <DialogHeader className="flex-shrink-0">
          <DialogTitle className="flex items-center gap-2 text-orange-600">
            <AlertTriangle className="h-5 w-5" />
            Bestehenden Vertrag ersetzen
          </DialogTitle>
        </DialogHeader>

        {/* Scrollable content area */}
        <div className="flex-1 overflow-y-auto space-y-6 pr-2">
          {/* Current Contract Details - Moved to top */}
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-medium text-gray-900">Aktueller Vertrag</h3>
                <Badge variant={contractToReplace.status === 'active' ? 'default' : 'secondary'}>
                  {contractToReplace.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
                </Badge>
              </div>

              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="flex items-center gap-2">
                  <User className="h-4 w-4 text-gray-400" />
                  <div>
                    <span className="font-medium text-gray-600">Schüler:</span>
                    <p>{contractToReplace.student?.name}</p>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <FileText className="h-4 w-4 text-gray-400" />
                  <div>
                    <span className="font-medium text-gray-600">Typ:</span>
                    <p>{getContractTypeDisplay(contractToReplace)}</p>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <Calendar className="h-4 w-4 text-gray-400" />
                  <div>
                    <span className="font-medium text-gray-600">Erstellt:</span>
                    <p>{formatDate(contractToReplace.created_at)}</p>
                  </div>
                </div>

                <div>
                  <span className="font-medium text-gray-600">Preis:</span>
                  <p className="text-brand-primary font-medium">{getContractPriceDisplay(contractToReplace)}</p>
                </div>

                {/* Show discount information if available */}
                {(contractToReplace.custom_discount_percent && contractToReplace.custom_discount_percent > 0) && (
                  <div className="col-span-2">
                    <span className="font-medium text-gray-600">Ermäßigung:</span>
                    <div className="flex items-center gap-2 mt-1">
                      <Badge variant="outline" className="text-xs bg-green-50 text-green-700 border-green-200">
                        Custom: -{contractToReplace.custom_discount_percent}%
                      </Badge>
                      <span className="text-xs text-gray-500">manuell zugewiesen</span>
                    </div>
                  </div>
                )}
              </div>

              {/* Progress Information */}
              <div className="mt-4 pt-4 border-t">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-gray-600">Fortschritt:</span>
                  <span className="text-sm font-medium">{contractToReplace.attendance_count}</span>
                </div>
                <div className="w-full bg-gray-200 rounded-full h-2">
                  <div 
                    className="bg-brand-primary h-2 rounded-full transition-all duration-300"
                    style={{ width: `${progress.percentage}%` }}
                  />
                </div>
                <div className="text-xs text-gray-500 text-right mt-1">
                  {progress.percentage}% abgeschlossen
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Warning Messages - Grouped together */}
          <div className="space-y-4">
            {/* Warning Message */}
            <Card className="border-orange-200 bg-orange-50">
              <CardContent className="pt-6">
                <div className="flex items-start space-x-3">
                  <AlertTriangle className="h-5 w-5 text-orange-500 mt-0.5" />
                  <div>
                    <h3 className="text-sm font-medium text-orange-800">
                      Achtung: Bestehender Vertrag wird ersetzt
                    </h3>
                    <p className="text-sm text-orange-700 mt-1">
                      Der Schüler <strong>{contractToReplace.student?.name}</strong> hat bereits einen aktiven Vertrag. 
                      Das Erstellen eines neuen Vertrags wird den bestehenden Vertrag permanent löschen.
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Data Loss Warning */}
            <Card className="border-red-200 bg-red-50">
              <CardContent className="pt-6">
                <div className="flex items-start space-x-3">
                  <AlertTriangle className="h-5 w-5 text-red-500 mt-0.5" />
                  <div>
                    <h3 className="text-sm font-medium text-red-800">
                      Wichtiger Hinweis
                    </h3>
                    <p className="text-sm text-red-700 mt-1">
                      Durch das Fortfahren wird der bestehende Vertrag unwiderruflich gelöscht. 
                      Alle Stundendaten, Kommentare und der Fortschritt gehen verloren. 
                      Diese Aktion kann nicht rückgängig gemacht werden.
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* PDF Download Recommendation - Moved to bottom */}
          <Card className="border-gray-200 bg-gray-50">
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <Download className="h-5 w-5 text-gray-500 mt-0.5" />
                <div className="flex-1">
                  <h3 className="text-sm font-medium text-gray-800">
                    Empfehlung: Vertrag als PDF speichern
                  </h3>
                  <p className="text-sm text-gray-700 mt-1">
                    Wir empfehlen Ihnen, den aktuellen Vertrag vor dem Ersetzen als PDF herunterzuladen, 
                    um eine Kopie für Ihre Unterlagen zu behalten.
                  </p>
                  <Button
                    onClick={handleDownloadPDF}
                    disabled={isDownloading}
                    variant="outline"
                    size="sm"
                    className="mt-3 bg-white hover:bg-gray-50 text-gray-700 border-gray-200"
                  >
                    <Download className="h-4 w-4 mr-2" />
                    {isDownloading ? 'PDF wird generiert...' : 'Vertrag als PDF herunterladen'}
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        <DialogFooter className="flex-shrink-0 flex justify-between items-center pt-6 border-t">
          <Button 
            variant="outline" 
            onClick={onClose}
            className="bg-gray-100 hover:bg-gray-200 text-gray-700 border-gray-300"
          >
            Abbrechen
          </Button>
          <Button 
            onClick={onConfirm}
            className="bg-red-600 hover:bg-red-700 text-white"
          >
            Vertrag ersetzen
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}