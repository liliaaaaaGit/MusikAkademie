import { useState, useEffect, useMemo } from 'react';
import { supabase, Contract, Teacher, Student, ContractDiscount, getContractTypeDisplay, getLegacyContractTypeDisplay, generateContractPDF, PDFContractData } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Plus, Search, MoreHorizontal, Edit, Calendar, FileText, Users, Trash2, Clock, ArrowLeft, Download } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { LessonTrackerModal } from '@/components/modals/LessonTrackerModal';
import { TeacherContractsModal } from '@/components/modals/TeacherContractsModal';
import { DeleteContractConfirmationModal } from '@/components/modals/DeleteContractConfirmationModal';
import { ContractForm } from '@/components/forms/ContractForm';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { toast } from 'sonner';
import { fmtDate } from '@/lib/utils';
import { formatMonthYearShort } from '@/lib/utils';

export function ContractsTab() {
  const { profile, isAdmin } = useAuth();
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [teachers, setTeachers] = useState<Teacher[]>([]);
  const [teacherContracts, setTeacherContracts] = useState<Record<string, number>>({});
  const [students, setStudents] = useState<Student[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [teacherFilter, setTeacherFilter] = useState<string>('all');
  const [selectedContract, setSelectedContract] = useState<Contract | null>(null);
  const [selectedTeacher, setSelectedTeacher] = useState<Teacher | null>(null);
  const [selectedTeacherForContracts, setSelectedTeacherForContracts] = useState<Teacher | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingContract, setEditingContract] = useState<Contract | null>(null);
  const [deletingContract, setDeletingContract] = useState<Contract | null>(null);
  const [selectedStudentForNewContract, setSelectedStudentForNewContract] = useState<string>('');
  const [allDiscounts, setAllDiscounts] = useState<ContractDiscount[]>([]);

  // Memoize current teacher lookup
  const currentTeacher = useMemo(() => 
    profile?.id ? teachers.find(t => t.profile_id === profile.id) : undefined, 
    [profile, teachers]
  );

  // Filter students for contract form based on context
  const studentsForContractForm = useMemo(() => {
    if (isAdmin) {
      // Admins can see all students globally for contract creation
      return students;
    } else if (profile?.role === 'teacher' && currentTeacher) {
      // Teacher view - show only students with contracts assigned to this teacher
      return students.filter(s => s.contracts?.some(c => c.teacher?.id === currentTeacher.id));
    }
    return [];
  }, [isAdmin, students, profile, currentTeacher]);

  useEffect(() => {
    const initializeData = async () => {
      setLoading(true);
      
      try {
        // Use Promise.all to fetch all initial data concurrently
        const promises = [
          fetchTeachers(),
          fetchStudents()
        ];

        // For teachers, also fetch contracts immediately
        // For admins, fetch teacher contract counts
        if (!isAdmin) {
          promises.push(fetchContracts());
        } else {
          promises.push(fetchTeacherContractCounts());
        }

        await Promise.all(promises);
      } catch (error) {
        console.error('Error initializing data:', error);
        toast.error('Fehler beim Laden der Daten');
      } finally {
        setLoading(false);
      }
    };

    initializeData();
  }, [isAdmin]);

  useEffect(() => {
    const fetchAllDiscounts = async () => {
      const { data, error } = await supabase
        .from('contract_discounts')
        .select('*')
        .order('name');
      if (!error && data) setAllDiscounts(data);
    };
    fetchAllDiscounts();
  }, []);

  const fetchTeacherContractCounts = async () => {
    try {
      // Use a proper server-side query with JOIN and COUNT
      const { data, error } = await supabase.rpc('get_teacher_contract_counts');

      if (error) {
        console.error('Error fetching contract counts via RPC:', error);
        
        // Fallback to manual counting if RPC fails
        const { data: contractData, error: contractError } = await supabase
          .from('contracts')
          .select(`
            id,
            teacher_id
          `);

        if (contractError) {
          console.error('Error fetching contract counts:', contractError);
          return;
        }

        // Count contracts per teacher manually
        const counts: Record<string, number> = {};
        contractData?.forEach(contract => {
          const teacherId = contract.teacher_id;
          if (typeof teacherId === 'string') {
            counts[teacherId] = (counts[teacherId] || 0) + 1;
          }
        });

        setTeacherContracts(counts);
        return;
      }

      // Convert RPC result to our expected format
      const counts: Record<string, number> = {};
      data?.forEach((row: { teacher_id: string; contract_count: number }) => {
        if (typeof row.teacher_id === 'string') {
          counts[row.teacher_id] = row.contract_count;
        }
      });

      setTeacherContracts(counts);
    } catch (error) {
      console.error('Error fetching teacher contract counts:', error);
      
      // Final fallback - direct query
      try {
        const { data: contractData, error: contractError } = await supabase
          .from('contracts')
          .select(`
            id,
            teacher_id
          `);

        if (!contractError && contractData) {
          const counts: Record<string, number> = {};
          contractData.forEach(contract => {
            const teacherId = contract.teacher_id;
            if (typeof teacherId === 'string') {
              counts[teacherId] = (counts[teacherId] || 0) + 1;
            }
          });
          setTeacherContracts(counts);
        }
      } catch (fallbackError) {
        console.error('Fallback query also failed:', fallbackError);
      }
    }
  };

  const fetchContracts = async (teacherId?: string) => {
    try {
      let query = supabase
        .from('contracts')
        .select(`
          *,
          student:students!fk_contracts_student_id(
            id, name, instrument, status, bank_id
          ),
          teacher:teachers!contracts_teacher_id_fkey(id, name, bank_id),
          contract_variant:contract_variants(
            id, name, duration_months, group_type, session_length_minutes, total_lessons,
            monthly_price, one_time_price,
            contract_category:contract_categories(id, name, display_name)
          ),
          lessons:lessons(id, lesson_number, date, is_available, comment)
        `)
        .order('created_at', { ascending: false });

      // Filter by specific teacher (for admin view) or current teacher (for teacher view)
      if (teacherId) {
        query = query.eq('teacher_id', teacherId);
      } else if (profile?.role === 'teacher' && currentTeacher?.id) {
        query = query.eq('teacher_id', currentTeacher.id);
      }

      const { data, error } = await query;

      if (error) {
        toast.error('Fehler beim Laden der Verträge', { description: error.message });
        return;
      }

      // Debug: Check if bank_ids are included in the fetched data
      if (data && data.length > 0) {
        console.log('Contracts Debug - First contract data:', {
          studentBankId: data[0].student?.bank_id,
          teacherBankId: data[0].student?.teacher?.bank_id,
          studentName: data[0].student?.name,
          teacherName: data[0].student?.teacher?.name
        });
      }

      setContracts(data || []);
    } catch (error) {
      console.error('Error fetching contracts:', error);
      toast.error('Fehler beim Laden der Verträge');
    }
  };

  const fetchTeachers = async () => {
    try {
      const { data, error } = await supabase
        .from('teachers')
        .select('*')
        .order('name');

      if (error) {
        toast.error('Fehler beim Laden der Lehrer', { description: error.message });
        return;
      }

      setTeachers(data || []);
    } catch (error) {
      console.error('Error fetching teachers:', error);
    }
  };

  const fetchStudents = async () => {
    try {
      let query = supabase
        .from('students')
        .select(`
          id, name, instrument, email, phone, status, bank_id, created_at,
          contracts:contracts!fk_contracts_student_id(
            id,
            teacher:teachers!contracts_teacher_id_fkey(id, name, profile_id, instrument, bank_id)
          )
        `)
        .order('name');

      // Filter by teacher for non-admin users
      if (profile?.role === 'teacher' && currentTeacher?.id) {
        query = query.eq('contracts.teacher_id', currentTeacher.id);
      }

      const { data, error } = await query;

      if (error) {
        toast.error('Fehler beim Laden der Schüler', { description: error.message });
        return;
      }

      setStudents((data as unknown as Student[]) || []);
    } catch (error) {
      console.error('Error fetching students:', error);
    }
  };

  const handleDeleteContract = async (contractId: string) => {
    setLoading(true);
    try {
      const { error } = await supabase.from('contracts').delete().eq('id', contractId);
      if (error) {
        throw new Error(error.message || 'Fehler beim Löschen des Vertrags');
      }
      toast.success('Vertrag gelöscht');

      // Refetch contracts after deletion
      // ✨ Preserve current teacher filter
      await fetchContracts(
        selectedTeacherForContracts ? selectedTeacherForContracts.id : undefined
      );
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unbekannter Fehler';
      toast.error('Fehler beim Löschen des Vertrags: ' + errorMessage);
    } finally {
      setLoading(false);
    }
  };

  const canEditContract = () => {
    // FIXED: Only admins can edit contracts
    return isAdmin;
  };

  const canDeleteContract = () => {
    // FIXED: Only admins can delete contracts
    return isAdmin;
  };

  const canAddContract = () => {
    // FIXED: Only admins can add contracts
    return isAdmin;
  };

  // Enhanced progress calculation that considers lesson availability
  const getAttendanceProgress = (contract: Contract) => {
    if (!contract.lessons || contract.lessons.length === 0) {
      // Fallback to old calculation if lessons not loaded
      const [current, total] = contract.attendance_count.split('/').map(Number);
      return { current, total, percentage: Math.round((current / total) * 100) };
    }

    // Calculate based on actual lesson data
    const availableLessons = contract.lessons.filter(lesson => lesson.is_available !== false);
    const completedLessons = availableLessons.filter(lesson => lesson.date).length;
    const totalAvailable = availableLessons.length;
    
    const percentage = totalAvailable > 0 ? Math.round((completedLessons / totalAvailable) * 100) : 0;
    
    return {
      current: completedLessons,
      total: totalAvailable,
      percentage,
      unavailable: contract.lessons.length - totalAvailable
    };
  };

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

  const getContractPriceDisplay = (contract: Contract) => {
    // Teachers cannot see price information
    if (!isAdmin) {
      return null;
    }

    // First check if we have the calculated final_price
    if (contract.final_price && contract.payment_type) {
      return {
        price: contract.final_price,
        type: contract.payment_type,
        hasDiscount: (contract.custom_discount_percent && contract.custom_discount_percent > 0) || (contract.discount_ids && contract.discount_ids.length > 0)
      };
    }

    // Fallback to contract variant pricing
    if (contract.contract_variant) {
      if (contract.contract_variant.monthly_price) {
        return {
          price: contract.contract_variant.monthly_price,
          type: 'monthly' as const,
          hasDiscount: false
        };
      } else if (contract.contract_variant.one_time_price) {
        return {
          price: contract.contract_variant.one_time_price,
          type: 'one_time' as const,
          hasDiscount: false
        };
      }
    }

    return null;
  };

  const getDiscountDisplay = (contract: Contract) => {
    if (!isAdmin) return null;
    const discounts = [];
    // Add standard discounts with actual percentages
    if (contract.discount_ids && contract.discount_ids.length > 0) {
      const found = contract.discount_ids
        .map(id => allDiscounts.find(d => d.id === id))
        .filter(Boolean) as ContractDiscount[];
      if (found.length > 0) {
        discounts.push(
          `Standard: ${found.map(d => `${d.discount_percent}%`).join(', ')}`
        );
      }
    }
    // Add custom discount
    if (contract.custom_discount_percent && contract.custom_discount_percent > 0) {
      discounts.push(`Custom: ${contract.custom_discount_percent}%`);
    }
    return discounts.length > 0 ? discounts.join(', ') : null;
  };

  const formatPrice = (price: number, type: 'monthly' | 'one_time') => {
    const formattedPrice = price.toFixed(2);
    return type === 'monthly' ? `${formattedPrice}€ / Monat` : `${formattedPrice}€ einmalig`;
  };

  // Helper: determine if a contract is completed (progress 100%)
  const isContractCompleted = (contract: Contract) => {
    const progress = getAttendanceProgress(contract);
    return progress.percentage === 100;
  };

  // Helper: compute conditional classes for completed vs active contracts
  const getContractCardStyling = (contract: Contract) => {
    const completed = isContractCompleted(contract);
    return {
      progressBarClass: completed ? 'bg-gray-400' : 'bg-brand-primary',
      buttonClass: completed
        ? 'w-full bg-gray-400 hover:bg-gray-500 focus:ring-gray-400 text-white'
        : 'w-full bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary',
      statusBadgeVariant: (completed ? 'secondary' : 'default') as 'secondary' | 'default',
      priceTextClass: completed ? 'text-gray-600' : 'text-brand-primary',
    };
  };

  const handleDownloadPDF = async (contract: Contract) => {
    try {
      toast.info('PDF-Download wird vorbereitet...', {
        description: `Vertrag für ${contract.student?.name} wird als PDF generiert.`
      });

      // Always refetch a fresh contract snapshot including all new fields
      const { data: freshContract, error: freshError } = await supabase
        .from('contracts')
        .select(`
          id, billing_cycle, paid_at, paid_through, first_payment_date, term_start, term_end, term_label, cancelled_at,
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
        .eq('id', contract.id)
        .single();

      if (freshError || !freshContract) {
        console.warn('PDF: could not fetch fresh contract, falling back to in-memory one', freshError);
      }

      const baseContract = freshContract || contract;

      // Fetch detailed lesson data if not already loaded
      let contractWithLessons = baseContract;
      if (!baseContract.lessons || baseContract.lessons.length === 0) {
        const { data: lessonsData, error: lessonsError } = await supabase
          .from('lessons')
          .select('*')
          .eq('contract_id', baseContract.id)
          .order('lesson_number');

        if (lessonsError) {
          console.error('Error fetching lessons for PDF:', lessonsError);
          toast.error('Fehler beim Laden der Stundendaten für PDF');
          return;
        }

        contractWithLessons = {
          ...baseContract,
          lessons: lessonsData || []
        } as Contract;
      }

      // Fetch discount details if discount_ids exist
      let appliedDiscounts: ContractDiscount[] = [];
      if (contractWithLessons.discount_ids && contractWithLessons.discount_ids.length > 0) {
        const { data: discountsData, error: discountsError } = await supabase
          .from('contract_discounts')
          .select('*')
          .in('id', contractWithLessons.discount_ids);

        if (discountsError) {
          console.error('Error fetching discounts for PDF:', discountsError);
          toast.warning('Ermäßigungsdaten konnten nicht geladen werden');
        } else {
          appliedDiscounts = discountsData || [];
        }
      }

      // Prepare contract data for PDF with all required information
      const contractToExport: PDFContractData = {
        ...contractWithLessons,
        applied_discounts: appliedDiscounts
      } as PDFContractData;

      // Check admin role and fetch bank_ids if needed
      const { data: { user } } = await supabase.auth.getUser();
      const { data: profileData } = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user?.id)
        .single();
      
      const isAdmin = profileData?.role === 'admin';
      console.log('PDF Debug - ContractsTab admin check:', { profileData, isAdmin });
      console.log('PDF Debug - Contract meta for PDF:', {
        billing_cycle: (contractToExport as any).billing_cycle,
        paid_at: (contractToExport as any).paid_at,
        paid_through: (contractToExport as any).paid_through,
        term_start: (contractToExport as any).term_start,
        term_end: (contractToExport as any).term_end,
        term_label: (contractToExport as any).term_label,
        cancelled_at: (contractToExport as any).cancelled_at,
      });

      // Generate and download PDF
      await generateContractPDF(contractToExport, { showBankIds: isAdmin });
      
      toast.success('PDF erfolgreich heruntergeladen', {
        description: `Vertrag für ${contract.student?.name} wurde als PDF gespeichert.`
      });
      
    } catch (error) {
      console.error('Error downloading PDF:', error);
      toast.error('PDF konnte nicht generiert werden. Bitte erneut versuchen.');
    }
  };

  const handleTeacherSelect = (teacher: Teacher) => {
    setSelectedTeacherForContracts(teacher);
    setLoading(true);
    fetchContracts(teacher.id).finally(() => setLoading(false));
  };

  const handleBackToTeachers = () => {
    setSelectedTeacherForContracts(null);
    setContracts([]);
  };

  // Function to refresh data after contract operations
  const refreshContractData = () => {
    if (selectedTeacherForContracts) {
      fetchContracts(selectedTeacherForContracts.id);
    } else {
      fetchContracts();
    }
    
    // Always update counts for admin view
    if (isAdmin) {
      fetchTeacherContractCounts();
    }
    
    fetchStudents();
  };

  const filteredContracts = contracts.filter(contract => {
    const matchesSearch = contract.student?.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         contract.student?.instrument.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         contract.student?.teacher?.name.toLowerCase().includes(searchTerm.toLowerCase());
    
    const matchesStatus = statusFilter === 'all' || contract.status === statusFilter;
    
    // Updated type filtering to work with both new and legacy systems
    const contractType = contract.contract_variant?.contract_category?.name || contract.type || '';
    const matchesType = typeFilter === 'all' || contractType === typeFilter;
    
    const matchesTeacher = teacherFilter === 'all' || contract.teacher?.id === teacherFilter;
    
    return matchesSearch && matchesStatus && matchesType && matchesTeacher;
  });

  const filteredTeachers = teachers.filter(teacher => {
    const matchesSearch = teacher.name.toLowerCase().includes(searchTerm.toLowerCase());
    return matchesSearch;
  });

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <div className="flex items-center gap-2">
            {isAdmin && selectedTeacherForContracts && (
              <Button
                variant="ghost"
                size="sm"
                onClick={handleBackToTeachers}
                className="p-2 hover:bg-gray-100"
              >
                <ArrowLeft className="h-4 w-4" />
              </Button>
            )}
            <div>
              <h1 className="text-2xl font-bold text-gray-900">
                {isAdmin && selectedTeacherForContracts 
                  ? `Verträge - ${selectedTeacherForContracts.name}`
                  : 'Vertragsverwaltung'
                }
              </h1>
              <p className="text-gray-600">
                {isAdmin && !selectedTeacherForContracts
                  ? 'Wählen Sie einen Lehrer aus, um dessen Verträge anzuzeigen'
                  : !isAdmin
                  ? 'Ihre Verträge anzeigen und Stunden verfolgen'
                  : 'Stundenverlauf verfolgen und Schülerverträge verwalten'
                }
              </p>
            </div>
          </div>
        </div>
        
        {/* Show add button only for admins when viewing contracts */}
        {canAddContract() && (selectedTeacherForContracts || !isAdmin) && (
          <Button 
            onClick={() => setShowAddForm(true)} 
            className="bg-brand-primary hover:bg-brand-primary/90 focus:ring-brand-primary"
          >
            <Plus className="h-4 w-4 mr-2" />
            Neuer Vertrag
          </Button>
        )}
      </div>


      {/* Filters */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex flex-col md:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
                <Input
                  placeholder={
                    isAdmin && !selectedTeacherForContracts
                      ? "Suchen nach Lehrername..."
                      : "Suchen nach Schülername, Instrument oder Lehrer..."
                  }
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10 focus:ring-brand-primary focus:border-brand-primary"
                />
              </div>
            </div>
            
            {/* Show contract filters only when viewing contracts */}
            {(selectedTeacherForContracts || !isAdmin) && (
              <>
                <Select value={statusFilter} onValueChange={setStatusFilter}>
                  <SelectTrigger className="w-full md:w-40">
                    <SelectValue placeholder="Status" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Alle Status</SelectItem>
                    <SelectItem value="active">Aktiv</SelectItem>
                    <SelectItem value="completed">Abgeschlossen</SelectItem>
                  </SelectContent>
                </Select>
                <Select value={typeFilter} onValueChange={setTypeFilter}>
                  <SelectTrigger className="w-full md:w-40">
                    <SelectValue placeholder="Typ" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Alle Typen</SelectItem>
                    <SelectItem value="ten_lesson_card">10er Karte</SelectItem>
                    <SelectItem value="half_year_contract">Halbjahr</SelectItem>
                    <SelectItem value="supplement_program">Ergänzung</SelectItem>
                    <SelectItem value="repetition_workshop">Workshop</SelectItem>
                    <SelectItem value="trial_package">Schnupper</SelectItem>
                  </SelectContent>
                </Select>
                {isAdmin && !selectedTeacherForContracts && (
                  <Select value={teacherFilter} onValueChange={setTeacherFilter}>
                    <SelectTrigger className="w-full md:w-40">
                      <SelectValue placeholder="Lehrer" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Alle Lehrer</SelectItem>
                      {teachers.map(teacher => (
                        <SelectItem key={teacher.id} value={teacher.id}>
                          {teacher.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              </>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Content based on role and selection */}
      {isAdmin && !selectedTeacherForContracts ? (
        /* Admin Teacher List View */
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Users className="h-5 w-5 text-brand-primary" />
            <h2 className="text-xl font-semibold text-gray-900">Lehrer auswählen</h2>
            <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200">
              {filteredTeachers.length} Lehrer
            </Badge>
          </div>
          
          <Card>
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Lehrername</TableHead>
                    <TableHead className="text-center">Anzahl Verträge</TableHead>
                    <TableHead className="text-right">Aktion</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredTeachers.map((teacher) => {
                    const contractCount = teacherContracts[teacher.id] || 0;
                    
                    return (
                      <TableRow 
                        key={teacher.id} 
                        className="hover:bg-gray-50 cursor-pointer"
                        onClick={() => handleTeacherSelect(teacher)}
                      >
                        <TableCell className="font-medium">{teacher.name}</TableCell>
                        <TableCell className="text-center">
                          <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200">
                            {contractCount}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          <Button
                            variant="outline"
                            size="sm"
                            className="bg-brand-primary text-white hover:bg-brand-primary/90 border-brand-primary"
                            onClick={(e) => {
                              e.stopPropagation();
                              handleTeacherSelect(teacher);
                            }}
                          >
                            Alle Verträge anzeigen
                          </Button>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>

              {filteredTeachers.length === 0 && (
                <div className="text-center py-12">
                  <Users className="h-12 w-12 text-gray-300 mx-auto mb-4" />
                  <p className="text-gray-500">Keine Lehrer gefunden, die Ihren Kriterien entsprechen.</p>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      ) : (
        /* Contracts Grid View */
        <div className="space-y-4">
          {/* Contract summary for selected teacher */}
          {selectedTeacherForContracts && (
            <Card className="bg-gray-50 border-gray-200">
              <CardContent className="pt-6">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <Users className="h-5 w-5 text-gray-600" />
                    <div>
                      <h3 className="font-medium text-gray-900">{selectedTeacherForContracts.name}</h3>
                      <p className="text-sm text-gray-700">{filteredContracts.length} Vertrag{filteredContracts.length !== 1 ? 'e' : ''}</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-sm text-gray-600">Für Buchhaltung optimiert</p>
                    <p className="text-xs text-gray-500">Alle Verträge dieses Lehrers</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}
          
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3 auto-rows-fr">
            {filteredContracts.map((contract) => {
              const progress = getAttendanceProgress(contract);
              const priceInfo = getContractPriceDisplay(contract);
              const { progressBarClass, buttonClass, statusBadgeVariant, priceTextClass } = getContractCardStyling(contract);
              
              return (
                <Card key={contract.id} className="hover:shadow-md transition-shadow h-full flex flex-col">
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                    <CardTitle className="text-lg font-medium">
                      {contract.student?.name || 'Unbekannter Schüler'}
                    </CardTitle>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button 
                          variant="ghost" 
                          className="bg-transparent border-none shadow-none p-0 h-auto w-auto text-black hover:bg-transparent hover:text-black"
                        >
                          <MoreHorizontal className="h-5 w-5" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem onClick={() => setSelectedContract(contract)}>
                          <Calendar className="h-4 w-4 mr-2" />
                          Stunden verfolgen
                        </DropdownMenuItem>
                        {canEditContract() && (
                          <DropdownMenuItem onClick={() => setEditingContract(contract)}>
                            <Edit className="h-4 w-4 mr-2" />
                            Vertrag bearbeiten
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuItem onClick={() => handleDownloadPDF(contract)}>
                          <Download className="h-4 w-4 mr-2" />
                          Als PDF herunterladen
                        </DropdownMenuItem>
                        {canDeleteContract() && (
                          <DropdownMenuItem 
                            onClick={() => handleDeleteContract(contract.id)}
                            className="text-red-600"
                          >
                            <Trash2 className="h-4 w-4 mr-2" />
                            Vertrag löschen
                          </DropdownMenuItem>
                        )}
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </CardHeader>
                  <CardContent className="flex-1">
                    <div className="space-y-3">
                      {/* Type */}
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-medium text-gray-600">Typ</span>
                        <span className="text-sm font-medium text-gray-900">
                          {getContractTypeDisplaySafe(contract)}
                        </span>
                      </div>
                      
                      {/* Status row (label left, status pill right) */}
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-medium text-gray-600">Status</span>
                        <Badge variant={statusBadgeVariant}>
                          {contract.student?.status === 'active' ? 'Aktiv' : 'Inaktiv'}
                        </Badge>
                      </div>

                      {/* Laufzeit */}
                      {(contract.term_label || contract.term_start || contract.term_end) && (
                        <div className="flex items-center justify-between">
                          <span className="text-sm font-medium text-gray-600">Laufzeit</span>
                          <span className="text-sm font-medium text-gray-900">
                            {contract.term_label || `${formatMonthYearShort(contract.term_start)}${contract.term_start && contract.term_end ? ' – ' : ''}${formatMonthYearShort(contract.term_end)}`}
                          </span>
                        </div>
                      )}
                      
                      {/* Instrument */}
                      {contract.student?.instrument && (
                        <div className="flex items-center justify-between">
                          <span className="text-sm font-medium text-gray-600">Instrument</span>
                          <span className="text-sm">{contract.student.instrument}</span>
                        </div>
                      )}
                      
                      {/* Preis */}
                      {priceInfo && (
                        <div className="flex items-center justify-between">
                          <span className="text-sm font-medium text-gray-600">Preis</span>
                          <div className="flex items-center gap-2">
                            <span className={`text-sm font-medium ${priceTextClass}`}>
                              {formatPrice(priceInfo.price, priceInfo.type)}
                            </span>
                            {priceInfo.hasDiscount && (
                              <Badge variant="outline" className="text-xs bg-green-50 text-green-700 border-green-200">
                                Ermäßigt
                              </Badge>
                            )}
                          </div>
                        </div>
                      )}

                      {/* Ermäßigungen (only if present) */}
                      {isAdmin && getDiscountDisplay(contract) && (
                        <div className="flex items-center justify-between">
                          <span className="text-sm font-medium text-gray-600">Ermäßigungen</span>
                          <span className="text-sm text-green-600">
                            {getDiscountDisplay(contract)}
                          </span>
                        </div>
                      )}
                      {isAdmin && !getDiscountDisplay(contract) && (
                        <div className="flex items-center justify-between min-h-[24px]"></div>
                      )}

                      {/* Payment + Cancellation badges row (moved here) */}
                      {(contract.billing_cycle === 'upfront' && contract.paid_at) ||
                       (contract.billing_cycle === 'monthly' && contract.first_payment_date) ||
                       contract.cancelled_at ? (
                        <div className="flex flex-wrap items-center gap-2 mt-2">
                          {contract.billing_cycle === 'upfront' && contract.paid_at && (
                            <Badge variant="secondary">Bezahlt am {fmtDate(contract.paid_at)}</Badge>
                          )}
                          {contract.billing_cycle === 'monthly' && contract.first_payment_date && (
                            <Badge variant="secondary">Erste Zahlung {fmtDate(contract.first_payment_date)}</Badge>
                          )}
                          {contract.cancelled_at && (
                            <Badge variant="outline" className="text-red-600 border-red-300">Gekündigt zum {fmtDate(contract.cancelled_at)}</Badge>
                          )}
                        </div>
                      ) : null}
                    </div>
                  </CardContent>

                  {/* Footer pinned to bottom */}
                  <div className="mt-auto border-t px-6 py-4">
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-medium text-gray-600">Fortschritt</span>
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-medium">
                            {progress.current}/{progress.total}
                          </span>
                          {Number(progress.unavailable) > 0 && (
                            <Badge variant="outline" className="text-xs bg-gray-50 text-gray-600 border-gray-200">
                              {progress.unavailable} nicht verfügbar
                            </Badge>
                          )}
                        </div>
                      </div>
                      <div className="w-full bg-gray-200 rounded-full h-2">
                        <div 
                          className={`${progressBarClass} h-2 rounded-full transition-all duration-300`}
                          style={{ width: `${progress.percentage}%` }}
                        />
                      </div>
                      <div className="flex justify-between items-center text-xs text-gray-500">
                        <span>{progress.percentage}% abgeschlossen</span>
                        {Number(progress.unavailable) > 0 && (
                          <span className="text-gray-500">
                            {progress.unavailable} Stunden ausgeschlossen
                          </span>
                        )}
                      </div>
                      <div className="pt-2">
                        <Button
                          onClick={() => setSelectedContract(contract)}
                          className={buttonClass}
                          size="sm"
                        >
                          <Clock className="h-4 w-4 mr-2" />
                          Fortschritt verfolgen
                        </Button>
                      </div>
                    </div>
                  </div>
                </Card>
              );
            })}
          </div>
          
          {filteredContracts.length === 0 && (
            <Card>
              <CardContent className="pt-6">
                <div className="text-center py-8">
                  <FileText className="h-12 w-12 text-gray-300 mx-auto mb-4" />
                  <p className="text-gray-500">
                    {selectedTeacherForContracts 
                      ? `Keine Verträge für ${selectedTeacherForContracts.name} gefunden.`
                      : !isAdmin && contracts.length === 0
                      ? 'Ihnen sind noch keine Verträge zugewiesen.'
                      : 'Keine Verträge gefunden, die Ihren Kriterien entsprechen.'
                    }
                  </p>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Add Contract Dialog - Only show for admins */}
      {isAdmin && (
        <Dialog open={showAddForm} onOpenChange={setShowAddForm}>
          <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Neuen Vertrag erstellen</DialogTitle>
            </DialogHeader>
            <ContractForm
              students={studentsForContractForm}
              teachers={teachers}
              initialStudentId={selectedStudentForNewContract}
              onSuccess={() => {
                setShowAddForm(false);
                setSelectedStudentForNewContract('');
                refreshContractData();
              }}
              onCancel={() => {
                setShowAddForm(false);
                setSelectedStudentForNewContract('');
              }}
            />
          </DialogContent>
        </Dialog>
      )}

      {/* Edit Contract Dialog - Only show for admins */}
      {isAdmin && (
        <Dialog open={!!editingContract} onOpenChange={() => setEditingContract(null)}>
          <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Vertrag bearbeiten</DialogTitle>
            </DialogHeader>
            {editingContract && (
              <ContractForm
                contract={editingContract}
                students={studentsForContractForm}
                teachers={teachers}
                onSuccess={() => {
                  setEditingContract(null);
                  refreshContractData();
                }}
                onCancel={() => setEditingContract(null)}
              />
            )}
          </DialogContent>
        </Dialog>
      )}

      {/* Delete Contract Confirmation Modal */}
      {deletingContract && (
        <DeleteContractConfirmationModal
          open={!!deletingContract}
          onClose={() => setDeletingContract(null)}
          onConfirm={() => handleDeleteContract(deletingContract.id)}
          contract={deletingContract}
        />
      )}

      {/* Lesson Tracker Modal */}
      {selectedContract && (
        <LessonTrackerModal
          contract={selectedContract}
          open={!!selectedContract}
          onClose={() => setSelectedContract(null)}
          onUpdate={async () => {
            // Add a short delay to allow backend to update
            await new Promise(resolve => setTimeout(resolve, 750));
            if (selectedTeacherForContracts) {
              fetchContracts(selectedTeacherForContracts.id);
            } else {
              fetchContracts();
            }
          }}
        />
      )}

      {/* Teacher Contracts Modal */}
      {selectedTeacher && (
        <TeacherContractsModal
          teacher={selectedTeacher}
          open={!!selectedTeacher}
          onClose={() => setSelectedTeacher(null)}
        />
      )}
    </div>
  );
}