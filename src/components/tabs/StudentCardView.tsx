import React from 'react';
import { Badge } from '@/components/ui/badge';
import { Info } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useIsMobile } from '@/hooks/useIsMobile';

interface StudentCardViewProps {
  students: any[];
  noOuterPadding?: boolean;
}

export const StudentCardView: React.FC<StudentCardViewProps> = ({ students, noOuterPadding }) => {
  const { profile } = useAuth();
  const isMobile = useIsMobile();
  const isTeacherMobile = profile?.role === 'teacher' && isMobile;

  return (
    <div className={`sm:hidden w-full max-w-[600px] mx-auto${noOuterPadding ? '' : ' px-2'}`}>
      <div className="flex flex-col gap-4 pt-2 pb-6 overflow-x-hidden">
        {students.map((student) => (
          <div
            key={student.id}
            className="w-full bg-white rounded-lg shadow-md border border-gray-100 p-4 flex flex-col"
          >
            <div className="flex items-center justify-between mb-2">
              <div className="text-lg font-semibold truncate">{student.name}</div>
              <Badge
                className={
                  student.status === 'active'
                    ? 'bg-green-100 text-green-800'
                    : 'bg-gray-200 text-gray-600'
                }
              >
                {student.status === 'active' ? 'Aktiv' : 'Inaktiv'}
              </Badge>
            </div>
            <div className="flex flex-col gap-1 text-sm">
              <div className="flex items-center gap-2">
                <span className="font-medium">Instrument:</span>
                <span className="truncate">{student.instrument || '-'}</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-medium">E-Mail:</span>
                <span className="truncate">{student.email || '-'}</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-medium">Telefon:</span>
                <span className="truncate">{student.phone || '-'}</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-medium">Vertrag:</span>
                <span className="truncate">{student.contract ? student.contract.contract_variant?.name : '-'}</span>
              </div>
            </div>
            {/* Only show the pink info text if NOT teacher on mobile */}
            {!(isTeacherMobile) && (
              <div className="flex items-center gap-2 mt-3">
                <Info className="w-5 h-5 text-pink-500" />
                <span className="text-xs text-pink-500">Info: Nur Anzeige – keine Bearbeitung möglich</span>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}; 