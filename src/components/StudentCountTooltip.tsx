import { useState } from 'react';
import { supabase, Student } from '@/lib/supabase';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Users, Loader2 } from 'lucide-react';
import { toast } from 'sonner';

interface StudentCountTooltipProps {
  teacherId: string;
  studentCount: number;
}

export function StudentCountTooltip({ teacherId, studentCount }: StudentCountTooltipProps) {
  const [students, setStudents] = useState<Student[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);

  const fetchStudents = async () => {
    if (studentCount === 0 || students.length > 0) return;
    
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('students')
        .select('id, name, instrument, status')
        .eq('teacher_id', teacherId)
        .eq('status', 'active')
        .order('name');

      if (error) {
        toast.error('Failed to fetch students', { description: error.message });
        return;
      }

      setStudents(data as Student[] || []);
    } catch (error) {
      console.error('Error fetching students:', error);
      toast.error('Failed to fetch students');
    } finally {
      setLoading(false);
    }
  };

  const handleOpenChange = (newOpen: boolean) => {
    setOpen(newOpen);
    if (newOpen) {
      fetchStudents();
    }
  };

  if (studentCount === 0) {
    return (
      <div className="flex items-center space-x-2">
        <Users className="h-4 w-4 text-gray-400" />
        <Badge variant="outline">0</Badge>
      </div>
    );
  }

  return (
    <Popover open={open} onOpenChange={handleOpenChange}>
      <PopoverTrigger asChild>
        <button className="flex items-center space-x-2 hover:bg-gray-50 rounded-md p-1 transition-colors">
          <Users className="h-4 w-4 text-gray-400" />
          <Badge variant="outline" className="cursor-pointer hover:bg-brand-primary/10 hover:border-brand-primary">
            {studentCount}
          </Badge>
        </button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-0" align="start">
        <div className="p-4 border-b">
          <h4 className="font-medium text-sm text-gray-900">
            Zugewiesene Schüler ({studentCount})
          </h4>
        </div>
        
        {loading ? (
          <div className="flex items-center justify-center p-6">
            <Loader2 className="h-5 w-5 animate-spin text-brand-primary" />
            <span className="ml-2 text-sm text-gray-500">Lade Schüler...</span>
          </div>
        ) : students.length > 0 ? (
          <ScrollArea className="max-h-80 overflow-y-auto">
            <div className="p-2 space-y-1">
              {students.map((student, index) => (
                <div
                  key={student.id}
                  className="flex items-center justify-between p-3 rounded-md hover:bg-gray-50 transition-colors"
                >
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center space-x-2">
                      <span className="text-xs text-gray-500 font-mono w-6">
                        {index + 1}.
                      </span>
                      <span className="text-sm font-medium text-gray-900 truncate">
                        {student.name}
                      </span>
                    </div>
                    <div className="flex items-center space-x-2 mt-1">
                      <span className="text-xs text-gray-500 ml-8">
                        {student.instrument}
                      </span>
                    </div>
                  </div>
                  <Badge 
                    variant={student.status === 'active' ? 'default' : 'secondary'}
                    className="ml-2 text-xs"
                  >
                    {student.status === 'active' ? 'Aktiv' : 'Inaktiv'}
                  </Badge>
                </div>
              ))}
            </div>
          </ScrollArea>
        ) : (
          <div className="p-6 text-center">
            <Users className="h-8 w-8 text-gray-300 mx-auto mb-2" />
            <p className="text-sm text-gray-500">Keine aktiven Schüler gefunden</p>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}