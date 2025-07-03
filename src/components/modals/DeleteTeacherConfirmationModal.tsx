import { Teacher } from '@/lib/supabase';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { AlertTriangle, UserX, FileText, ExternalLink } from 'lucide-react';

interface DeleteTeacherConfirmationModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  teacher: Teacher;
  contractCount?: number;
}

export function DeleteTeacherConfirmationModal({
  open,
  onClose,
  onConfirm,
  teacher,
  contractCount = 0
}: DeleteTeacherConfirmationModalProps) {

  const getInstrumentDisplay = (instrument: string | string[]) => {
    if (Array.isArray(instrument)) {
      return instrument.length > 0 ? instrument.join(', ') : '-';
    }
    return instrument || '-';
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="w-full max-w-screen-lg max-h-[90vh] overflow-y-auto overflow-x-hidden p-4 md:p-6">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-red-600">
            <AlertTriangle className="h-5 w-5" />
            Lehrer löschen - Bestätigung erforderlich
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Teacher Information */}
          <Card className="w-full max-w-full">
            <CardContent className="pt-6">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between mb-4 gap-2">
                <h3 className="text-lg font-medium text-gray-900">Lehrerinformationen</h3>
                <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200 w-fit">
                  {teacher.student_count || 0} Schüler
                </Badge>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Name:</span>
                  <p className="break-words">{teacher.name}</p>
                </div>
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">E-Mail:</span>
                  <p className="break-all">{teacher.email}</p>
                </div>
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Instrumente:</span>
                  <p className="break-words">{getInstrumentDisplay(teacher.instrument)}</p>
                </div>
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Bank-ID:</span>
                  <p className="font-mono break-all">{teacher.bank_id}</p>
                </div>
                <div className="min-w-0">
                  <span className="font-medium text-gray-600">Telefon:</span>
                  <p className="break-words">{teacher.phone || 'Nicht angegeben'}</p>
                </div>
                <div>
                  <span className="font-medium text-gray-600">Zugewiesene Schüler:</span>
                  <p>{teacher.student_count || 0}</p>
                </div>
              </div>

              {contractCount > 0 && (
                <div className="mt-4 pt-4 border-t">
                  <div className="flex items-center gap-2">
                    <FileText className="h-4 w-4 text-gray-500" />
                    <span className="text-sm font-medium text-gray-900">
                      {contractCount} zugehörige Verträge gefunden
                    </span>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Warning Message */}
          <Card className="border-red-200 bg-red-50 w-full max-w-full">
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <AlertTriangle className="h-5 w-5 text-red-500 mt-0.5 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-medium text-red-800">
                    Achtung: Irreversible Aktion
                  </h3>
                  <p className="text-sm text-red-700 mt-1 break-words">
                    Das Löschen dieses Lehrers löscht auch alle zugehörigen Verträge. 
                    Diese Aktion ist irreversibel.
                  </p>
                  {contractCount > 0 && (
                    <p className="text-sm text-red-700 mt-2 font-medium">
                      {contractCount} Vertrag{contractCount !== 1 ? 'e' : ''} wird/werden ebenfalls gelöscht!
                    </p>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Recommendation for Contract Downloads */}
          {contractCount > 0 && (
            <Card className="border-orange-200 bg-orange-50 w-full max-w-full">
              <CardContent className="pt-6">
                <div className="flex items-start space-x-3">
                  <ExternalLink className="h-5 w-5 text-orange-500 mt-0.5 flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <h3 className="text-sm font-medium text-orange-800">
                      Empfehlung: Verträge sichern
                    </h3>
                    <p className="text-sm text-orange-700 mt-1 break-words">
                      Verträge können hier nicht in großen Mengen heruntergeladen werden. 
                      Es wird empfohlen, die Vertragsübersicht zu besuchen und wichtige 
                      Verträge als PDF herunterzuladen, bevor Sie fortfahren.
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}

          {/* Impact Summary */}
          <Card className="border-gray-200 bg-gray-50 w-full max-w-full">
            <CardContent className="pt-6">
              <h3 className="text-sm font-medium text-gray-900 mb-3">
                Auswirkungen dieser Aktion:
              </h3>
              <ul className="text-sm text-gray-700 space-y-1">
                <li>• Lehrerprofil wird dauerhaft gelöscht</li>
                <li>• {teacher.student_count || 0} Schüler verlieren ihre Lehrerzuweisung</li>
                {contractCount > 0 && (
                  <li>• {contractCount} Vertrag{contractCount !== 1 ? 'e' : ''} wird/werden gelöscht</li>
                )}
                <li>• Alle Stundendaten und Kommentare gehen verloren</li>
                <li>• Diese Aktion kann nicht rückgängig gemacht werden</li>
              </ul>
            </CardContent>
          </Card>
        </div>

        <DialogFooter className="flex flex-col sm:flex-row gap-3 pt-6 border-t">
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
            <UserX className="h-4 w-4 mr-2" />
            Löschen fortsetzen
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}