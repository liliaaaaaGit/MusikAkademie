import { useState, useEffect, useMemo } from 'react';
import { useForm } from 'react-hook-form';
import { supabase, Student, Teacher, ContractCategory, ContractVariant, ContractDiscount, ContractPricing, calculateContractPrice, getContractDuration, getLegacyContractType } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { StudentForEdit } from '@/lib/students/getStudentForEdit';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { ReplaceContractConfirmationModal } from '@/components/modals/ReplaceContractConfirmationModal';
import { INSTRUMENTS } from '@/lib/constants';
import { toast } from 'sonner';

// Helper constants and functions for shadcn Select compatibility
const NONE = '__none__';
const toNullable = (v: string | null | undefined) => (v === NONE ? null : v ?? null);
const toSelectValue = (v: string | null | undefined) => (v ? String(v) : NONE);

type FormValues = {
  name: string;
  email: string | null;
  phone: string | null;
  status: string;
  teacher_id: string | null;
  contract_variant_id: string | null;
};

interface StudentFormProps {
  student?: Student;
  teachers: Teacher[];
  onSuccess: () => void;
  onCancel: () => void;
  // Add these new props for prefilled data
  prefilledStudent?: StudentForEdit;
  variants?: { id: string; name: string }[];
}

export function StudentForm({ student, teachers, onSuccess, onCancel, prefilledStudent }: StudentFormProps) {
  const { profile, isAdmin } = useAuth();
  
  // Enhanced teacher profile resolution with robust string comparison
  const currentTeacher = useMemo(() => {
    if (!profile?.id) return undefined;
    
    return teachers.find(t => {
      // Ensure both values exist and are strings before comparison
      if (!t.profile_id || !profile.id) return false;
      
      // Trim whitespace and compare
      const teacherProfileId = String(t.profile_id).trim();
      const userProfileId = String(profile.id).trim();
      
      return teacherProfileId === userProfileId;
    });
  }, [profile, teachers]);
  
  const currentTeacherId = currentTeacher?.id;
  const isTeacherProfileResolved = profile?.role === 'teacher' ? !!currentTeacher : true;

  // Contract data state
  const [contractCategories, setContractCategories] = useState<ContractCategory[]>([]);
  const [contractVariants, setContractVariants] = useState<ContractVariant[]>([]);
  const [contractDiscounts, setContractDiscounts] = useState<ContractDiscount[]>([]);
  const [calculatedPricing, setCalculatedPricing] = useState<ContractPricing | null>(null);

  // Replacement modal state
  const [showReplaceConfirmationModal, setShowReplaceConfirmationModal] = useState(false);
  const [contractToReplaceDetails, setContractToReplaceDetails] = useState<any>(null);
  const [isReplacementConfirmed, setIsReplacementConfirmed] = useState(false);

  // Custom instrument state
  const [showCustomInstrumentInput, setShowCustomInstrumentInput] = useState(false);
  const [customInstrumentValue, setCustomInstrumentValue] = useState('');

  // Custom discount state
  const [useCustomDiscount, setUseCustomDiscount] = useState(false);
  const [customDiscountPercent, setCustomDiscountPercent] = useState<number>(0);

  const [formData, setFormData] = useState({
    instrument: student?.instrument || '',
    email: student?.email || '',
    phone: student?.phone || '',
    teacher_id: student?.teacher_id || (profile?.role === 'teacher' && currentTeacherId ? currentTeacherId : ''),
    status: student?.status || 'active',
    // Contract fields
    selectedCategoryId: '',
    selectedVariantId: '',
    selectedDiscountIds: [] as string[]
  });
  const [loading, setLoading] = useState(false);

  // React Hook Form setup for prefilled data
  const { setValue, reset, watch, handleSubmit: rhfHandleSubmit, register } = useForm<FormValues>({
    defaultValues: {
      name: prefilledStudent?.name ?? student?.name ?? '',
      email: prefilledStudent?.email ?? student?.email ?? '',
      phone: prefilledStudent?.phone ?? student?.phone ?? '',
      status: prefilledStudent?.status ?? student?.status ?? 'Aktiv',
      teacher_id: prefilledStudent?.teacher_id ?? student?.teacher_id ?? null,
      contract_variant_id: prefilledStudent?.contract_variant_id ?? null,
    },
  });

  // Reset form when prefilled data changes
  useEffect(() => {
    if (prefilledStudent) {
      reset({
        name: prefilledStudent.name ?? '',
        email: prefilledStudent.email ?? '',
        phone: prefilledStudent.phone ?? '',
        status: prefilledStudent.status ?? 'Aktiv',
        teacher_id: prefilledStudent.teacher_id ?? null,
        contract_variant_id: prefilledStudent.contract_variant_id ?? null,
      });
    }
  }, [prefilledStudent, reset]);

  const teacherId = watch('teacher_id') ?? '';
  const variantId = watch('contract_variant_id') ?? '';
  // Track when all contract data is loaded
  const [contractDataLoaded, setContractDataLoaded] = useState(false);

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

  // Initialize custom instrument state based on existing data
  useEffect(() => {
    if (student?.instrument && !INSTRUMENTS.includes(student.instrument as any)) {
      setShowCustomInstrumentInput(true);
      setCustomInstrumentValue(student.instrument);
      setFormData(prev => ({ ...prev, instrument: 'andere' }));
    }
  }, [student]);

  // Initialize contract data when editing existing student
  useEffect(() => {
    if (student?.contracts && student.contracts.length > 0 && contractDataLoaded && contractVariants.length > 0 && contractDiscounts.length > 0) {
      console.log('Initializing contract data for student:', student.name);
      console.log('Student contracts:', student.contracts);
      console.log('Available variants:', contractVariants.length);
      
      // Get the first active contract (or the first contract if none are active)
      const activeContract = student.contracts.find(c => c.status === 'active') || student.contracts[0];
      console.log('Using contract:', activeContract);
      
      const variant = contractVariants.find(v => v.id === activeContract?.contract_variant_id);
      console.log('Found variant:', variant);
      
      if (variant) {
        // Ensure all discount IDs are strings for comparison
        const discountIds = (activeContract?.discount_ids || []).map(String);
        console.log('Setting form data with:', {
          selectedCategoryId: variant.contract_category_id,
          selectedVariantId: variant.id,
          selectedDiscountIds: discountIds
        });
        
        setFormData(prev => ({
          ...prev,
          selectedCategoryId: variant.contract_category_id,
          selectedVariantId: variant.id,
          selectedDiscountIds: discountIds
        }));
      } else {
        console.warn('Contract variant not found in available variants:', activeContract?.contract_variant_id);
      }
    }
  }, [student, contractVariants, contractDiscounts, contractDataLoaded]);

  // Initialize custom discount if student's contract has one
  useEffect(() => {
    if (student?.contracts && student.contracts.length > 0) {
      // Get the first active contract (or the first contract if none are active)
      const activeContract = student.contracts.find(c => c.status === 'active') || student.contracts[0];
      
      if (activeContract?.custom_discount_percent) {
        console.log('Initializing custom discount:', activeContract.custom_discount_percent);
        setUseCustomDiscount(true);
        setCustomDiscountPercent(activeContract.custom_discount_percent);
        
        // Add custom discount ID to selected discounts if not already there
        if (!formData.selectedDiscountIds.includes('custom-discount')) {
          setFormData(current => ({
            ...current,
            selectedDiscountIds: [...current.selectedDiscountIds, 'custom-discount']
          }));
        }
      }
    }
  }, [student, formData.selectedDiscountIds]);

  // Fetch contract data on component mount
  useEffect(() => {
    fetchContractData();
  }, []);

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
        console.error('Error fetching contract categories:', categoriesError);
        return;
      }

      // Fetch contract variants using RPC - pass null for new students to get current price version
      const { data: variants, error: variantsError } = await supabase
        .rpc('get_variants_for_student', { p_student_id: student?.id || null });

      if (variantsError) {
        console.error('Error fetching contract variants:', variantsError);
        return;
      }

      // Fetch contract discounts
      const { data: discounts, error: discountsError } = await supabase
        .from('contract_discounts')
        .select('*')
        .eq('is_active', true)
        .order('name');

      if (discountsError) {
        console.error('Error fetching contract discounts:', discountsError);
        return;
      }

      setContractCategories(categories || []);
      setContractVariants(variants || []);
      setContractDiscounts(discounts || []);
      setContractDataLoaded(true);
    } catch (error) {
      console.error('Error fetching contract data:', error);
    }
  };

  const calculatePricing = async () => {
    if (!formData.selectedVariantId) return;

    try {
      // Create a copy of the selected discount IDs
      let discountIdsToUse = [...formData.selectedDiscountIds];
      
      // If using custom discount, add the custom discount ID
      if (useCustomDiscount && customDiscountPercent > 0) {
        // Create a custom discount object that matches ContractDiscount interface
        const customDiscount: ContractDiscount = {
          id: 'custom-discount',
          name: `Custom Discount (${customDiscountPercent}%)`,
          discount_percent: customDiscountPercent,
          conditions: 'manually assigned',
          is_active: true,
          created_at: new Date().toISOString()
        };
        
        // Add the custom discount ID to the list
        if (!discountIdsToUse.includes('custom-discount')) {
          discountIdsToUse.push('custom-discount');
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
    }
  };

  const performStudentSave = async (data: FormValues) => {
    // Determine the final instrument value
    let finalInstrument = formData.instrument;
    if (showCustomInstrumentInput && customInstrumentValue.trim()) {
      finalInstrument = customInstrumentValue.trim();
    }

    // Prepare data for submission - bank_id will be auto-generated by database
    const submitData: any = {
      name: data.name.trim(),
      instrument: finalInstrument,
      email: data.email?.trim() || null,
      phone: data.phone?.trim() || null,
      status: data.status
    };

    // Clean up null/empty values
    Object.keys(submitData).forEach(key => {
      if (submitData[key] === '' || submitData[key] === 'null') {
        submitData[key] = null;
      }
    });

    if (student) {
      // Update existing student - bank_id is never updated
      const { error } = await supabase
        .from('students')
        .update(submitData)
        .eq('id', student.id);

      if (error) {
        throw error;
      }

      return student.id;
    } else {
      // Create new student - bank_id will be auto-generated by database
      const { data: newStudent, error } = await supabase
        .from('students')
        .insert([submitData])
        .select()
        .single();

      if (error) {
        throw error;
      }

      return newStudent.id;
    }
  };

  const performContractSave = async (studentId: string) => {
    if (!selectedCategory) {
      throw new Error('Vertragskategorie nicht gefunden');
    }

    // FIXED: Prepare contract data for safe save with UUID validation
    const contractData = {
      student_id: studentId,
      teacher_id: formData.teacher_id && formData.teacher_id.trim() !== '' ? formData.teacher_id : null,
      type: getLegacyContractType(selectedCategory.name),
      contract_variant_id: formData.selectedVariantId && formData.selectedVariantId.trim() !== '' ? formData.selectedVariantId : null,
      status: 'active',
      // FIXED: Handle discount IDs properly
      discount_ids: formData.selectedDiscountIds.filter(id => id !== 'custom-discount').length > 0 
        ? formData.selectedDiscountIds.filter(id => id !== 'custom-discount') 
        : null,
      // FIXED: Handle custom discount properly
      custom_discount_percent: useCustomDiscount && customDiscountPercent > 0 
        ? customDiscountPercent 
        : null,
      // FIXED: Always update pricing information
      final_price: calculatedPricing?.final_monthly_price || calculatedPricing?.final_one_time_price || null,
      payment_type: calculatedPricing?.payment_type || null
    };

    // Validate required UUID fields
    if (!contractData.teacher_id) {
      throw new Error('Lehrer muss ausgewählt werden');
    }
    if (!contractData.contract_variant_id) {
      throw new Error('Vertragsvariante muss ausgewählt werden');
    }

    // Debug logging to help identify the issue
    console.log('Contract data being sent:', {
      student_id: contractData.student_id,
      teacher_id: contractData.teacher_id,
      contract_variant_id: contractData.contract_variant_id,
      type: contractData.type,
      status: contractData.status
    });

    // FIXED: Use atomic save function with comprehensive error handling
    const activeContract = student?.contracts?.find(c => c.status === 'active') || student?.contracts?.[0];
    const { data: saveResult, error: saveError } = await supabase.rpc('atomic_save_and_sync_contract', {
      contract_data: contractData,
      is_update: !!activeContract,
      contract_id_param: activeContract?.id || null
    });

    if (saveError) {
      console.error('Safe save error:', saveError);
      throw new Error(`Database error: ${saveError.message}`);
    }

    if (!saveResult.success) {
      console.error('Save failed:', saveResult);
      throw new Error(saveResult.error || 'Unknown save error');
    }

    return { id: saveResult.contract_id };
  };

  const handleSubmit = async (data: FormValues) => {
    setLoading(true);

    try {
      // Validate required fields
      if (!data.name.trim()) {
        toast.error('Schülername ist erforderlich');
        setLoading(false);
        return;
      }

      // Validate instrument selection
      if (!formData.instrument.trim()) {
        toast.error('Instrument ist erforderlich');
        setLoading(false);
        return;
      }

      // Validate custom instrument if "andere" is selected
      if (showCustomInstrumentInput && !customInstrumentValue.trim()) {
        toast.error('Bitte geben Sie ein Instrument ein');
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

      // For teachers, ensure they can only assign students to themselves
      if (profile?.role === 'teacher') {
        if (!currentTeacherId) {
          toast.error('Lehrerprofil nicht gefunden. Bitte kontaktieren Sie Ihren Administrator.');
          setLoading(false);
          return;
        }
        
        // Force teacher_id to be the current teacher's ID for teachers
        setFormData(prev => ({ ...prev, teacher_id: currentTeacherId }));
      }

      // For admins creating new students, require teacher assignment
      if (isAdmin && !student && !formData.teacher_id) {
        toast.error('Bitte weisen Sie einen Lehrer zu');
        setLoading(false);
        return;
      }

      // Validate teacher assignment for teachers
      if (profile?.role === 'teacher' && formData.teacher_id !== currentTeacherId) {
        toast.error('Lehrer können nur Schüler zu sich selbst zuweisen');
        setLoading(false);
        return;
      }

      // Save student first
      const studentId = await performStudentSave(data);
      
      if (student) {
        toast.success('Schüler erfolgreich aktualisiert');
      } else {
        toast.success('Schüler erfolgreich erstellt');
      }

      // FIXED: Handle contract creation/update if variant is selected
      let contractId: string | null = null;
      if (formData.selectedVariantId && studentId && selectedCategory) {
        // FIXED: For new students, check for existing contracts
        if (!student) {
        // Check for existing active contract and handle replacement if needed
        if (!isReplacementConfirmed) {
          const { data: existingContracts, error: checkError } = await supabase
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
            .eq('student_id', studentId)
            .eq('status', 'active');

          if (checkError) {
            console.error('Error checking existing contracts:', checkError);
            toast.error('Fehler beim Prüfen bestehender Verträge');
          } else if (existingContracts && existingContracts.length > 0) {
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

            setContractToReplaceDetails({
              ...existingContract,
              applied_discounts: appliedDiscounts
            });
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
        }

        // FIXED: Create or update contract
        try {
          const contractResult = await performContractSave(studentId);
          contractId = contractResult.id;
          // NEW: Update student with contract_id if contract was created
          if (contractId) {
            const { error: updateError } = await supabase
              .from('students')
              .update({ contract_id: contractId })
              .eq('id', studentId);
            if (updateError) {
              throw updateError;
            }
          }
          if (student) {
            toast.success('Schüler und Vertrag erfolgreich aktualisiert');
          } else {
            toast.success('Schüler und Vertrag erfolgreich erstellt');
          }
        } catch (contractError) {
          console.error('Contract creation/update error:', contractError);
          
          // Enhanced error reporting
          let errorMessage = 'Unbekannter Fehler beim Erstellen/Aktualisieren des Vertrags';
          
          if (contractError && typeof contractError === 'object') {
            if ('message' in contractError) {
              errorMessage = (contractError as any).message;
              
              // Check for specific constraint violations
              if (errorMessage.includes('lessons_lesson_number_check')) {
                errorMessage = 'Fehler: Die Anzahl der Stunden für diesen Vertragstyp überschreitet das erlaubte Maximum. Bitte kontaktieren Sie den Administrator.';
              } else if (errorMessage.includes('contract_variant_id')) {
                errorMessage = 'Fehler: Ungültige Vertragsvariante ausgewählt. Bitte wählen Sie eine gültige Variante aus.';
              }
              
              if ('details' in contractError && (contractError as any).details) {
                errorMessage += ` Details: ${(contractError as any).details}`;
              }
            }
          } else if (contractError instanceof Error) {
            errorMessage = contractError.message;
          }
          
          toast.error('Schüler wurde gespeichert, aber Vertrag konnte nicht erstellt/aktualisiert werden', { 
            description: errorMessage
          });
        }
      }

      onSuccess();
    } catch (error) {
      console.error('Error saving student:', error);
      
      // Enhanced error reporting for student creation
      let errorMessage = 'Ein unerwarteter Fehler ist aufgetreten.';
      
      if (error && typeof error === 'object' && 'message' in error) {
        errorMessage = (error as any).message;
        if ((error as any).details) {
          errorMessage += ` Details: ${(error as any).details}`;
        }
      } else if (error instanceof Error) {
        errorMessage = error.message;
      }
      
      toast.error('Fehler beim Speichern des Schülers', {
        description: errorMessage
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

  const handleChange = (field: string, value: string) => {
    // Convert placeholder values back to empty strings for form state
    const actualValue = value === '__none__' ? '' : value;
    setFormData(prev => ({ ...prev, [field]: actualValue }));
    
    // Reset variant when category changes
    if (field === 'selectedCategoryId') {
      setFormData(prev => ({ ...prev, selectedVariantId: '' }));
    }
  };

  const handleInstrumentChange = (value: string) => {
    if (value === 'andere') {
      setShowCustomInstrumentInput(true);
      setFormData(prev => ({ ...prev, instrument: value }));
    } else {
      setShowCustomInstrumentInput(false);
      setCustomInstrumentValue('');
      setFormData(prev => ({ ...prev, instrument: value }));
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
        selectedDiscountIds: prev.selectedDiscountIds.filter(id => id !== 'custom-discount')
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

  // Filter teachers based on role
  const availableTeachers = profile?.role === 'teacher' && currentTeacher 
    ? [currentTeacher] 
    : teachers;

  return (
    <div className="max-h-[80vh] overflow-y-auto">
      <form onSubmit={rhfHandleSubmit(handleSubmit)} className="space-y-6">
        {/* Show error if teacher profile is not resolved */}
        {profile?.role === 'teacher' && !isTeacherProfileResolved && (
          <div className="bg-red-50 border border-red-200 rounded-md p-4">
            <p className="text-sm text-red-600">
              Lehrerprofil nicht gefunden. Bitte kontaktieren Sie Ihren Administrator.
            </p>
          </div>
        )}

        {/* Shared Fields */}
        <div className="space-y-4">
          <h3 className="text-lg font-medium text-gray-900">Grunddaten</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <Label htmlFor="name">Schülername *</Label>
              <Input
                id="name"
                {...register("name", { required: true })}
                placeholder="Schülername eingeben"
              />
            </div>

            <div>
              <Label htmlFor="instrument">Instrument *</Label>
              <Select 
                value={formData.instrument} 
                onValueChange={handleInstrumentChange}
                required
              >
                <SelectTrigger>
                  <SelectValue placeholder="Instrument auswählen..." />
                </SelectTrigger>
                <SelectContent className="max-h-64">
                  {INSTRUMENTS.map((instrument) => (
                    <SelectItem key={instrument} value={instrument}>
                      {instrument === 'andere' ? 'Andere' : instrument}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {showCustomInstrumentInput && (
                <div className="mt-2">
                  <Input
                    value={customInstrumentValue}
                    onChange={(e) => setCustomInstrumentValue(e.target.value)}
                    placeholder="Instrument eingeben..."
                    required
                  />
                </div>
              )}
            </div>

            <div>
              <Label htmlFor="email">E-Mail</Label>
              <Input
                id="email"
                type="email"
                value={formData.email}
                onChange={(e) => handleChange('email', e.target.value)}
                placeholder="student@email.com"
              />
            </div>

            <div>
              <Label htmlFor="phone">Telefon</Label>
              <Input
                id="phone"
                value={formData.phone}
                onChange={(e) => handleChange('phone', e.target.value)}
                placeholder="+49 123 456 789"
              />
            </div>

            <div>
              <Label htmlFor="teacher">
                Zugewiesener Lehrer {(isAdmin && !student) && <span className="text-red-500">*</span>}
              </Label>
              <Select 
                value={toSelectValue(teacherId)}
                onValueChange={(v) => {
                  setValue('teacher_id', toNullable(v), { shouldDirty: true });
                  handleChange('teacher_id', v);
                }}
                disabled={profile?.role === 'teacher'}
                required={isAdmin && !student}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Lehrer auswählen" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>Kein Lehrer zugewiesen</SelectItem>
                  {availableTeachers.map((teacher) => (
                    <SelectItem key={teacher.id} value={String(teacher.id)}>
                      {teacher.name} ({teacher.instrument})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div>
              <Label htmlFor="status">Status</Label>
              <Select value={formData.status} onValueChange={(value) => handleChange('status', value as 'active' | 'inactive')}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="active">Aktiv</SelectItem>
                  <SelectItem value="inactive">Inaktiv</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        </div>

        {/* Contract Section - Available for both admins and teachers when creating new students */}
        {(!student || isAdmin) && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-gray-900">Vertrag (optional)</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <Label htmlFor="category">Vertragskategorie</Label>
                <Select 
                  value={formData.selectedCategoryId || '__none__'} 
                  onValueChange={(value) => handleChange('selectedCategoryId', value)}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Kategorie auswählen..." />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>Kein Vertrag</SelectItem>
                    {availableCategories.map((category) => (
                      <SelectItem key={category.id} value={category.id}>
                        {category.display_name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div>
                <Label htmlFor="variant">Vertragsvariante</Label>
                <Select 
                  value={toSelectValue(variantId)}
                  onValueChange={(v) => {
                    setValue('contract_variant_id', toNullable(v), { shouldDirty: true });
                    handleChange('selectedVariantId', v);
                  }}
                  disabled={!formData.selectedCategoryId}
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Variante auswählen..." />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>Keine Variante</SelectItem>
                    {filteredVariants.map((variant) => (
                      <SelectItem key={variant.id} value={String(variant.id)}>
                        {variant.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            {/* Preisbox nur anzeigen, wenn die gewählte Variante der vorhandenen entspricht */}
            {prefilledStudent?.variant && toSelectValue(variantId) === toSelectValue(prefilledStudent.variant.id) && (
              <div className="rounded-xl border p-3 text-sm">
                <div className="font-medium">Preise (aktuell)</div>
                <div>Grundpreis: {prefilledStudent.variant.one_time_price?.toFixed(2)}€ einmalig</div>
              </div>
            )}

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
                </CardContent>
              </Card>
            )}

            {/* Discounts Section */}
            {contractDataLoaded && (contractDiscounts.length > 0 || isAdmin) && formData.selectedVariantId && !loading && (
              <div className="space-y-4">
                <h4 className="text-base font-medium text-gray-900">Ermäßigungen</h4>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  {contractDiscounts.map((discount) => (
                    <div key={discount.id} className="flex items-start space-x-3 p-3 border rounded-lg">
                      <Checkbox
                        id={discount.id}
                        checked={formData.selectedDiscountIds.map(String).includes(String(discount.id))}
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
          </div>
        )}

        {/* Admin-only Fields - Only show for admins and when editing existing students */}
        {isAdmin && student && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-gray-900">Verwaltung (nur Admin)</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <Label htmlFor="bank_id">Bank-ID</Label>
                <Input
                  id="bank_id"
                  value={student.bank_id || ''}
                  disabled
                  placeholder="Automatisch generiert"
                  className="bg-gray-50 font-mono text-sm"
                />
                <p className="text-xs text-gray-500 mt-1">
                  Diese ID wird automatisch beim Erstellen des Schülers generiert und kann nicht geändert werden.
                </p>
              </div>
            </div>
          </div>
        )}

        <div className="flex justify-end space-x-2 pt-6 border-t">
          <Button 
            type="button" 
            variant="outline" 
            onClick={onCancel}
            className="bg-brand-gray hover:bg-brand-gray/80 text-gray-700 border-brand-gray"
          >
            Abbrechen
          </Button>
          <Button 
            type="submit" 
            disabled={loading || (profile?.role === 'teacher' && !isTeacherProfileResolved)}
            className="bg-brand-primary hover:bg-brand-primary/90"
          >
            {loading ? 'Speichern...' : student ? 'Schüler aktualisieren' : 'Schüler erstellen'}
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