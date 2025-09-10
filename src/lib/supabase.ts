import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

// Check if environment variables are properly configured
export const isSupabaseConfigured = !!(supabaseUrl && supabaseAnonKey && 
  supabaseUrl !== 'https://your-project-id.supabase.co' && 
  supabaseAnonKey !== 'your-anon-key-here');

// Create a fallback client if environment variables are missing
const fallbackUrl = 'https://example.supabase.co';
const fallbackKey = 'fallback-key';

export const supabase = createClient(
  supabaseUrl || fallbackUrl, 
  supabaseAnonKey || fallbackKey
);

// Database types
export interface Profile {
  id: string;
  email: string;
  full_name: string;
  role: 'admin' | 'teacher';
  created_at: string;
}

export interface Teacher {
  id: string;
  profile_id?: string;
  name: string;
  email: string;
  instrument: string[];
  phone?: string;
  student_count: number;
  bank_id: string; // Now a text string, always present
  created_at: string;
}

export interface Student {
  id: string;
  name: string;
  instrument: string;
  email?: string;
  phone?: string;
  teacher_id?: string; // Deprecated, use contracts.teacher_id
  contract_id?: string; // Deprecated, use contracts array
  bank_id: string; // Now a text string, always present
  status: 'active' | 'inactive';
  created_at: string;
  teacher?: Teacher; // Deprecated, use contracts.teacher
  contract?: Contract; // Deprecated, use contracts array
  contracts?: Contract[]; // New: array of contracts with different teachers
}

export interface ContractCategory {
  id: string;
  name: string;
  display_name: string;
  description?: string;
  created_at: string;
}

export interface ContractVariant {
  id: string;
  contract_category_id: string;
  name: string;
  duration_months?: number; // NULL for flexible duration
  group_type: 'single' | 'group' | 'duo' | 'varies';
  session_length_minutes?: number; // NULL for varies
  total_lessons?: number;
  monthly_price?: number; // NULL if one-time payment
  one_time_price?: number; // NULL if monthly payment
  notes?: string;
  is_active: boolean;
  created_at: string;
  contract_category?: ContractCategory;
}

export interface ContractDiscount {
  id: string;
  name: string;
  discount_percent: number;
  conditions?: string;
  is_active: boolean;
  created_at: string;
}

export interface Contract {
  id: string;
  student_id: string;
  teacher_id?: string; // New: direct teacher reference
  type: string; // Required field for legacy compatibility
  contract_variant_id: string;
  discount_ids?: string[];
  final_price?: number;
  payment_type?: 'monthly' | 'one_time';
  status: 'active' | 'completed';
  attendance_count: string;
  attendance_dates: string[];
  created_at: string;
  updated_at: string;
  custom_discount_percent?: number; // New field for custom discounts
  student?: Student;
  teacher?: Teacher; // New: teacher object
  contract_variant?: ContractVariant;
  lessons?: Lesson[];
  applied_discounts?: ContractDiscount[];
  // NEW optional metadata fields
  billing_cycle?: 'monthly' | 'upfront' | null;
  paid_at?: string | null;
  paid_through?: string | null;
  term_start?: string | null;
  term_end?: string | null;
  term_label?: string | null;
  cancelled_at?: string | null;
  private_notes?: string | null;
}

export interface Lesson {
  id: string;
  contract_id: string;
  lesson_number: number;
  date?: string;
  comment?: string;
  is_available: boolean;
  created_at: string;
  updated_at: string;
}

export interface TrialAppointment {
  id: string;
  student_name: string;
  instrument: string;
  phone?: string;
  email?: string;
  status: 'open' | 'assigned' | 'accepted';
  teacher_id?: string;
  created_by?: string;
  created_at: string;
  teacher?: Teacher;
  created_by_profile?: Profile;
}

// Legacy interface for backward compatibility (maps to TrialAppointment)
export interface TrialLesson {
  id: string;
  student_name: string;
  instrument: string;
  phone?: string;
  email?: string;
  status: 'open' | 'assigned' | 'accepted';
  assigned_teacher_id?: string; // Legacy field name
  created_by?: string;
  created_at: string;
  assigned_teacher?: Teacher; // Legacy field name
  created_by_profile?: Profile;
}

export interface Notification {
  id: string;
  type: 'contract_fulfilled' | 'assigned_trial' | 'declined_trial' | 'accepted_trial';
  contract_id?: string;
  trial_appointment_id?: string;
  teacher_id?: string;
  student_id?: string;
  message: string;
  is_read: boolean;
  created_at: string;
  updated_at: string;
  contract?: Contract;
  trial_appointment?: TrialAppointment;
  teacher?: Teacher;
  student?: Student;
}

export interface BankId {
  id: string;
  profile_id: string;
  reference_id: string;
  entity_type: 'teacher' | 'student';
  entity_id: string;
  account_holder_name?: string;
  created_at: string;
}

export interface ContractPricing {
  base_monthly_price?: number;
  base_one_time_price?: number;
  total_discount_percent: number;
  final_monthly_price?: number;
  final_one_time_price?: number;
  payment_type: 'monthly' | 'one_time';
}

// PDF Generation types
export interface PDFContractData extends Contract {
  lessons?: Lesson[];
  applied_discounts?: ContractDiscount[];
}

// Trial appointment helper functions
export const acceptTrial = async (trialId: string) => {
  const { data, error } = await supabase.rpc('accept_trial', {
    _trial_id: trialId
  });
  
  return { data, error };
};

export const declineTrial = async (trialId: string) => {
  const { data, error } = await supabase.rpc('decline_trial', {
    _trial_id: trialId
  });
  
  return { data, error };
};

