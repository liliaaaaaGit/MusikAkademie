import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Contract, getContractTypeDisplay, getLegacyContractTypeDisplay } from '@/lib/supabase';
import { Loader2 } from 'lucide-react';

interface ContractDetailsModalProps {
  open: boolean;
  onClose: () => void;
  contract: Contract | null;
  loading?: boolean;
}

export function ContractDetailsModal({ open, onClose, contract, loading }: ContractDetailsModalProps) {
  // Helper function to get contract type display
  const getContractTypeDisplaySafe = (contract: Contract) => {
    // Use new contract variant system if available
    if (contract.contract_variant) {
      return getContractTypeDisplay(contract.contract_variant);
    }
    
    // Fallback to legacy type system
    if (contract.type) {
      return getLegacyContractTypeDisplay(contract.type);
    }
    
    return 'Unbekannt';
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Vertragsdetails</DialogTitle>
        </DialogHeader>
        {loading ? (
          <div className="flex flex-col items-center justify-center py-8">
            <Loader2 className="animate-spin h-8 w-8 text-gray-400 mb-4" />
            <span className="text-gray-500">Lade Vertrag...</span>
          </div>
        ) : contract ? (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">Typ</span>
              <span className="text-sm font-medium text-gray-900">{getContractTypeDisplaySafe(contract)}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">Status</span>
              <Badge variant={contract.status === 'active' ? 'default' : 'secondary'}>
                {contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen'}
              </Badge>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">Gesamte Stunden</span>
              <span className="text-sm">{contract.attendance_count?.split('/')[1] || '-'}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-600">Abgeschlossene Stunden</span>
              <span className="text-sm">{contract.attendance_count?.split('/')[0] || '-'}</span>
            </div>
            {/* Add more fields here as needed */}
          </div>
        ) : (
          <div className="py-8 text-center text-gray-500">Kein Vertrag gefunden</div>
        )}
        <div className="flex justify-end pt-4">
          <Button variant="outline" onClick={onClose}>
            Schließen
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
} 