import { supabase } from '@/lib/supabase';

export async function updateContractNotes(contractId: string, notes: string) {
  const { error } = await supabase.rpc('update_contract_notes', { 
    _contract_id: contractId, 
    _notes: notes 
  });
  
  if (error) {
    throw new Error(error.message || 'Failed to update contract notes');
  }
}