// Notification helper functions
export const markNotificationAsRead = async (notificationId: string) => {
  const { data, error } = await supabase.rpc('mark_notification_read', {
    notification_id: notificationId
  });
  
  return { data, error };
};

export const deleteNotification = async (notificationId: string) => {
  const { data, error } = await supabase.rpc('delete_notification', {
    notification_id: notificationId
  });
  
  return { data, error };
};

// Contract helper functions
export const getContractDuration = (variant: ContractVariant) => {
  if (!variant.duration_months) {
    return 'Flexibel';
  }
  
  if (variant.duration_months === 6) {
    return '6 Monate';
  } else if (variant.duration_months === 12) {
    return '12 Monate';
  } else if (variant.duration_months === 24) {
    return '2 Jahre';
  } else if (variant.duration_months === 36) {
    return '3 Jahre';
  }
  
  return `${variant.duration_months} Monate`;
};

export const getContractLessonCount = (variant: ContractVariant) => {
  return variant.total_lessons || 0;
};

export const getContractTypeDisplay = (variant: ContractVariant) => {
  return variant.name;
};

export const getContractCategoryDisplay = (category: ContractCategory) => {
  return category.display_name;
};

// Map modern contract category names to legacy type values for database constraint
export const getLegacyContractType = (categoryName: string): string => {
  switch (categoryName) {
    case 'ten_lesson_card':
    case '10er_karte':
    case 'zehnerkarte':
      return 'ten_class_card';
    case 'half_year_contract':
    case 'halbjahr':
    case 'halbjahresvertrag':
    case 'semester':
      return 'half_year';
    default:
      // Default to ten_class_card for unknown categories to avoid constraint violation
      return 'ten_class_card';
  }
};

// Contract pricing helper
export const calculateContractPrice = async (
  variantId: string, 
  discountIds: string[] = [],
  customDiscount?: ContractDiscount
): Promise<ContractPricing | null> => {
  try {
    // If we have a custom discount, we need to calculate manually
    if (customDiscount) {
      // Get the variant details
      const { data: variantData, error: variantError } = await supabase
        .from('contract_variants')
        .select('*')
        .eq('id', variantId)
        .single();
      
      if (variantError) {
        console.error('Error fetching variant:', variantError);
        return null;
      }
      
      // Get other discounts (excluding custom)
      const regularDiscountIds = discountIds.filter(id => id !== customDiscount.id);
      let totalDiscountPercent = customDiscount.discount_percent;
      
      if (regularDiscountIds.length > 0) {
        const { data: discountsData, error: discountsError } = await supabase
          .from('contract_discounts')
          .select('discount_percent')
          .in('id', regularDiscountIds)
          .eq('is_active', true);
        
        if (discountsError) {
          console.error('Error fetching discounts:', discountsError);
        } else if (discountsData) {
          // Add other discount percentages
          totalDiscountPercent += discountsData.reduce((sum, d) => sum + d.discount_percent, 0);
        }
      }
      
      // Ensure discount doesn't exceed 100%
      totalDiscountPercent = Math.min(totalDiscountPercent, 100);
      
      // Calculate final prices
      const result: ContractPricing = {
        base_monthly_price: variantData.monthly_price,
        base_one_time_price: variantData.one_time_price,
        total_discount_percent: totalDiscountPercent,
        payment_type: variantData.monthly_price ? 'monthly' : 'one_time'
      };
      
      if (variantData.monthly_price) {
        result.final_monthly_price = variantData.monthly_price * (1 - totalDiscountPercent / 100);
      } else if (variantData.one_time_price) {
        result.final_one_time_price = variantData.one_time_price * (1 - totalDiscountPercent / 100);
      }
      
      return result;
    } else {
      // Use the RPC function for standard discounts
      const { data, error } = await supabase.rpc('calculate_contract_price', {
        variant_id: variantId,
        discount_ids: discountIds.length > 0 ? discountIds : null
      });

      if (error) {
        console.error('Error calculating contract price:', error);
        return null;
      }

      return data?.[0] || null;
    }
  } catch (error) {
    console.error('Error calculating contract price:', error);
    return null;
  }
};

// Lesson helper functions
export const getLessonStatus = (lesson: Lesson) => {
  if (!lesson.is_available) {
    return 'unavailable';
  }
  
  if (lesson.date) {
    return lesson.comment ? 'completed-with-notes' : 'completed';
  }
  
  return 'pending';
};

export const getLessonStatusDisplay = (status: string) => {
  switch (status) {
    case 'completed-with-notes':
      return 'Complete + Notes';
    case 'completed':
      return 'Complete';
    case 'unavailable':
      return 'Unavailable';
    default:
      return 'Pending';
  }
};

export const getLessonStatusColor = (status: string) => {
  switch (status) {
    case 'completed-with-notes':
      return 'bg-green-100 text-green-800';
    case 'completed':
      return 'bg-blue-100 text-blue-800';
    case 'unavailable':
      return 'bg-red-100 text-red-800';
    default:
      return 'bg-gray-100 text-gray-800';
  }
};

// Legacy support functions (for backward compatibility during transition)
export const getLegacyContractTypeDisplay = (type: string) => {
  switch (type) {
    case 'ten_class_card':
      return '10er Karte';
    case 'half_year':
      return 'Halbjahresvertrag';
    default:
      return type;
  }
};

export const getLegacyContractDuration = (type: string) => {
  switch (type) {
    case 'ten_class_card':
      return 'Flexibel';
    case 'half_year':
      return '6 Monate';
    default:
      return 'Unbekannt';
  }
};

export const getLegacyContractLessonCount = (type: string) => {
  switch (type) {
    case 'ten_class_card':
      return 10;
    case 'half_year':
      return 18;
    default:
      return 0;
  }
};

// Re-export PDF generator function
export { generateContractPDF } from './pdfGenerator';