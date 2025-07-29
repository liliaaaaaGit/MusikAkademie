import { useState, useEffect, useMemo } from 'react';
import { supabase, Contract, Student, Teacher, ContractCategory, ContractVariant, ContractDiscount, ContractPricing, calculateContractPrice, getContractDuration, getLegacyContractType } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { ReplaceContractConfirmationModal } from '@/components/modals/ReplaceContractConfirmationModal';
import { toast } from 'sonner';
import { FileText } from 'lucide-react';

interface ContractFormProps {
  contract?: Contract;
  students: Student[];
  onSuccess: () => void;
  onCancel: () => void;
  initialStudentId?: string;
}

// Deep copy utility function to create immutable snapshots
const deepCopy = <T,>(obj: T): T => {
  if (obj === null || typeof obj !== 'object') {
    return obj;
  }
  
  if (obj instanceof Date) {
    return new Date(obj.getTime()) as unknown as T;
  }
  
  if (Array.isArray(obj)) {
    return obj.map(item => deepCopy(item)) as unknown as T;
  }
  
  if (typeof obj === 'object') {
    const copy = {} as T;
    for (const key in obj) {
      if (obj.hasOwnProperty(key)) {
        copy[key] = deepCopy(obj[key]);
      }
    }
    return copy;
  }
  
  return obj;
};

// Helper to convert JS array to Postgres array string
function toPostgresArray(arr: string[]): string {
  return '{' + arr.map(id => `"${id}"`).join(',') + '}';
}

