import { useState, useEffect } from 'react';
import { supabase, Contract } from '@/lib/supabase';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Calendar, Save, X, Clock, CheckCircle, AlertCircle, FileText, XCircle } from 'lucide-react';
import { format } from 'date-fns';
import { toast } from 'sonner';
import { useAuth } from '@/hooks/useAuth';
import { useIsMobile } from '@/hooks/useIsMobile';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';

interface LessonTrackerModalProps {
  contract: Contract;
  open: boolean;
  onClose: () => void;
  onUpdate: () => void;
}

export function LessonTrackerModal({ contract, open, onClose, onUpdate }: LessonTrackerModalProps) {
  const [lessons, setLessons] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editedLessons, setEditedLessons] = useState<Record<string, { date: string; comment: string; is_available: boolean }>>({});

  const { profile } = useAuth();
  const isMobile = useIsMobile();
  const isAdminOrTeacher = profile?.role === 'admin' || profile?.role === 'teacher';

  useEffect(() => {
    if (open && contract) {
      fetchLessons();
    }
  }, [open, contract]);

  const fetchLessons = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('lessons')
        .select('*')
        .eq('contract_id', contract.id)
        .order('lesson_number');

      if (error) {
        toast.error('Fehler beim Laden der Stunden', { description: error.message });
        return;
      }

      setLessons(data || []);
      
      // Initialize edited lessons state
      const initialEdits: Record<string, { date: string; comment: string; is_available: boolean }> = {};
      data?.forEach(lesson => {
        initialEdits[lesson.id] = {
          date: lesson.date || '',
          comment: lesson.comment || '',
          is_available: lesson.is_available ?? true
        };
      });
      setEditedLessons(initialEdits);
    } catch (error) {
      console.error('Error fetching lessons:', error);
      toast.error('Fehler beim Laden der Stunden');
    } finally {
      setLoading(false);
    }
  };

  const handleLessonChange = (lessonId: string, field: 'date' | 'comment' | 'is_available', value: string | boolean) => {
    setEditedLessons(prev => ({
      ...prev,
      [lessonId]: {
        ...prev[lessonId],
        [field]: value
      }
    }));
  };

  const handleAvailabilityToggle = (lessonId: string, isAvailable: boolean) => {
    setEditedLessons(prev => ({
      ...prev,
      [lessonId]: {
        ...prev[lessonId],
        is_available: isAvailable,
        // Clear date and comment if marking as unavailable
        date: isAvailable ? prev[lessonId].date : '',
        comment: isAvailable ? prev[lessonId].comment : ''
      }
    }));
  };

  const handleSave = async () => {
    // Blur the active element to ensure all changes are registered
    if (typeof window !== 'undefined' && document.activeElement instanceof HTMLElement) {
      document.activeElement.blur();
    }
    setSaving(true);
    try {
      // FIXED: Prepare updates with proper contract_id preservation
      const updates = Object.entries(editedLessons)
        .map(([lessonId, data]) => {
          const originalLesson = lessons.find(l => l.id === lessonId);
          if (!originalLesson) return null;
          
          // Check if there are actual changes
          const hasChanges = 
            (data.date || null) !== (originalLesson.date || null) ||
            (data.comment || null) !== (originalLesson.comment || null) ||
            data.is_available !== (originalLesson.is_available ?? true);
          
          if (!hasChanges) return null;
          
          return {
            id: lessonId,
            contract_id: originalLesson.contract_id, // FIXED: Always include contract_id
            date: data.date || null,
            comment: data.comment || null,
            is_available: data.is_available,
            updated_at: new Date().toISOString()
          };
        })
        .filter(Boolean);

      if (updates.length === 0) {
        toast.info('Keine Änderungen zu speichern');
        setSaving(false);
        return;
      }

      // FIXED: Use safe batch update function to prevent contract_id issues
      const { data: batchResult, error: batchError } = await supabase.rpc('batch_update_lessons', {
        updates: updates
      });

      if (batchError) {
        console.error('Batch update error:', batchError);
        toast.error('Fehler beim Speichern der Stunden', { 
          description: batchError.message 
            });
        setSaving(false);
        return;
          }

      // Log the batch result for debugging
      console.log('Batch update result:', batchResult);

      // FIXED: Call the enhanced sync function to ensure contract attendance is correct
        try {
        const { data: syncResult, error: syncError } = await supabase.rpc('sync_contract_data', {
            contract_id_param: contract.id
          });

        if (syncError) {
          console.error('Error syncing contract data:', syncError);
          // Log error but don't fail the operation
          await supabase.rpc('log_contract_error', {
            operation: 'lesson_tracking_sync',
            contract_id_param: contract.id,
            error_message: syncError.message
          });
        } else {
          console.log('Contract data synced:', syncResult);
          }
        } catch (error) {
        console.error('Error calling sync function:', error);
        // Log error but don't fail the operation
        await supabase.rpc('log_contract_error', {
          operation: 'lesson_tracking_sync',
          contract_id_param: contract.id,
          error_message: error instanceof Error ? error.message : 'Unknown error'
        });
        }

        // Force refresh the lessons to get updated data
        await fetchLessons();
        
      toast.success(`${updates.length} Stunde${updates.length !== 1 ? 'n' : ''} erfolgreich aktualisiert`);
        
        // Call onUpdate to refresh the parent component
        onUpdate();
        
        // Close the modal
        onClose();
    } catch (error) {
      console.error('Error updating lessons:', error);
      
      // Enhanced error reporting
      let errorMessage = 'Fehler beim Aktualisieren der Stunden';
      if (error instanceof Error) {
        errorMessage += `: ${error.message}`;
      }
      
      toast.error(errorMessage);
      
      // Log the error for debugging
      try {
        await supabase.rpc('log_contract_error', {
          operation: 'lesson_tracking_save',
          contract_id_param: contract.id,
          error_message: error instanceof Error ? error.message : 'Unknown error'
        });
      } catch (logError) {
        console.error('Error logging contract error:', logError);
      }
    } finally {
      setSaving(false);
    }
  };

  // Calculate progress based on available lessons only
  const availableLessons = lessons.filter(lesson => 
    editedLessons[lesson.id]?.is_available ?? lesson.is_available ?? true
  );
  
  const completedLessons = availableLessons.filter(lesson => 
    editedLessons[lesson.id]?.date || lesson.date
  ).length;
  
  const totalAvailableLessons = availableLessons.length;
  const progressPercentage = totalAvailableLessons > 0 ? Math.round((completedLessons / totalAvailableLessons) * 100) : 0;

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed-with-notes':
        return <CheckCircle className="h-4 w-4 text-green-600" />;
      case 'completed':
        return <CheckCircle className="h-4 w-4 text-blue-600" />;
      case 'unavailable':
        return <XCircle className="h-4 w-4 text-red-600" />;
      default:
        return <Clock className="h-4 w-4 text-gray-400" />;
    }
  };

  const getStatusBadge = (status: string) => {
    const getStatusColor = (status: string) => {
      switch (status) {
        case 'completed-with-notes':
          return 'bg-green-100 text-green-800';
        case 'completed':
          return 'bg-blue-100 text-blue-800';
        case 'unavailable':
          return 'bg-red-100 text-red-800';
        default:
          return 'bg-gray-100 text-gray-800';
      }
    };

    const getStatusDisplay = (status: string) => {
      switch (status) {
        case 'completed-with-notes':
          return 'Abgeschlossen + Notizen';
        case 'completed':
          return 'Abgeschlossen';
        case 'unavailable':
          return 'Nicht verfügbar';
        default:
          return 'Ausstehend';
      }
    };
    
    const colorClass = getStatusColor(status);
    const displayText = getStatusDisplay(status);
    
    return (
      <Badge className={`${colorClass} hover:${colorClass}`}>
        {displayText}
      </Badge>
    );
  };

  const getLessonStatus = (lesson: any) => {
    const editedData = editedLessons[lesson.id] || { 
      date: lesson.date || '', 
      comment: lesson.comment || '', 
      is_available: lesson.is_available ?? true 
    };

    if (!editedData.is_available) {
      return 'unavailable';
    }
    
    if (editedData.date) {
      return editedData.comment ? 'completed-with-notes' : 'completed';
    }
    
    return 'pending';
  };

  const getContractTypeDisplayGerman = (type: string) => {
    switch (type) {
      case 'ten_class_card':
        return '10er Karte';
      case 'half_year':
        return 'Halbjahresvertrag';
      default:
        return type;
    }
  };

  const getContractDurationGerman = (type: string) => {
    switch (type) {
      case 'ten_class_card':
        return '3 Monate';
      case 'half_year':
        return '4,5 Monate';
      default:
        return 'Unbekannt';
    }
  };

  // Mobile accordion view for Admin/Teacher
  if (isMobile && isAdminOrTeacher) {
    return (
      <Dialog open={open} onOpenChange={onClose}>
        <DialogContent className="max-w-lg w-full p-0 overflow-y-auto max-h-[80vh]">
          <div className="p-4">
            {/* Contract Overview Card (reuse structure from ContractDetailsModal) */}
            <div className="bg-white rounded-lg shadow-md border border-gray-100 p-4 mb-4">
              <div className="flex items-center justify-between mb-2">
                <div className="text-lg font-semibold truncate">{contract.student?.name || '-'}</div>
                <Badge variant={contract.status === 'active' ? 'default' : 'secondary'}>
                  {contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
                </Badge>
              </div>
              <div className="flex flex-col gap-1 text-sm">
                <div className="flex items-center gap-2">
                  <span className="font-medium">Typ:</span>
                  <span>{contract.contract_variant?.name || contract.type || '-'}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="font-medium">Instrument:</span>
                  <span>{contract.student?.instrument || '-'}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="font-medium">Lehrer:</span>
                  <span>{contract.student?.teacher?.name || '-'}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="font-medium">Fortschritt:</span>
                  <span>{contract.attendance_count || '-'}</span>
                </div>
              </div>
            </div>

            {/* Lessons Accordion */}
            <Accordion type="single" collapsible className="w-full">
              {lessons.map((lesson) => {
                const editedData = editedLessons[lesson.id] || { date: '', comment: '', is_available: true };
                const status = getLessonStatus(lesson);
                // If lesson is undefined, skip rendering
                if (!lesson) return null;
                return (
                  <AccordionItem key={lesson.id} value={lesson.id} className="mb-2 border rounded-lg">
                    <div className="flex items-center justify-between px-4 py-3">
                      <div className="flex items-center gap-2 select-none">
                        {getStatusIcon(status)}
                        <span className="font-medium">Stunde {lesson.lesson_number}</span>
                      </div>
                      <AccordionTrigger className="flex items-center gap-2 px-0 py-0 w-auto h-auto ml-2">
                        <span className="text-sm text-gray-600">{editedData.date || 'Kein Datum'}</span>
                      </AccordionTrigger>
                    </div>
                    <AccordionContent className="px-4 pb-4">
                      <div className="flex flex-col gap-3">
                        <div className="flex items-center gap-2">
                          <Checkbox
                            checked={editedData.is_available}
                            onCheckedChange={(checked) => handleAvailabilityToggle(lesson.id, checked as boolean)}
                            className="focus:ring-brand-primary"
                          />
                          <span className="text-sm text-gray-600">
                            {editedData.is_available ? 'Verfügbar' : 'Nicht verfügbar'}
                          </span>
                        </div>
                        <div>
                          <Label>Datum</Label>
                          <Input
                            type="date"
                            value={editedData.date}
                            onChange={(e) => handleLessonChange(lesson.id, 'date', e.target.value)}
                            className="w-full focus:ring-brand-primary focus:border-brand-primary"
                            max={format(new Date(), 'yyyy-MM-dd')}
                            disabled={!editedData.is_available}
                          />
                        </div>
                        <div>
                          <Label>Notizen</Label>
                          <Textarea
                            value={editedData.comment}
                            onChange={(e) => handleLessonChange(lesson.id, 'comment', e.target.value)}
                            placeholder={editedData.is_available ? "Notizen hinzufügen (z.B. Hausaufgaben gegeben, Stunde verpasst, etc.)" : "Stunde nicht verfügbar"}
                            className="min-h-[60px] resize-none focus:ring-brand-primary focus:border-brand-primary"
                            rows={2}
                            disabled={!editedData.is_available}
                          />
                        </div>
                        <div className="flex gap-2 mt-2">
                          <Button 
                            onClick={handleSave} 
                            disabled={saving || loading}
                            className="bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary w-full"
                          >
                            {saving ? 'Speichern...' : 'Speichern'}
                          </Button>
                          <Button 
                            variant="outline" 
                            onClick={onClose}
                            className="w-full"
                          >
                            Schließen
                          </Button>
                        </div>
                      </div>
                    </AccordionContent>
                  </AccordionItem>
                );
              }).filter(Boolean)}
            </Accordion>
          </div>
        </DialogContent>
      </Dialog>
    );
  }

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-6xl max-h-[95vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Calendar className="h-5 w-5" />
            Stundenverfolgung - {contract.student?.name}
          </DialogTitle>
        </DialogHeader>

        {/* Contract Overview */}
        <Card className="mb-6">
          <CardHeader>
            <CardTitle className="text-lg flex items-center justify-between">
              <span>Vertragsübersicht</span>
              <div className="flex items-center gap-2">
                <Badge variant="outline" className="text-sm">
                  {completedLessons}/{totalAvailableLessons} Stunden
                </Badge>
                <span className="text-brand-primary font-medium text-sm">
                  {progressPercentage}% abgeschlossen
                </span>
              </div>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
              <div>
                <span className="text-sm font-medium text-gray-600">Typ:</span>
                <p className="text-sm">{getContractTypeDisplayGerman(contract.type)}</p>
              </div>
              <div>
                <span className="text-sm font-medium text-gray-600">Laufzeit:</span>
                <p className="text-sm">{getContractDurationGerman(contract.type)}</p>
              </div>
              <div>
                <span className="text-sm font-medium text-gray-600">Instrument:</span>
                <p className="text-sm">{contract.student?.instrument}</p>
              </div>
              <div>
                <span className="text-sm font-medium text-gray-600">Status:</span>
                <Badge variant={contract.status === 'active' ? 'default' : 'secondary'}>
                  {contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
                </Badge>
              </div>
            </div>
            
            {/* Progress Bar */}
            <div className="w-full bg-gray-200 rounded-full h-3">
              <div 
                className="bg-brand-primary h-3 rounded-full transition-all duration-300"
                style={{ width: `${progressPercentage}%` }}
              />
            </div>
            
            {/* Progress Summary */}
            <div className="flex justify-between items-center mt-2 text-xs text-gray-600">
              <span>{completedLessons} abgeschlossen</span>
              <span>{totalAvailableLessons - completedLessons} verbleibend</span>
              <span>{lessons.length - totalAvailableLessons} nicht verfügbar</span>
            </div>
          </CardContent>
        </Card>

        {loading ? (
          <div className="flex items-center justify-center py-8">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-medium">Stundenfortschritt</h3>
              <div className="flex items-center gap-2 text-sm text-gray-600">
                <CheckCircle className="h-4 w-4 text-green-600" />
                <span>Abgeschlossen + Notizen</span>
                <CheckCircle className="h-4 w-4 text-blue-600 ml-3" />
                <span>Abgeschlossen</span>
                <Clock className="h-4 w-4 text-gray-400 ml-3" />
                <span>Ausstehend</span>
                <XCircle className="h-4 w-4 text-red-600 ml-3" />
                <span>Nicht verfügbar</span>
              </div>
            </div>

            <div className="border rounded-lg overflow-hidden">
              <Table>
                <TableHeader>
                  <TableRow className="bg-gray-50">
                    <TableHead className="w-20">Stunde #</TableHead>
                    <TableHead className="w-32">Verfügbar</TableHead>
                    <TableHead className="w-40">Datum</TableHead>
                    <TableHead>Kommentare/Notizen</TableHead>
                    <TableHead className="w-40">Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {lessons.map((lesson) => {
                    const editedData = editedLessons[lesson.id] || { 
                      date: '', 
                      comment: '', 
                      is_available: true 
                    };
                    const status = getLessonStatus(lesson);
                    
                    return (
                      <TableRow key={lesson.id} className={`hover:bg-gray-50 ${!editedData.is_available ? 'opacity-60' : ''}`}>
                        <TableCell className="font-medium flex items-center gap-2">
                          {getStatusIcon(status)}
                          {lesson.lesson_number}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center space-x-2">
                            <Checkbox
                              checked={editedData.is_available}
                              onCheckedChange={(checked) => 
                                handleAvailabilityToggle(lesson.id, checked as boolean)
                              }
                              className="focus:ring-brand-primary"
                            />
                            <span className="text-sm text-gray-600">
                              {editedData.is_available ? 'Verfügbar' : 'Nicht verfügbar'}
                            </span>
                          </div>
                        </TableCell>
                        <TableCell>
                          <Input
                            type="date"
                            value={editedData.date}
                            onChange={(e) => handleLessonChange(lesson.id, 'date', e.target.value)}
                            className="w-full focus:ring-brand-primary focus:border-brand-primary"
                            max={format(new Date(), 'yyyy-MM-dd')}
                            disabled={!editedData.is_available}
                          />
                        </TableCell>
                        <TableCell>
                          <Textarea
                            value={editedData.comment}
                            onChange={(e) => handleLessonChange(lesson.id, 'comment', e.target.value)}
                            placeholder={editedData.is_available ? "Notizen hinzufügen (z.B. Hausaufgaben gegeben, Stunde verpasst, etc.)" : "Stunde nicht verfügbar"}
                            className="min-h-[60px] resize-none focus:ring-brand-primary focus:border-brand-primary"
                            rows={2}
                            disabled={!editedData.is_available}
                          />
                        </TableCell>
                        <TableCell>
                          {getStatusBadge(status)}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>

            {lessons.length === 0 && (
              <div className="text-center py-8">
                <AlertCircle className="h-12 w-12 text-gray-300 mx-auto mb-4" />
                <p className="text-gray-500">Keine Stunden für diesen Vertrag gefunden.</p>
              </div>
            )}
          </div>
        )}

        <DialogFooter className="flex justify-between items-center pt-6 border-t">
          <div className="flex items-center gap-4 text-sm text-gray-600">
            <div className="flex items-center gap-1">
              <FileText className="h-4 w-4" />
              <span>Vertrag: {getContractTypeDisplayGerman(contract.type)}</span>
            </div>
            <div className="flex items-center gap-1">
              <Calendar className="h-4 w-4" />
              <span>Gültig für: {getContractDurationGerman(contract.type)}</span>
            </div>
          </div>
          <div className="flex gap-2">
            <Button 
              variant="outline" 
              onClick={onClose}
              className="bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray focus:ring-brand-primary"
            >
              <X className="h-4 w-4 mr-2" />
              Abbrechen
            </Button>
            <Button 
              onClick={handleSave} 
              disabled={saving || loading}
              className="bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
            >
              <Save className="h-4 w-4 mr-2" />
              {saving ? 'Speichern...' : 'Fortschritt speichern'}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}