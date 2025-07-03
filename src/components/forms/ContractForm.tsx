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

  // Filter students based on role - THIS IS THE KEY FIX
  const availableStudents = useMemo(() => {
    if (isAdmin) {
      // Admins can see all students
      return students;
    } else if (profile?.role === 'teacher' && currentTeacher) {
      // Teachers can only see their own students
      return students.filter(s => s.teacher_id === currentTeacher.id);
    }
    return [];
  }, [isAdmin, profile, currentTeacher, students]);

  // Filter contract categories to exclude "Sondervereinbarung"
  const availableCategories = useMemo(() => {
    return contractCategories.filter(category => category.name !== 'special_discount');
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
      const { data: categories, error: categoriesError } = await supabase
        .from('contract_categories')
        .select('*')
        .order('display_name');

      if (categoriesError) {
        toast.error('Fehler beim Laden der Vertragskategorien', { description: categoriesError.message });
        return;
      }

      // Fetch contract variants with category data
      const { data: variants, error: variantsError } = await supabase
        .from('contract_variants')
        .select(`
          *,
          contract_category:contract_categories(*)
        `)
        .eq('is_active', true)
        .order('name');

      if (variantsError) {
        toast.error('Fehler beim Laden der Vertragsvarianten', { description: variantsError.message });
        return;
      }

      // Fetch contract discounts
      const { data: discounts, error: discountsError } = await supabase
        .from('contract_discounts')
        .select('*')
        .eq('is_active', true)
        .order('name');

      if (discountsError) {
        toast.error('Fehler beim Laden der Ermäßigungen', { description: discountsError.message });
        return;
      }

      setContractCategories(categories || []);
      setContractVariants(variants || []);
      setContractDiscounts(discounts || []);
    } catch (error) {
      console.error('Error fetching contract data:', error);
      toast.error('Fehler beim Laden der Vertragsdaten');
    }
  };

  const calculatePricing = async () => {
    if (!formData.selectedVariantId) return;

    try {
      // Create a copy of the selected discount IDs
      let discountIdsToUse = [...formData.selectedDiscountIds];
      
      // If using custom discount, add the custom discount ID
      if (useCustomDiscount && customDiscountPercent > 0) {
        // Create a custom discount object
        const customDiscount = {
          id: customDiscountId,
          name: `Custom Discount (${customDiscountPercent}%)`,
          discount_percent: customDiscountPercent,
          conditions: 'manually assigned',
          is_active: true
        };
        
        // Add the custom discount ID to the list
        if (!discountIdsToUse.includes(customDiscountId)) {
          discountIdsToUse.push(customDiscountId);
        }
        
        // Calculate pricing with the custom discount
        const pricing = await calculateContractPrice(
          formData.selectedVariantId,
          discountIdsToUse,
          customDiscount
        );
        
        setCalculatedPricing(pricing);
      } else {
        // Calculate pricing without custom discount
        const pricing = await calculateContractPrice(
          formData.selectedVariantId,
          discountIdsToUse
        );
        
        setCalculatedPricing(pricing);
      }
    } catch (error) {
      console.error('Error calculating pricing:', error);
      toast.error('Fehler beim Berechnen des Preises');
    }
  };

  const performContractSave = async () => {
    if (!selectedCategory) {
      throw new Error('Vertragskategorie nicht gefunden');
    }

    // Prepare contract data with legacy type mapping
    const contractData: any = {
      student_id: formData.student_id,
      type: getLegacyContractType(selectedCategory.name), // Use legacy type mapping
      contract_variant_id: formData.selectedVariantId,
      status: formData.status,
      updated_at: new Date().toISOString()
    };

    // Add discount IDs if any are selected (excluding custom discount)
    if (formData.selectedDiscountIds.length > 0) {
      // Filter out the custom discount ID since it's not a real UUID
      const validDiscountIds = formData.selectedDiscountIds.filter(id => id !== customDiscountId);
      
      contractData.discount_ids = validDiscountIds.length > 0 ? validDiscountIds : null;
    } else {
      contractData.discount_ids = null;
    }

    // Add pricing information
    contractData.final_price = calculatedPricing?.final_monthly_price || calculatedPricing?.final_one_time_price || null;
    contractData.payment_type = calculatedPricing?.payment_type || null;

    // Add custom discount percentage if applicable
    if (useCustomDiscount && customDiscountPercent > 0) {
      contractData.custom_discount_percent = customDiscountPercent;
    } else {
      contractData.custom_discount_percent = null;
    }

    if (contract) {
      // Update existing contract
      const { error } = await supabase
        .from('contracts')
        .update(contractData)
        .eq('id', contract.id);

      if (error) {
        throw error;
      }

      toast.success('Vertrag erfolgreich aktualisiert');
    } else {
      // Create new contract
      const { data: newContract, error } = await supabase
        .from('contracts')
        .insert([contractData])
        .select()
        .single();

      if (error) {
        throw error;
      }

      // Update student's contract reference
      await supabase
        .from('students')
        .update({
          contract_id: newContract.id
        })
        .eq('id', formData.student_id);

      toast.success('Vertrag erfolgreich erstellt');
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

      // Additional validation for teachers - ensure they can only create contracts for their students
      if (profile?.role === 'teacher' && currentTeacher) {
        const selectedStudent = availableStudents.find(s => s.id === formData.student_id);
        if (!selectedStudent || selectedStudent.teacher_id !== currentTeacher.id) {
          toast.error('Sie können nur Verträge für Ihre eigenen Schüler erstellen');
          setLoading(false);
          return;
        }
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
      await performContractSave();
      onSuccess();
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
    
    // If unchecking, remove custom discount from selected discounts
    if (!checked) {
      setFormData(prev => ({
        ...prev,
        selectedDiscountIds: prev.selectedDiscountIds.filter(id => id !== customDiscountId)
      }));
    }
  };

  const handleCustomDiscountChange = (value: string) => {
    const numValue = parseFloat(value);
    if (isNaN(numValue)) {
      setCustomDiscountPercent(0);
    } else {
      // Clamp value between 0 and 100
      setCustomDiscountPercent(Math.min(Math.max(numValue, 0), 100));
    }
  };

  const getGroupTypeDisplay = (groupType: string) => {
    switch (groupType) {
      case 'single':
        return 'Einzelunterricht';
      case 'group':
        return 'Gruppenunterricht';
      case 'duo':
        return 'Zweierunterricht';
      case 'varies':
        return 'Variiert';
      default:
        return groupType;
    }
  };

  const formatPrice = (price: number | null | undefined) => {
    if (!price) return '-';
    return `${price.toFixed(2)}€`;
  };

  // Function to translate discount names to German
  const getDiscountNameGerman = (name: string) => {
    switch (name) {
      case 'Family/Student Discount':
        return 'Familien-/Studentenermäßigung';
      case 'Combo Booking (2 blocks)':
        return 'Kombi-Buchung (2 Blöcke)';
      case 'Combo Booking (3 blocks)':
        return 'Kombi-Buchung (3 Blöcke)';
      case 'Half-Year Prepayment':
        return 'Halbjahres-Vorauszahlung';
      case 'Full-Year Prepayment':
        return 'Ganzjahres-Vorauszahlung';
      default:
        return name;
    }
  };

  // Function to translate discount conditions to German
  const getDiscountConditionsGerman = (conditions: string) => {
    switch (conditions) {
      case 'manually assignable':
        return 'manuell zuweisbar';
      case 'applies if 2 active blocks exist':
        return 'gilt bei 2 aktiven Blöcken';
      case 'applies if 3+ active blocks exist':
        return 'gilt bei 3+ aktiven Blöcken';
      case 'applies if paid upfront':
        return 'gilt bei Vorauszahlung';
      default:
        return conditions;
    }
  };

  const selectedStudent = availableStudents.find(s => s.id === formData.student_id);

  return (
    <div className="max-h-[85vh] overflow-y-auto">
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="space-y-4">
          <h3 className="text-lg font-medium text-gray-900">Vertragsdetails</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <Label htmlFor="student">Schüler *</Label>
              <Select 
                value={formData.student_id} 
                onValueChange={(value) => handleChange('student_id', value)}
                required
              >
                <SelectTrigger>
                  <SelectValue placeholder="Schüler auswählen..." />
                </SelectTrigger>
                <SelectContent>
                  {availableStudents.map((student) => (
                    <SelectItem key={student.id} value={student.id}>
                      {student.name} - {student.instrument}
                      {student.teacher && ` (${student.teacher.name})`}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {/* Show info message for teachers */}
              {profile?.role === 'teacher' && (
                <p className="text-xs text-gray-500 mt-1">
                  Sie sehen nur Ihre zugewiesenen Schüler
                </p>
              )}
            </div>

            <div>
              <Label htmlFor="status">Status</Label>
              <Select 
                value={formData.status} 
                onValueChange={(value) => handleChange('status', value)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="active">Aktiv</SelectItem>
                  <SelectItem value="completed">Abgeschlossen</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div>
              <Label htmlFor="category">Vertragskategorie *</Label>
              <Select 
                value={formData.selectedCategoryId} 
                onValueChange={(value) => handleChange('selectedCategoryId', value)}
                required
              >
                <SelectTrigger>
                  <SelectValue placeholder="Kategorie auswählen..." />
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

            <div>
              <Label htmlFor="variant">Vertragsvariante *</Label>
              <Select 
                value={formData.selectedVariantId} 
                onValueChange={(value) => handleChange('selectedVariantId', value)}
                required
                disabled={!formData.selectedCategoryId}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Variante auswählen..." />
                </SelectTrigger>
                <SelectContent>
                  {filteredVariants.map((variant) => (
                    <SelectItem key={variant.id} value={variant.id}>
                      {variant.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
        </div>

        {/* Contract Information Card */}
        {selectedVariant && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Vertragsinformationen</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4 text-sm">
                <div>
                  <span className="font-medium text-gray-600">Kategorie:</span>
                  <p>{selectedCategory?.display_name}</p>
                </div>
                <div>
                  <span className="font-medium text-gray-600">Variante:</span>
                  <p>{selectedVariant.name}</p>
                </div>
                <div>
                  <span className="font-medium text-gray-600">Unterrichtsform:</span>
                  <p>{getGroupTypeDisplay(selectedVariant.group_type)}</p>
                </div>
                <div>
                  <span className="font-medium text-gray-600">Laufzeit:</span>
                  <p>{getContractDuration(selectedVariant)}</p>
                </div>
                <div>
                  <span className="font-medium text-gray-600">Gesamtstunden:</span>
                  <p>{selectedVariant.total_lessons || '-'} Stunden</p>
                </div>
                <div>
                  <span className="font-medium text-gray-600">Stundenlänge:</span>
                  <p>{selectedVariant.session_length_minutes ? `${selectedVariant.session_length_minutes} min` : 'Variiert'}</p>
                </div>
              </div>

              {/* Pricing Information */}
              <Separator />
              <div className="space-y-3">
                <h4 className="font-medium text-gray-900">Preisübersicht</h4>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="font-medium text-gray-600">Grundpreis:</span>
                    <p>
                      {selectedVariant.monthly_price 
                        ? `${formatPrice(selectedVariant.monthly_price)} / Monat`
                        : `${formatPrice(selectedVariant.one_time_price)} einmalig`
                      }
                    </p>
                  </div>
                  {calculatedPricing && calculatedPricing.total_discount_percent > 0 && (
                    <div>
                      <span className="font-medium text-gray-600">Ermäßigung:</span>
                      <p className="text-green-600">-{calculatedPricing.total_discount_percent}%</p>
                    </div>
                  )}
                </div>
                {calculatedPricing && (
                  <div className="bg-brand-primary/5 p-3 rounded-lg">
                    <span className="font-medium text-brand-primary">Endpreis:</span>
                    <p className="text-lg font-bold text-brand-primary">
                      {calculatedPricing.payment_type === 'monthly'
                        ? `${formatPrice(calculatedPricing.final_monthly_price)} / Monat`
                        : `${formatPrice(calculatedPricing.final_one_time_price)} einmalig`
                      }
                    </p>
                  </div>
                )}
              </div>

              {selectedStudent && (
                <>
                  <Separator />
                  <div>
                    <span className="font-medium text-gray-600">Schüler:</span>
                    <p>{selectedStudent.name} - {selectedStudent.instrument}</p>
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        )}

        {/* Discounts Section */}
        {(contractDiscounts.length > 0 || isAdmin) && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-gray-900">Ermäßigungen</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {contractDiscounts.map((discount) => (
                <div key={discount.id} className="flex items-start space-x-3 p-3 border rounded-lg">
                  <Checkbox
                    id={discount.id}
                    checked={formData.selectedDiscountIds.includes(discount.id)}
                    onCheckedChange={(checked) => handleDiscountToggle(discount.id, checked as boolean)}
                    className="mt-1"
                  />
                  <div className="flex-1 min-w-0">
                    <label htmlFor={discount.id} className="text-sm font-medium text-gray-900 cursor-pointer">
                      {getDiscountNameGerman(discount.name)}
                    </label>
                    <div className="flex items-center gap-2 mt-1">
                      <Badge variant="outline" className="text-xs">
                        -{discount.discount_percent}%
                      </Badge>
                      {discount.conditions && (
                        <span className="text-xs text-gray-500">{getDiscountConditionsGerman(discount.conditions)}</span>
                      )}
                    </div>
                  </div>
                </div>
              ))}
              
              {/* Custom Discount Option (Admin Only) */}
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
                    {useCustomDiscount && customDiscountPercent > 0 && (
                      <div className="flex items-center gap-2 mt-1">
                        <Badge variant="outline" className="text-xs bg-green-50 text-green-700 border-green-200">
                          -{customDiscountPercent}%
                        </Badge>
                        <span className="text-xs text-gray-500">manuell zugewiesen</span>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Warning for existing contracts */}
        {!contract && selectedStudent?.contract_id && !isReplacementConfirmed && (
          <Card className="border-yellow-200 bg-yellow-50">
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <div className="flex-shrink-0">
                  <svg className="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                  </svg>
                </div>
                <div>
                  <h3 className="text-sm font-medium text-yellow-800">
                    Schüler hat bereits einen Vertrag
                  </h3>
                  <p className="text-sm text-yellow-700 mt-1">
                    Dieser Schüler hat bereits einen aktiven Vertrag. Das Erstellen eines neuen Vertrags ersetzt den bestehenden.
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        )}

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