import React, { useState } from 'react';
import { Info } from 'lucide-react';

export const TeacherMobileInfoBox: React.FC = () => {
  const [expanded, setExpanded] = useState(false);

  return (
    <div
      className="bg-gray-50 border-gray-200 rounded-lg mb-4 cursor-pointer select-none transition-colors duration-200"
      onClick={() => setExpanded((prev) => !prev)}
      aria-expanded={expanded}
      tabIndex={0}
      role="button"
    >
      <div className="flex items-center space-x-3 p-4">
        <Info className="h-5 w-5 text-gray-600 flex-shrink-0" />
        <span className="font-bold text-gray-800">Lehreransicht</span>
      </div>
      <div
        className={`overflow-hidden transition-all duration-300 ease-in-out ${expanded ? 'max-h-40 opacity-100' : 'max-h-0 opacity-0'}`}
      >
        <div className="px-4 pb-4 text-sm text-gray-700">
          <span className="font-semibold block mb-1">Lehreransicht – Eingeschränkte Berechtigungen</span>
          Sie können nur Ihre eigenen Verträge anzeigen und Stunden verfolgen. Das Hinzufügen, Bearbeiten oder Löschen von Verträgen ist nur für Administratoren möglich.
        </div>
      </div>
    </div>
  );
}; 