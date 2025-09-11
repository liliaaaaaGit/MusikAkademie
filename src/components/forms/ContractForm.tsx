import { useState, useEffect, useMemo } from 'react';
import { supabase, Contract, Student, Teacher, ContractCategory, ContractVariant, ContractDiscount, ContractPricing, calculateContractPrice, getLegacyContractType } from '@/lib/supabase';
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
  teachers: Teacher[];
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

export function ContractForm({ contract, students, teachers, onSuccess, onCancel, initialStudentId }: ContractFormProps) {
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

  // NEW: Payment & term & cancellation state
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'upfront' | ''>(contract?.billing_cycle || '');
  const [paidAt, setPaidAt] = useState<string | ''>(contract?.paid_at || '');
  const [paidThrough, setPaidThrough] = useState<string | ''>(contract?.paid_through || '');
  const [termStart, setTermStart] = useState<string | ''>(contract?.term_start || '');
  const [termEnd, setTermEnd] = useState<string | ''>(contract?.term_end || '');
  const [termLabel, setTermLabel] = useState<string>(contract?.term_label || '');
  const [isCancelledToggle, setIsCancelledToggle] = useState<boolean>(!!contract?.cancelled_at);
  const [cancelledAt, setCancelledAt] = useState<string | ''>(contract?.cancelled_at || '');

  const [formData, setFormData] = useState({
    student_id: contract?.student_id || initialStudentId || '',
    teacher_id: contract?.teacher_id || '',
    selectedCategoryId: '',
    selectedVariantId: contract?.contract_variant_id || '',
    selectedDiscountIds: contract?.discount_ids || []
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
      if (!formData.selectedDiscountIds.includes('custom-discount')) {
        setFormData(prev => ({
          ...prev,
          selectedDiscountIds: [...prev.selectedDiscountIds, 'custom-discount']
        }));
      }
    }
  }, [contract]);

  // Refetch cohort-aware variants whenever the selected student changes
  useEffect(() => {
    const loadVariantsForStudent = async () => {
      try {
        if (formData.student_id) {
          const { data, error } = await supabase.rpc('get_variants_for_student', { p_student_id: formData.student_id });
          if (error) {
            toast.error('Fehler beim Laden der Vertragsvarianten', { description: error.message });
            setContractVariants([]);
            return;
          }
          setContractVariants(data || []);
          // Reset selected variant if it does not belong to the list anymore
          if (formData.selectedVariantId && !(data || []).some((v: any) => v.id === formData.selectedVariantId)) {
            setFormData(prev => ({ ...prev, selectedVariantId: '' }));
          }
        } else {
          setContractVariants([]);
          if (formData.selectedVariantId) {
            setFormData(prev => ({ ...prev, selectedVariantId: '' }));
          }
        }
      } catch (e) {
        console.error('Error loading variants for student', e);
        setContractVariants([]);
      }
    };
    loadVariantsForStudent();
  }, [formData.student_id]);

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

      // Fetch contract variants (cohort-aware) when a student is selected
      if (formData.student_id) {
        const { data: variantsData, error: variantsError } = await supabase
          .rpc('get_variants_for_student', { p_student_id: formData.student_id });

        if (variantsError) {
          toast.error('Fehler beim Laden der Vertragsvarianten', { description: variantsError.message });
          return;
        }

        setContractVariants(variantsData || []);
      } else {
        setContractVariants([]);
      }

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
        formData.selectedDiscountIds.filter(id => id !== 'custom-discount'),
        useCustomDiscount ? {
          id: 'custom-discount',
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
    const discountIds = formData.selectedDiscountIds.filter(id => id !== 'custom-discount');
    const contractData = {
      student_id: formData.student_id,
      teacher_id: formData.teacher_id,
      type: getLegacyContractType(selectedCategory?.name || ''),
      contract_variant_id: formData.selectedVariantId,
      discount_ids: discountIds.length > 0 ? discountIds : null,
      custom_discount_percent: useCustomDiscount && customDiscountPercent > 0 
        ? customDiscountPercent 
        : null,
      payment_type: calculatedPricing?.payment_type || null,

      // NEW fields (send only when present)
      billing_cycle: billingCycle || null,
      paid_at: billingCycle === 'upfront' && paidAt ? paidAt : null,
      paid_through: billingCycle === 'monthly' && paidThrough ? paidThrough : null,
      term_start: termStart || null,
      term_end: termEnd || null,
      term_label: termLabel || null,
      cancelled_at: isCancelledToggle && cancelledAt ? cancelledAt : null
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
        .select(`
          id, billing_cycle, paid_at, paid_through, term_start, term_end, term_label, cancelled_at,
          student:students!fk_contracts_student_id(id, name, instrument, status, bank_id),
          teacher:teachers!contracts_teacher_id_fkey(id, name, bank_id),
          contract_variant:contract_variants(
            id, name, duration_months, group_type, session_length_minutes, total_lessons,
            monthly_price, one_time_price,
            contract_category:contract_categories(id, name, display_name)
          ),
          lessons:lessons(id, lesson_number, date, is_available, comment),
          type, discount_ids, custom_discount_percent, payment_type, status, attendance_count, attendance_dates, created_at, updated_at
        `)
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

      if (!formData.teacher_id) {
        toast.error('Bitte wählen Sie einen Lehrer aus');
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

      // Check for existing active contract with same (student_id, teacher_id) pair (for new contracts only)
      if (!contract && !isReplacementConfirmed) {
        const { data: existingContract, error: checkError } = await supabase
          .from('contracts')
          .select(`
            *,
            student:students!fk_contracts_student_id(
              id, name, instrument
            ),
            teacher:teachers!contracts_teacher_id_fkey(id, name, bank_id),
            contract_variant:contract_variants(
              id, name, duration_months, group_type, session_length_minutes, total_lessons, monthly_price, one_time_price,
              contract_category:contract_categories(id, name, display_name)
            ),
            lessons:lessons(id, lesson_number, date, is_available, comment)
          `)
          .eq('student_id', formData.student_id)
          .eq('teacher_id', formData.teacher_id)
          .eq('status', 'active')
          .maybeSingle();

        if (checkError) {
          toast.error('Fehler beim Prüfen bestehender Verträge', { description: checkError.message });
          setLoading(false);
          return;
        }

        if (existingContract) {
          // Fetch discount details if needed
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
        selectedDiscountIds: prev.selectedDiscountIds.filter(id => id !== 'custom-discount')
      }));
    } else {
      // Add custom discount to selected discounts
      if (!formData.selectedDiscountIds.includes('custom-discount')) {
        setFormData(prev => ({
          ...prev,
          selectedDiscountIds: [...prev.selectedDiscountIds, 'custom-discount']
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
                          {student.email && (
                            <Badge variant="secondary" className="text-xs">
                              {student.email}
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

        {/* Teacher Selection */}
        <Card>
          <CardHeader>
            <CardTitle>Lehrer auswählen</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <div>
                <Label htmlFor="teacher">Lehrer *</Label>
                <Select 
                  value={formData.teacher_id} 
                  onValueChange={(value) => handleChange('teacher_id', value)}
                  disabled={loading}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Lehrer auswählen" />
                  </SelectTrigger>
                  <SelectContent>
                    {teachers.map((teacher) => (
                      <SelectItem key={teacher.id} value={teacher.id}>
                        <div className="flex items-center gap-2">
                          <span>{teacher.name}</span>
                          <Badge variant="outline" className="text-xs">
                            {teacher.instrument}
                          </Badge>
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

        {/* NEW: Payment Section */}
        <Card>
          <CardHeader>
            <CardTitle>Zahlung</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex gap-4 items-center">
              <Label className="w-32 mt-1">Zyklus</Label>
              <div className="flex gap-6">
                <div className="flex items-center gap-2">
                  <input type="radio" id="cycle-monthly" name="billing_cycle" checked={billingCycle==='monthly'} onChange={() => { setBillingCycle('monthly'); setPaidAt(''); }} />
                  <Label htmlFor="cycle-monthly">Monatlich</Label>
                </div>
                <div className="flex items-center gap-2">
                  <input type="radio" id="cycle-upfront" name="billing_cycle" checked={billingCycle==='upfront'} onChange={() => { setBillingCycle('upfront'); setPaidThrough(''); }} />
                  <Label htmlFor="cycle-upfront">Einmalig</Label>
                </div>
              </div>
            </div>

            {billingCycle === 'monthly' && (
              <div className="flex items-center gap-4">
                <Label className="w-32">Bezahlt bis</Label>
                <Input type="date" value={paidThrough || ''} onChange={e => setPaidThrough(e.target.value)} className="max-w-[220px]" />
                <Button type="button" variant="outline" onClick={() => {
                  const t = new Date();
                  const y = t.getFullYear();
                  const m = t.getMonth()+1;
                  const last = new Date(y, m, 0).getDate();
                  const mm = String(m).padStart(2,'0');
                  const dd = String(last).padStart(2,'0');
                  setPaidThrough(`${y}-${mm}-${dd}`);
                }}>
                  Heute (Monatsende)
                </Button>
              </div>
            )}

            {billingCycle === 'upfront' && (
              <div className="flex items-center gap-4">
                <Label className="w-32">Bezahlt am</Label>
                <Input type="date" value={paidAt || ''} onChange={e => setPaidAt(e.target.value)} className="max-w-[220px]" />
                <Button type="button" variant="outline" onClick={() => {
                  const t = new Date();
                  const yyyy = t.getFullYear();
                  const mm = String(t.getMonth()+1).padStart(2,'0');
                  const dd = String(t.getDate()).padStart(2,'0');
                  setPaidAt(`${yyyy}-${mm}-${dd}`);
                }}>
                  Heute
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        {/* NEW: Term Section */}
        <Card>
          <CardHeader>
            <CardTitle>Laufzeit</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center gap-4">
              <Label className="w-32">Beginn</Label>
              <Input type="date" value={termStart || ''} onChange={e => setTermStart(e.target.value)} className="max-w-[220px]" />
            </div>
            <div className="flex items-center gap-4">
              <Label className="w-32">Ende</Label>
              <Input type="date" value={termEnd || ''} onChange={e => setTermEnd(e.target.value)} className="max-w-[220px]" />
            </div>
            <div className="flex items-center gap-4">
              <Label className="w-32">Label (optional)</Label>
              <Input value={termLabel} onChange={e => setTermLabel(e.target.value)} placeholder="z. B. Schuljahr 2025/26" className="max-w-[360px]" />
            </div>
          </CardContent>
        </Card>

        {/* NEW: Cancellation Section */}
        <Card>
          <CardHeader>
            <CardTitle>Kündigung</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center gap-3">
              <Checkbox id="cancelled-toggle" checked={isCancelledToggle} onCheckedChange={(v) => setIsCancelledToggle(!!v)} />
              <Label htmlFor="cancelled-toggle">Gekündigt</Label>
            </div>
            {isCancelledToggle && (
              <div className="flex items-center gap-4">
                <Label className="w-32">Kündigungsdatum</Label>
                <Input type="date" value={cancelledAt || ''} onChange={e => setCancelledAt(e.target.value)} className="max-w-[220px]" />
              </div>
            )}
          </CardContent>
        </Card>

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

        {/* Contract Status control removed: status is display-only elsewhere */}

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
            disabled={loading || availableStudents.length === 0 || !formData.selectedVariantId || !formData.teacher_id}
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