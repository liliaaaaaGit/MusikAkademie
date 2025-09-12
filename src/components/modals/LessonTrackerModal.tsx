import { useState, useEffect, useRef } from 'react';
import { supabase, Contract, getContractDuration } from '@/lib/supabase';
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
import { fmtDate, fmtRange } from '@/lib/utils';
import { updateContractNotes } from '@/lib/actions/contractNotes';

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
  
  // Private notes stable local state (no remounting)
  const [privateNotes, setPrivateNotes] = useState<string>('');
  const initializedRef = useRef(false);

  const { profile } = useAuth();
  const isMobile = useIsMobile();
  const isAdminOrTeacher = profile?.role === 'admin' || profile?.role === 'teacher';

  useEffect(() => {
    if (open && contract) {
      fetchLessons();
      // Initialize notes from contract data only once per modal open
      if (!initializedRef.current) {
        setPrivateNotes(contract.private_notes || '');
        initializedRef.current = true;
      }
    }
    
    // Reset initialization flag when modal closes
    if (!open) {
      initializedRef.current = false;
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
        // Only clear date if marking as unavailable; keep notes editable
        date: isAvailable ? prev[lessonId].date : '',
        comment: prev[lessonId].comment
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
      let hasNotesChanges = false;
      
      // 1. Save private notes first (if changed and user is admin/teacher)
      if (isAdminOrTeacher && privateNotes !== (contract.private_notes || '')) {
        hasNotesChanges = true;
        try {
          await updateContractNotes(contract.id, privateNotes);
        } catch (error) {
          console.error('Error saving private notes:', error);
          toast.error('Fehler beim Speichern der Notizen');
          setSaving(false);
          return;
        }
      }

      // 2. Prepare lesson updates with proper contract_id preservation
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

      // Check if there are any changes to save
      if (updates.length === 0 && !hasNotesChanges) {
        toast.info('Keine Änderungen zu speichern');
        setSaving(false);
        return;
      }

      // 3. Use safe batch update function to prevent contract_id issues
      if (updates.length > 0) {
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

        // Check if the batch update was successful
        if (batchResult && batchResult.success) {
          // Check if contract should be marked as completed
          try {
            const { data: completionResult, error: completionError } = await supabase.rpc('check_contract_completion_after_lessons', {
              contract_id_param: contract.id
            });

            if (completionError) {
              console.error('Error checking contract completion:', completionError);
            } else {
              console.log('Contract completion check result:', completionResult);
            }
          } catch (error) {
            console.error('Error calling contract completion check:', error);
          }

          // Force refresh the lessons to get updated data
          await fetchLessons();
        } else {
          // Handle batch update failure
          const errorMessage = batchResult?.errors?.join(', ') || 'Unbekannter Fehler beim Speichern';
          toast.error(`Fehler beim Speichern: ${errorMessage}`);
          console.error('Batch update failed:', batchResult);
          setSaving(false);
          return;
        }
      }
      
      // Show success message
      if (hasNotesChanges && updates.length > 0) {
        toast.success('Notizen und Stunden erfolgreich aktualisiert');
      } else if (hasNotesChanges) {
        toast.success('Notizen erfolgreich gespeichert');
      } else {
        toast.success(`${updates.length} Stunde${updates.length !== 1 ? 'n' : ''} erfolgreich aktualisiert`);
      }
      
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
        return <CheckCircle className="h-4 w-4 text-green-600" />;
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
          return 'bg-green-100 text-green-800';
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

  const getContractTypeDisplayUnified = (c: Contract) => {
    if (c.contract_variant?.name) return c.contract_variant.name;
    // Legacy fallback
    switch (c.type) {
      case 'ten_class_card':
        return '10er Karte';
      case 'half_year':
        return 'Halbjahresvertrag';
      default:
        return c.type || '-';
    }
  };

  const getContractDurationUnified = (c: Contract) => {
    if (c.contract_variant) return getContractDuration(c.contract_variant);
    // Legacy fallback
    switch (c.type) {
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
        <DialogContent className="w-screen h-[100svh] max-w-none p-0 rounded-none overflow-hidden md:rounded-lg md:max-w-6xl md:h-auto">
          {/* Sticky header */}
          <div className="sticky top-0 z-20 bg-white/95 backdrop-blur border-b">
            <div className="px-4 py-3 flex items-center justify-between">
              <div className="text-base font-semibold truncate">Stundenverfolgung – {contract.student?.name || '-'}</div>
              <Badge variant={contract.status === 'active' ? 'default' : 'secondary'}>
                {contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
              </Badge>
            </div>
          </div>

          {/* Scrollable body */}
          <div className="flex flex-col h-[calc(100svh-0px)] md:h-auto">
            <div className="flex-1 overflow-y-auto px-4 pt-4 pb-24">
              {/* Contract Overview Card (compact) */}
              <div className="bg-white rounded-lg shadow-sm border border-gray-100 p-4 mb-4">
                <div className="grid grid-cols-2 gap-3 text-sm">
                  <div>
                    <span className="font-medium">Typ:</span>{' '}
                    <span>{contract.contract_variant?.name || contract.type || '-'}</span>
                  </div>
                  <div>
                    <span className="font-medium">Instrument:</span>{' '}
                    <span>{contract.student?.instrument || '-'}</span>
                  </div>
                  <div>
                    <span className="font-medium">Lehrer:</span>{' '}
                    <span>{contract.student?.teacher?.name || '-'}</span>
                  </div>
                  <div>
                    <span className="font-medium">Fortschritt:</span>{' '}
                    <span>{contract.attendance_count || '-'}</span>
                  </div>
                </div>
              </div>

              {/* Private Notes Panel - INLINED */}
              {isAdminOrTeacher && (
                <Card className="mb-6">
                  <CardHeader>
                    <CardTitle className="text-lg">
                      Notizen (nur intern)
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <Textarea
                      value={privateNotes}
                      onChange={(e) => setPrivateNotes(e.target.value)}
                      placeholder="Notizen hinzufügen (z.B. besondere Vereinbarungen, wichtige Hinweise, etc.)"
                      className="min-h-[100px] resize-none focus:ring-brand-primary focus:border-brand-primary"
                      rows={4}
                    />
                  </CardContent>
                </Card>
              )}

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
                            placeholder={editedData.is_available ? "Notizen hinzufügen (z.B. Hausaufgaben gegeben, Stunde verpasst, etc.)" : "Grund/Notiz zur Ausfallstunde …"}
                            className="min-h-[60px] resize-none focus:ring-brand-primary focus:border-brand-primary"
                            rows={2}
                          />
                        </div>
                      </div>
                    </AccordionContent>
                  </AccordionItem>
                );
              }).filter(Boolean)}
            </Accordion>
            </div>

            {/* Sticky footer */}
            <div className="sticky bottom-0 z-20 bg-white/95 backdrop-blur border-t px-4 py-3 pb-[env(safe-area-inset-bottom)]">
              <div className="flex gap-2">
                <Button 
                  variant="outline" 
                  onClick={onClose}
                  className="flex-1"
                >
                  Abbrechen
                </Button>
                <Button 
                  onClick={handleSave} 
                  disabled={saving || loading}
                  className="flex-1 bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
                >
                  {saving ? 'Speichern...' : 'Fortschritt speichern'}
                </Button>
              </div>
            </div>
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
                <p className="text-sm">{getContractTypeDisplayUnified(contract)}</p>
              </div>
              <div>
                <span className="text-sm font-medium text-gray-600">Laufzeit:</span>
                <p className="text-sm">{getContractDurationUnified(contract)}</p>
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

            {/* NEW: Payment & Cancellation badges + Laufzeit label */}
            <div className="flex flex-wrap items-center gap-2 mb-4">
              {contract.billing_cycle === 'upfront' && contract.paid_at && (
                <Badge variant="secondary">Bezahlt am {fmtDate(contract.paid_at)}</Badge>
              )}
              {contract.billing_cycle === 'monthly' && contract.first_payment_date && (
                <Badge variant="secondary">Erste Zahlung {fmtDate(contract.first_payment_date)}</Badge>
              )}
              {contract.cancelled_at && (
                <Badge variant="destructive" className="bg-transparent text-red-600 border-red-300">Gekündigt zum {fmtDate(contract.cancelled_at)}</Badge>
              )}
            </div>

            {(contract.term_label || contract.term_start || contract.term_end) && (
              <div className="mb-4">
                <span className="text-sm font-medium text-gray-600">Laufzeit:</span>
                <span className="text-sm ml-2">
                  {contract.term_label || fmtRange(contract.term_start, contract.term_end)}
                </span>
              </div>
            )}

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

        {/* Private Notes Panel - INLINED */}
        {isAdminOrTeacher && (
          <Card className="mb-6">
            <CardHeader>
              <CardTitle className="text-lg">
                Notizen (nur intern)
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Textarea
                value={privateNotes}
                onChange={(e) => setPrivateNotes(e.target.value)}
                placeholder="Notizen hinzufügen (z.B. besondere Vereinbarungen, wichtige Hinweise, etc.)"
                className="min-h-[100px] resize-none focus:ring-brand-primary focus:border-brand-primary"
                rows={4}
              />
            </CardContent>
          </Card>
        )}

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
                            placeholder={editedData.is_available ? "Notizen hinzufügen (z.B. Hausaufgaben gegeben, Stunde verpasst, etc.)" : "Grund/Notiz zur Ausfallstunde …"}
                            className="min-h-[60px] resize-none focus:ring-brand-primary focus:border-brand-primary"
                            rows={2}
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
              <span>Vertrag: {getContractTypeDisplayUnified(contract)}</span>
            </div>
            <div className="flex items-center gap-1">
              <Calendar className="h-4 w-4" />
              <span>Gültig für: {getContractDurationUnified(contract)}</span>
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
