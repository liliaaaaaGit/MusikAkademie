import { useState, useEffect } from 'react';
import { supabase, Contract } from '@/lib/supabase';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Badge } from '@/components/ui/badge';
import { CalendarIcon, X } from 'lucide-react';
import { format } from 'date-fns';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';

interface AttendanceModalProps {
  contract: Contract;
  open: boolean;
  onClose: () => void;
  onUpdate: () => void;
}

export function AttendanceModal({ contract, open, onClose, onUpdate }: AttendanceModalProps) {
  const [attendanceDates, setAttendanceDates] = useState<string[]>([]);
  const [selectedDate, setSelectedDate] = useState<Date>();
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (contract?.attendance_dates) {
      setAttendanceDates(contract.attendance_dates);
    }
  }, [contract]);

  const maxClasses = contract.type === 'ten_class_card' ? 10 : 18;

  const handleAddDate = () => {
    if (!selectedDate) return;

    const dateString = format(selectedDate, 'yyyy-MM-dd');
    
    if (attendanceDates.includes(dateString)) {
      toast.error('This date is already recorded');
      return;
    }

    if (attendanceDates.length >= maxClasses) {
      toast.error(`Maximum ${maxClasses} classes reached for this contract`);
      return;
    }

    setAttendanceDates(prev => [...prev, dateString].sort());
    setSelectedDate(undefined);
  };

  const handleRemoveDate = (dateToRemove: string) => {
    setAttendanceDates(prev => prev.filter(date => date !== dateToRemove));
  };

  const handleSave = async () => {
    setLoading(true);

    try {
      const { error } = await supabase
        .from('contracts')
        .update({
          attendance_dates: attendanceDates
        })
        .eq('id', contract.id);

      if (error) {
        toast.error('Failed to update attendance', { description: error.message });
        return;
      }

      toast.success('Attendance updated successfully');
      onUpdate();
      onClose();
    } catch (error) {
      console.error('Error updating attendance:', error);
      toast.error('Failed to update attendance');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Update Attendance</DialogTitle>
          <div className="text-sm text-gray-600">
            {contract.student?.name} - {contract.type.replace('_', ' ').toUpperCase()}
          </div>
        </DialogHeader>

        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <Label>Progress</Label>
            <Badge variant="outline">
              {attendanceDates.length}/{maxClasses} classes
            </Badge>
          </div>

          <div className="w-full bg-gray-200 rounded-full h-2">
            <div 
              className="bg-brand-primary h-2 rounded-full transition-all duration-300"
              style={{ width: `${(attendanceDates.length / maxClasses) * 100}%` }}
            />
          </div>

          <div>
            <Label>Add Attendance Date</Label>
            <div className="flex gap-2 mt-1">
              <Popover>
                <PopoverTrigger asChild>
                  <Button
                    variant="outline"
                    className={cn(
                      "flex-1 justify-start text-left font-normal bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray focus:ring-brand-primary",
                      !selectedDate && "text-muted-foreground"
                    )}
                  >
                    <CalendarIcon className="mr-2 h-4 w-4" />
                    {selectedDate ? format(selectedDate, "PP") : "Pick a date"}
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0" align="start">
                  <Calendar
                    mode="single"
                    selected={selectedDate}
                    onSelect={setSelectedDate}
                    disabled={(date) => 
                      date > new Date() || 
                      attendanceDates.includes(format(date, 'yyyy-MM-dd'))
                    }
                    initialFocus
                  />
                </PopoverContent>
              </Popover>
              <Button 
                onClick={handleAddDate} 
                disabled={!selectedDate}
                className="bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
              >
                Add
              </Button>
            </div>
          </div>

          <div>
            <Label>Recorded Dates ({attendanceDates.length})</Label>
            <div className="mt-2 max-h-40 overflow-y-auto space-y-1">
              {attendanceDates.length === 0 ? (
                <div className="text-sm text-gray-500 py-2">No attendance recorded yet</div>
              ) : (
                attendanceDates.map((date, index) => (
                  <div key={date} className="flex items-center justify-between bg-gray-50 p-2 rounded">
                    <span className="text-sm">
                      {index + 1}. {format(new Date(date), 'PP')}
                    </span>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleRemoveDate(date)}
                      className="h-6 w-6 p-0 hover:bg-red-100 hover:text-red-600"
                    >
                      <X className="h-3 w-3" />
                    </Button>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button 
            variant="outline" 
            onClick={onClose}
            className="bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray focus:ring-brand-primary"
          >
            Cancel
          </Button>
          <Button 
            onClick={handleSave} 
            disabled={loading}
            className="bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
          >
            {loading ? 'Saving...' : 'Save Changes'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}