export function ContractForm({ contract, students, onSuccess, onCancel, initialStudentId }: ContractFormProps) {
  const { profile, isAdmin } = useAuth();
  
  // Enhanced teacher profile resolution
  const currentTeacher = useMemo(() => {
    if (!profile?.id) return undefined;
    
    return students.find(s => s.teacher?.profile_id === profile.id)?.teacher;
  }, [profile, students]);

  // Contract data state
  const [contractCategories, setContractCategories] = useState<ContractCategory[]>([]);
  const [contractVariants, setContractVariants] = useState<ContractVariant[]>([]);
  const [contractDiscounts, setContractDiscounts] = useState<ContractDiscount[]>([]);
  const [calculatedPricing, setCalculatedPricing] = useState<ContractPricing | null>(null);

  // Replacement modal state
  const [showReplaceConfirmationModal, setShowReplaceConfirmationModal] = useState(false);
  const [contractToReplaceDetails, setContractToReplaceDetails] = useState<Contract | null>(null);
  const [isReplacementConfirmed, setIsReplacementConfirmed] = useState(false);

  // Custom discount state
  const [useCustomDiscount, setUseCustomDiscount] = useState(false);
  const [customDiscountPercent, setCustomDiscountPercent] = useState<number>(0);
  const [customDiscountId, setCustomDiscountId] = useState<string>('custom-discount');

  const [formData, setFormData] = useState({
    student_id: contract?.student_id || initialStudentId || '',
    selectedCategoryId: '',
    selectedVariantId: contract?.contract_variant_id || '',
    selectedDiscountIds: contract?.discount_ids || [],
    status: contract?.status || 'active'
  });
  const [loading, setLoading] = useState(false);

  // Filter students based on role - FIXED: Only admins can edit contracts
  const availableStudents = useMemo(() => {
    if (isAdmin) {
      // Admins can see all students
      return students;
    } else if (profile?.role === 'teacher' && currentTeacher) {
      // Teachers can only see their own students (read-only)
      return students.filter(s => s.teacher_id === currentTeacher.id);
    }
    return [];
  }, [isAdmin, profile, currentTeacher, students]);

  // Filter contract categories to exclude "Sondervereinbarung" and "Diplomausbildung"
  const availableCategories = useMemo(() => {
    return contractCategories.filter(category => 
      category.name !== 'special_discount' && 
      category.name !== 'private_diploma'
    );
  }, [contractCategories]);

  // Filter variants based on selected category
  const filteredVariants = useMemo(() => {
    if (!formData.selectedCategoryId) return [];
    return contractVariants.filter(v => v.contract_category_id === formData.selectedCategoryId);
  }, [contractVariants, formData.selectedCategoryId]);

  // Get selected variant details
  const selectedVariant = useMemo(() => {
    return contractVariants.find(v => v.id === formData.selectedVariantId);
  }, [contractVariants, formData.selectedVariantId]);

  // Get selected category details
  const selectedCategory = useMemo(() => {
    return contractCategories.find(c => c.id === formData.selectedCategoryId);
  }, [contractCategories, formData.selectedCategoryId]);

  // Fetch contract data on component mount
  useEffect(() => {
    fetchContractData();
  }, []);

  // Set initial category when editing existing contract
  useEffect(() => {
    if (contract?.contract_variant_id && contractVariants.length > 0) {
      const variant = contractVariants.find(v => v.id === contract.contract_variant_id);
      if (variant) {
        setFormData(prev => ({
          ...prev,
          selectedCategoryId: variant.contract_category_id,
          selectedVariantId: variant.id,
          selectedDiscountIds: contract.discount_ids || []
        }));
      }
    }
  }, [contract, contractVariants]);

  // Initialize custom discount if contract has one
  useEffect(() => {
    if (contract?.custom_discount_percent) {
      setUseCustomDiscount(true);
      setCustomDiscountPercent(contract.custom_discount_percent);
      
      // Add custom discount ID to selected discounts if not already there
      if (!formData.selectedDiscountIds.includes(customDiscountId)) {
        setFormData(prev => ({
          ...prev,
          selectedDiscountIds: [...prev.selectedDiscountIds, customDiscountId]
        }));
      }
    }
  }, [contract]);

  // Calculate pricing when variant or discounts change
  useEffect(() => {
    if (formData.selectedVariantId) {
      calculatePricing();
    } else {
      setCalculatedPricing(null);
    }
  }, [formData.selectedVariantId, formData.selectedDiscountIds, useCustomDiscount, customDiscountPercent]);

  const fetchContractData = async () => {
    try {
      // Fetch contract categories
      const { data: categoriesData, error: categoriesError } = await supabase
        .from('contract_categories')
        .select('*')
        .order('display_name');

      if (categoriesError) {
        toast.error('Fehler beim Laden der Vertragskategorien', { description: categoriesError.message });
        return;
      }

      setContractCategories(categoriesData || []);

      // Fetch contract variants
      const { data: variantsData, error: variantsError } = await supabase
        .from('contract_variants')
        .select('*')
        .order('name');

      if (variantsError) {
        toast.error('Fehler beim Laden der Vertragsvarianten', { description: variantsError.message });
        return;
      }

      setContractVariants(variantsData || []);

      // Fetch contract discounts
      const { data: discountsData, error: discountsError } = await supabase
        .from('contract_discounts')
        .select('*')
        .order('name');

      if (discountsError) {
        toast.error('Fehler beim Laden der Rabatte', { description: discountsError.message });
        return;
      }

      setContractDiscounts(discountsData || []);
    } catch (error) {
      console.error('Error fetching contract data:', error);
      toast.error('Fehler beim Laden der Vertragsdaten');
    }
  };

  const calculatePricing = async () => {
    if (!formData.selectedVariantId) {
      setCalculatedPricing(null);
      return;
    }

    try {
      const pricing = await calculateContractPrice(
        formData.selectedVariantId,
        formData.selectedDiscountIds.filter(id => id !== customDiscountId),
        useCustomDiscount ? {
          id: customDiscountId,
          name: `Custom Discount (${customDiscountPercent}%)`,
          discount_percent: customDiscountPercent,
          conditions: 'manually assigned',
          is_active: true,
          created_at: new Date().toISOString()
        } : undefined
      );
        setCalculatedPricing(pricing);
    } catch (error) {
      console.error('Error calculating pricing:', error);
      setCalculatedPricing(null);
    }
  };

  const handleSave = async () => {
    const loadingToast = toast.loading('Speichere Vertrag...');
    // Prepare contractData from form state
    const discountIds = formData.selectedDiscountIds.filter(id => id !== customDiscountId);
    const contractData = {
      student_id: formData.student_id,
      type: getLegacyContractType(selectedCategory?.name || ''),
      contract_variant_id: formData.selectedVariantId,
      status: formData.status,
      discount_ids: discountIds.length > 0 ? discountIds : null,
      custom_discount_percent: useCustomDiscount && customDiscountPercent > 0 
        ? customDiscountPercent 
        : null,
      payment_type: calculatedPricing?.payment_type || null
    };
    try {
      // 1. Atomic save and sync in one backend transaction
      const { data: result, error } = await supabase.rpc('atomic_save_and_sync_contract', {
        contract_data: contractData,
        is_update: !!contract,
        contract_id_param: contract?.id || null
      });
      if (error) {
        console.error('Save error:', error);
        throw new Error(error.message || 'Datenbankfehler aufgetreten');
      }
      if (!result?.success || !result.contract_id) {
        throw new Error(result?.message || 'Speichern fehlgeschlagen');
      }
      // 2. Refetch the updated contract from Supabase
      const { data: updatedContract, error: fetchError } = await supabase
        .from('contracts')
        .select('*, lessons(*)')
        .eq('id', result.contract_id)
        .single();
      if (fetchError || !updatedContract) {
        throw new Error(fetchError?.message || 'Fehler beim Laden des aktualisierten Vertrags');
      }
      // 3. Show success message
      toast.success(result.message, { id: loadingToast });
      // 4. Show any backend warnings
      if (Array.isArray(result.warnings) && result.warnings.length > 0) {
        result.warnings.forEach((warning: string) => toast("Warnung: " + warning));
      }
      // 5. Let parent handle UI refresh
      onSuccess?.();
    } catch (error) {
      console.error('Contract save failed:', error);
      const errorMessage = error instanceof Error ? error.message : 'Unbekannter Fehler';
      toast.error(`Speichern des Vertrags fehlgeschlagen: ${errorMessage}`, { id: loadingToast });
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Validate required fields
      if (!formData.student_id) {
        toast.error('Bitte wählen Sie einen Schüler aus');
        setLoading(false);
        return;
      }

      if (!formData.selectedVariantId) {
        toast.error('Bitte wählen Sie eine Vertragsvariante aus');
        setLoading(false);
        return;
      }

      if (!selectedCategory) {
        toast.error('Vertragskategorie nicht gefunden');
        setLoading(false);
        return;
      }

      // Validate custom discount if enabled
      if (useCustomDiscount) {
        if (customDiscountPercent < 0 || customDiscountPercent > 100) {
          toast.error('Benutzerdefinierte Ermäßigung muss zwischen 0% und 100% liegen');
          setLoading(false);
          return;
        }
      }

      // FIXED: Only admins can create/edit contracts
      if (!isAdmin) {
        toast.error('Nur Administratoren können Verträge erstellen und bearbeiten');
          setLoading(false);
          return;
      }

      // Check for existing active contract (for new contracts only)
      if (!contract && !isReplacementConfirmed) {
        const { data: existingContracts, error: checkError } = await supabase
          .from('contracts')
          .select(`
            *,
            student:students!fk_contracts_student_id(
              id, name, instrument, 
              teacher:teachers(id, name, bank_id)
            ),
            contract_variant:contract_variants(
              id, name, duration_months, group_type, session_length_minutes, total_lessons, monthly_price, one_time_price,
              contract_category:contract_categories(id, name, display_name)
            ),
            lessons:lessons(id, lesson_number, date, is_available, comment)
          `)
          .eq('student_id', formData.student_id)
          .eq('status', 'active');

        if (checkError) {
          toast.error('Fehler beim Prüfen bestehender Verträge', { description: checkError.message });
          setLoading(false);
          return;
        }

        if (existingContracts && existingContracts.length > 0) {
          // Fetch discount details if needed
          const existingContract = existingContracts[0];
          let appliedDiscounts = [];
          
          if (existingContract.discount_ids && existingContract.discount_ids.length > 0) {
            const { data: discountsData } = await supabase
              .from('contract_discounts')
              .select('*')
              .in('id', existingContract.discount_ids);
            
            appliedDiscounts = discountsData || [];
          }

          // Create a deep copy of the contract to ensure immutability
          const contractSnapshot = deepCopy({
            ...existingContract,
            applied_discounts: appliedDiscounts
          });

          setContractToReplaceDetails(contractSnapshot);
          setShowReplaceConfirmationModal(true);
          setLoading(false);
          return;
        }
      }

      // If replacement confirmed, delete old contract first
      if (isReplacementConfirmed && contractToReplaceDetails) {
        const { error: deleteError } = await supabase
          .from('contracts')
          .delete()
          .eq('id', contractToReplaceDetails.id);

        if (deleteError) {
          toast.error('Fehler beim Löschen des alten Vertrags', { description: deleteError.message });
          setLoading(false);
          return;
        }
      }

      // Perform the actual contract save
      await handleSave();
    } catch (error) {
      console.error('Error saving contract:', error);
      toast.error('Fehler beim Speichern des Vertrags', { 
        description: error instanceof Error ? error.message : 'Unbekannter Fehler' 
      });
    } finally {
      setLoading(false);
    }
  };

  const handleConfirmReplace = () => {
    setIsReplacementConfirmed(true);
    setShowReplaceConfirmationModal(false);
    
    // Re-trigger form submission
    setTimeout(() => {
      const form = document.querySelector('form');
      if (form) {
        form.requestSubmit();
      }
    }, 100);
  };

  const handleChange = (field: string, value: string | string[]) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    
    // Reset variant when category changes
    if (field === 'selectedCategoryId') {
      setFormData(prev => ({ ...prev, selectedVariantId: '' }));
    }
  };

  const handleDiscountToggle = (discountId: string, checked: boolean) => {
    setFormData(prev => ({
      ...prev,
      selectedDiscountIds: checked
        ? [...prev.selectedDiscountIds, discountId]
        : prev.selectedDiscountIds.filter(id => id !== discountId)
    }));
  };

  const handleCustomDiscountToggle = (checked: boolean) => {
    setUseCustomDiscount(checked);
    if (!checked) {
      setCustomDiscountPercent(0);
      // Remove custom discount from selected discounts
      setFormData(prev => ({
        ...prev,
        selectedDiscountIds: prev.selectedDiscountIds.filter(id => id !== customDiscountId)
      }));
    } else {
      // Add custom discount to selected discounts
      if (!formData.selectedDiscountIds.includes(customDiscountId)) {
        setFormData(prev => ({
          ...prev,
          selectedDiscountIds: [...prev.selectedDiscountIds, customDiscountId]
        }));
      }
    }
  };

  const handleCustomDiscountChange = (value: string) => {
    const percent = parseFloat(value) || 0;
    setCustomDiscountPercent(percent);
  };

  // FIXED: Only show form for admins
  if (!isAdmin) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <FileText className="h-12 w-12 text-gray-300 mx-auto mb-4" />
          <p className="text-gray-500">Nur Administratoren können Verträge erstellen und bearbeiten.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Student Selection */}
        <Card>
          <CardHeader>
            <CardTitle>Schüler auswählen</CardTitle>
          </CardHeader>
          <CardContent>
        <div className="space-y-4">
            <div>
              <Label htmlFor="student">Schüler *</Label>
              <Select 
                value={formData.student_id} 
                onValueChange={(value) => handleChange('student_id', value)}
                  disabled={loading}
              >
                <SelectTrigger>
                    <SelectValue placeholder="Schüler auswählen" />
                </SelectTrigger>
                <SelectContent>
                  {availableStudents.map((student) => (
                    <SelectItem key={student.id} value={student.id}>
                        <div className="flex items-center gap-2">
                          <span>{student.name}</span>
                          <Badge variant="outline" className="text-xs">
                            {student.instrument}
                          </Badge>
                          {student.teacher && (
                            <Badge variant="secondary" className="text-xs">
                              {student.teacher.name}
                            </Badge>
                          )}
                        </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            </div>
          </CardContent>
        </Card>

        {/* Contract Type Selection */}
        <Card>
          <CardHeader>
            <CardTitle>Vertragstyp auswählen</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
            <div>
              <Label htmlFor="category">Vertragskategorie *</Label>
              <Select 
                value={formData.selectedCategoryId} 
                onValueChange={(value) => handleChange('selectedCategoryId', value)}
                  disabled={loading}
              >
                <SelectTrigger>
                    <SelectValue placeholder="Kategorie auswählen" />
                </SelectTrigger>
                <SelectContent>
                  {availableCategories.map((category) => (
                    <SelectItem key={category.id} value={category.id}>
                      {category.display_name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

              {formData.selectedCategoryId && (
            <div>
              <Label htmlFor="variant">Vertragsvariante *</Label>
              <Select 
                value={formData.selectedVariantId} 
                onValueChange={(value) => handleChange('selectedVariantId', value)}
                    disabled={loading}
              >
                <SelectTrigger>
                      <SelectValue placeholder="Variante auswählen" />
                </SelectTrigger>
                <SelectContent>
                  {filteredVariants.map((variant) => (
                    <SelectItem key={variant.id} value={variant.id}>
                          <div className="flex items-center justify-between w-full">
                            <span>{variant.name}</span>
                            <div className="flex items-center gap-2 text-sm text-gray-500">
                              {variant.monthly_price && (
                                <span>{variant.monthly_price}€/Monat</span>
                              )}
                              {variant.one_time_price && (
                                <span>{variant.one_time_price}€ einmalig</span>
                              )}
                            </div>
                          </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
              )}
          </div>
          </CardContent>
        </Card>

        {/* Pricing Display */}
        {calculatedPricing && (
          <Card>
            <CardHeader>
              <CardTitle>Preisberechnung</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">Basispreis:</span>
                  <span className="font-medium">
                    {(calculatedPricing.base_monthly_price || calculatedPricing.base_one_time_price)?.toFixed(2)}€
                    {calculatedPricing.payment_type === 'monthly' ? ' / Monat' : ' einmalig'}
                  </span>
                </div>
                
                {calculatedPricing.total_discount_percent > 0 && (
                  <div className="flex justify-between items-center text-green-600">
                    <span>Rabatt:</span>
                    <span className="font-medium">-{calculatedPricing.total_discount_percent}%</span>
                  </div>
                )}
                
                <Separator />
                
                <div className="flex justify-between items-center text-lg font-semibold">
                  <span>Endpreis:</span>
                  <span className="text-brand-primary">
                    {calculatedPricing.final_monthly_price?.toFixed(2) || calculatedPricing.final_one_time_price?.toFixed(2)}€
                    {calculatedPricing.payment_type === 'monthly' ? ' / Monat' : ' einmalig'}
                  </span>
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Discounts */}
        {contractDiscounts.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle>Rabatte</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
              {contractDiscounts.map((discount) => (
                  <div key={discount.id} className="flex items-start space-x-3">
                  <Checkbox
                    id={discount.id}
                    checked={formData.selectedDiscountIds.includes(discount.id)}
                    onCheckedChange={(checked) => handleDiscountToggle(discount.id, checked as boolean)}
                      disabled={loading}
                  />
                  <div className="flex-1 min-w-0">
                    <label htmlFor={discount.id} className="text-sm font-medium text-gray-900 cursor-pointer">
                          {discount.name}
                    </label>
                        <p className="text-sm text-gray-500">{discount.conditions || `-${discount.discount_percent}%`}</p>
                  </div>
                </div>
              ))}
              
              {isAdmin && (
                <div className="flex items-start space-x-3 p-3 border rounded-lg">
                  <Checkbox
                    id="custom-discount"
                    checked={useCustomDiscount}
                    onCheckedChange={(checked) => handleCustomDiscountToggle(checked as boolean)}
                    className="mt-1"
                  />
                  <div className="flex-1 min-w-0">
                    <label htmlFor="custom-discount" className="text-sm font-medium text-gray-900 cursor-pointer">
                      Benutzerdefinierte Ermäßigung
                      <span className="ml-2 text-xs text-gray-500">(Nur Admin)</span>
                    </label>
                    {useCustomDiscount && (
                      <div className="mt-2">
                        <div className="flex items-center gap-2">
                          <Input
                            type="number"
                            min="0"
                            max="100"
                            step="0.1"
                            value={customDiscountPercent}
                            onChange={(e) => handleCustomDiscountChange(e.target.value)}
                            className="w-24 h-8 text-sm"
                          />
                          <span className="text-sm font-medium">%</span>
                        </div>
                        <p className="text-xs text-gray-500 mt-1">
                          Geben Sie einen Wert zwischen 0 und 100% ein
                        </p>
                      </div>
                    )}
            </div>
          </div>
        )}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Contract Status */}
        <Card>
          <CardHeader>
            <CardTitle>Vertragsstatus</CardTitle>
          </CardHeader>
          <CardContent>
            <div>
              <Label htmlFor="status">Status</Label>
              <Select
                value={formData.status}
                onValueChange={(value) => handleChange('status', value)}
                disabled={loading}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="active">Aktiv</SelectItem>
                  <SelectItem value="completed">Abgeschlossen</SelectItem>
                  <SelectItem value="cancelled">Storniert</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end space-x-2 pt-6 border-t">
          <Button 
            type="button" 
            variant="outline" 
            onClick={onCancel}
            className="bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray focus:ring-brand-primary"
          >
            Abbrechen
          </Button>
          <Button 
            type="submit" 
            disabled={loading || availableStudents.length === 0 || !formData.selectedVariantId}
            className="bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
          >
            {loading ? 'Speichern...' : contract ? 'Vertrag aktualisieren' : 'Vertrag erstellen'}
          </Button>
        </div>
      </form>

      {/* Replace Contract Confirmation Modal */}
      {contractToReplaceDetails && (
        <ReplaceContractConfirmationModal
          open={showReplaceConfirmationModal}
          onClose={() => {
            setShowReplaceConfirmationModal(false);
            setContractToReplaceDetails(null);
            setIsReplacementConfirmed(false);
          }}
          onConfirm={handleConfirmReplace}
          contractToReplace={contractToReplaceDetails}
        />
      )}
    </div>
  );
}