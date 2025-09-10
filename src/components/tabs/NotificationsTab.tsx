import { useState, useEffect } from 'react';
import { supabase, Notification, Contract, Student, markNotificationAsRead, deleteNotification, generateContractPDF, PDFContractData } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Bell, BellOff, Search, Download, Plus, Trash2, Eye, Calendar, User, FileText, CheckCircle, Clock, Check, UserCheck } from 'lucide-react';
import { LessonTrackerModal } from '@/components/modals/LessonTrackerModal';
import { ContractForm } from '@/components/forms/ContractForm';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { format } from 'date-fns';
import { de } from 'date-fns/locale';
import { toast } from 'sonner';

export function NotificationsTab() {
  const { isAdmin, profile } = useAuth();
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedContract, setSelectedContract] = useState<Contract | null>(null);
  const [showNewContractForm, setShowNewContractForm] = useState(false);
  const [selectedStudentForNewContract, setSelectedStudentForNewContract] = useState<string>('');
  const [students, setStudents] = useState<any[]>([]);

  useEffect(() => {
    if (isAdmin || profile?.role === 'teacher') {
      fetchNotifications();
      fetchStudents();
    }
  }, [isAdmin, profile]);

  const fetchNotifications = async () => {
    try {
      const { data, error } = await supabase
        .from('notifications')
        .select(`
          *,
          contract:contracts(
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
          ),
          trial_appointment:trial_appointments(
            *,
            teacher:teachers(id, name, instrument),
            created_by_profile:profiles!trial_appointments_created_by_fkey(id, full_name)
          ),
          student:students(id, name, instrument)
        `)
        .order('created_at', { ascending: false });

      if (error) {
        toast.error('Fehler beim Laden der Benachrichtigungen', { description: error.message });
        return;
      }

      setNotifications(data || []);
    } catch (error) {
      console.error('Error fetching notifications:', error);
      toast.error('Fehler beim Laden der Benachrichtigungen');
    } finally {
      setLoading(false);
    }
  };

  const fetchStudents = async () => {
    try {
      const { data, error } = await supabase
        .from('students')
        .select(`
          id, name, instrument, status, bank_id, created_at,
          contracts:contracts!fk_contracts_student_id(
            id,
            teacher:teachers!contracts_teacher_id_fkey(id, name, profile_id, instrument, bank_id)
          )
        `)
        .order('name');

      if (error) {
        console.error('Error fetching students:', error);
        return;
      }

      setStudents((data as unknown as Student[]) || []);
    } catch (error) {
      console.error('Error fetching students:', error);
    }
  };

  const handleMarkAsRead = async (notification: Notification) => {
    if (notification.is_read) return;

    try {
      const { error } = await markNotificationAsRead(notification.id);
      
      if (error) {
        toast.error('Fehler beim Markieren als gelesen', { description: error.message });
        return;
      }

      // Update local state
      setNotifications(prev => 
        prev.map(n => 
          n.id === notification.id 
            ? { ...n, is_read: true, updated_at: new Date().toISOString() }
            : n
        )
      );

      toast.success('Benachrichtigung als gelesen markiert');
    } catch (error) {
      console.error('Error marking notification as read:', error);
      toast.error('Fehler beim Markieren als gelesen');
    }
  };

  const handleDeleteNotification = async (notification: Notification) => {
    try {
      const { error } = await deleteNotification(notification.id);
      
      if (error) {
        toast.error('Fehler beim Löschen der Benachrichtigung', { description: error.message });
        return;
      }

      // Update local state
      setNotifications(prev => prev.filter(n => n.id !== notification.id));
      toast.success('Benachrichtigung gelöscht');
    } catch (error) {
      console.error('Error deleting notification:', error);
      toast.error('Fehler beim Löschen der Benachrichtigung');
    }
  };

  // Function to render clickable links in notification messages
  const renderNotificationMessage = (message: string) => {
    // Simple markdown link parser: [text](url)
    const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;
    const parts = [];
    let lastIndex = 0;
    let match;

    while ((match = linkRegex.exec(message)) !== null) {
      // Add text before the link
      if (match.index > lastIndex) {
        parts.push({
          type: 'text',
          content: message.slice(lastIndex, match.index)
        });
      }

      // Add the link
      parts.push({
        type: 'link',
        text: match[1],
        url: match[2]
      });

      lastIndex = match.index + match[0].length;
    }

    // Add remaining text
    if (lastIndex < message.length) {
      parts.push({
        type: 'text',
        content: message.slice(lastIndex)
      });
    }

    return (
      <span>
        {parts.map((part, index) => {
          if (part.type === 'link') {
            return (
              <button
                key={index}
                onClick={() => part.url && handlePDFLinkClick(part.url)}
                className="text-blue-600 hover:text-blue-800 underline cursor-pointer"
              >
                {part.text}
              </button>
            );
          } else {
            return <span key={index}>{part.content}</span>;
          }
        })}
      </span>
    );
  };

  // Handle PDF link clicks
  const handlePDFLinkClick = async (pdfUrl: string) => {
    // Extract contract ID from URL like "/contracts/{id}/pdf"
    const contractIdMatch = pdfUrl.match(/\/contracts\/([^\/]+)\/pdf/);
    if (!contractIdMatch) {
      toast.error('Ungültiger PDF-Link');
      return;
    }

    const contractId = contractIdMatch[1];
    
    // Find the notification with this contract
    const notification = notifications.find(n => n.contract?.id === contractId);
    if (!notification) {
      toast.error('Vertrag nicht gefunden');
      return;
    }

    // Use the existing PDF download function
    await handleDownloadPDF(notification);
  };

  const handleViewContract = async (notification: Notification) => {
    if (!notification.contract) {
      toast.error('Vertragsdaten nicht verfügbar');
      return;
    }

    // Mark as read when viewing
    if (!notification.is_read) {
      await handleMarkAsRead(notification);
    }

    setSelectedContract(notification.contract);
  };

  const handleDownloadPDF = async (notification: Notification) => {
    if (!notification.contract) {
      toast.error('Vertragsdaten nicht verfügbar');
      return;
    }

    try {
      toast.info('PDF-Download wird vorbereitet...', {
        description: `Vertrag für ${notification.contract.student?.name} wird als PDF generiert.`
      });

      // Fetch discount details if needed
      let appliedDiscounts = [];
      if (notification.contract.discount_ids && notification.contract.discount_ids.length > 0) {
        const { data: discountsData } = await supabase
          .from('contract_discounts')
          .select('*')
          .in('id', notification.contract.discount_ids);
        
        appliedDiscounts = discountsData || [];
      }

      // Prepare contract data for PDF
      let contractToExport: PDFContractData = {
        ...notification.contract,
        applied_discounts: appliedDiscounts
      };

      // Admin-only: fetch student and teacher bank_ids for PDF display
      // Get profile data directly since get_user_role() seems to have issues
      const { data: { user } } = await supabase.auth.getUser();
      const { data: profileData } = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user?.id)
        .single();
      
      const isAdmin = profileData?.role === 'admin';
      console.log('PDF Debug - Direct profile check (Notifications):', { profileData, isAdmin });
      
      // Always fetch bank_ids for admins, regardless of what's in the contract object
      if (isAdmin) {
        // Fetch student bank_id
        const studentId = notification.contract?.student?.id;
        if (studentId) {
          const { data: studentData } = await supabase
            .from('students')
            .select('bank_id')
            .eq('id', studentId)
            .single();
          
          if (studentData) {
            contractToExport = {
              ...contractToExport,
              student: {
                ...contractToExport.student,
                bank_id: studentData.bank_id,
              } as any,
            };
            console.log('PDF Debug - Updated student bank_id (Notifications):', studentData.bank_id);
          }
        }

        // Fetch teacher bank_id
        const teacherId = notification.contract?.student?.teacher?.id;
        if (teacherId) {
          const { data: teacherData } = await supabase
            .from('teachers')
            .select('bank_id')
            .eq('id', teacherId)
            .single();
          
          if (teacherData) {
            contractToExport = {
              ...contractToExport,
              student: {
                ...contractToExport.student,
                teacher: {
                  ...contractToExport.student?.teacher,
                  bank_id: teacherData.bank_id,
                } as any,
              } as any,
            };
            console.log('PDF Debug - Updated teacher bank_id (Notifications):', teacherData.bank_id);
          }
        }
      }

      // Generate and download PDF (admins see bank IDs)
      await generateContractPDF(contractToExport, { showBankIds: isAdmin });
      
      toast.success('PDF erfolgreich heruntergeladen', {
        description: `Vertrag für ${notification.contract.student?.name} wurde als PDF gespeichert.`
      });

      // Mark as read when downloading
      if (!notification.is_read) {
        await handleMarkAsRead(notification);
      }
      
    } catch (error) {
      console.error('Error downloading PDF:', error);
      toast.error('PDF konnte nicht generiert werden. Bitte erneut versuchen.');
    }
  };

  const handleCreateNewContract = (notification: Notification) => {
    if (!notification.contract?.student) {
      toast.error('Schülerdaten nicht verfügbar');
      return;
    }

    setSelectedStudentForNewContract(notification.contract.student.id);
    setShowNewContractForm(true);

    // Mark as read when creating new contract
    if (!notification.is_read) {
      handleMarkAsRead(notification);
    }
  };

  const getContractTypeDisplay = (contract: Contract) => {
    if (contract.contract_variant) {
      return contract.contract_variant.name;
    }
    
    // Fallback to legacy type system
    switch (contract.type) {
      case 'ten_class_card':
        return '10er Karte';
      case 'half_year':
        return 'Halbjahresvertrag';
      default:
        return contract.type;
    }
  };

  const formatDate = (dateString: string) => {
    if (!dateString) return 'Unbekannt';
    
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return 'Ungültiges Datum';
    
    return format(date, 'dd.MM.yyyy', { locale: de });
  };

  const getNotificationIcon = (type: string) => {
    switch (type) {
      case 'contract_fulfilled':
        return <CheckCircle className="h-5 w-5 text-green-600" />;
      case 'assigned_trial':
        return <UserCheck className="h-5 w-5 text-blue-600" />;
      case 'declined_trial':
        return <Clock className="h-5 w-5 text-orange-600" />;
      case 'accepted_trial':
        return <Check className="h-5 w-5 text-green-600" />;
      default:
        return <Bell className="h-5 w-5 text-gray-600" />;
    }
  };

  const getNotificationTitle = (type: string) => {
    switch (type) {
      case 'contract_fulfilled':
        return 'Vertrag abgeschlossen';
      case 'assigned_trial':
        return 'Probestunde zugewiesen';
      case 'declined_trial':
        return 'Probestunde verfügbar';
      case 'accepted_trial':
        return 'Probestunde angenommen';
      default:
        return 'Benachrichtigung';
    }
  };

  const filteredNotifications = notifications.filter(notification => {
    const matchesSearch = 
      notification.message.toLowerCase().includes(searchTerm.toLowerCase()) ||
      notification.contract?.student?.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      notification.trial_appointment?.student_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      notification.teacher?.name.toLowerCase().includes(searchTerm.toLowerCase());
    
    return matchesSearch;
  });

  // Separate read and unread notifications
  const unreadNotifications = filteredNotifications.filter(n => !n.is_read);
  const readNotifications = filteredNotifications.filter(n => n.is_read);

  if (!isAdmin && profile?.role !== 'teacher') {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <Bell className="h-12 w-12 text-gray-300 mx-auto mb-4" />
          <p className="text-gray-500">Sie haben keinen Zugriff auf das Postfach.</p>
        </div>
      </div>
    );
  }

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
          <h1 className="text-2xl font-bold text-gray-900">Postfach</h1>
          <p className="text-gray-600">
            {isAdmin 
              ? 'Benachrichtigungen über abgeschlossene Verträge und Probestunden verwalten'
              : 'Ihre Benachrichtigungen zu Probestunden und Verträgen'
            }
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant="outline" className="bg-red-50 text-red-700 border-red-200">
            {unreadNotifications.length} ungelesen
          </Badge>
          <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200">
            {readNotifications.length} gelesen
          </Badge>
        </div>
      </div>

      {/* Search */}
      <Card>
        <CardContent className="pt-6">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
            <Input
              placeholder="Suchen nach Benachrichtigungen, Schülern oder Lehrern..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10 focus:ring-brand-primary focus:border-brand-primary"
            />
          </div>
        </CardContent>
      </Card>

      {/* Unread Notifications */}
      {unreadNotifications.length > 0 && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Bell className="h-5 w-5 text-red-500" />
            <h2 className="text-xl font-semibold text-gray-900">Neue Benachrichtigungen</h2>
            <Badge variant="outline" className="bg-red-50 text-red-700 border-red-200">
              {unreadNotifications.length}
            </Badge>
          </div>

          <div className="grid gap-4">
            {unreadNotifications.map((notification) => (
              <Card 
                key={notification.id} 
                className={
                  notification.type === 'contract_fulfilled' ? 'border-red-200 bg-red-50' :
                  notification.type === 'assigned_trial' ? 'border-blue-200 bg-blue-50' :
                  notification.type === 'declined_trial' ? 'border-orange-200 bg-orange-50' :
                  notification.type === 'accepted_trial' ? 'border-green-200 bg-green-50' :
                  'border-gray-200 bg-gray-50'
                }
              >
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-2">
                      {getNotificationIcon(notification.type)}
                      <CardTitle className="text-lg">{getNotificationTitle(notification.type)}</CardTitle>
                      <Badge className="bg-red-600 text-white">Neu</Badge>
                    </div>
                    {/* Removed top-right icon actions; footer buttons remain */}
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="space-y-3">
                    <p className="text-sm text-gray-700">{renderNotificationMessage(notification.message)}</p>
                    
                    {notification.contract && (
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                        <div className="flex items-center gap-2">
                          <User className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-600">Schüler:</span>
                            <p>{notification.contract.student?.name}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <FileText className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-600">Typ:</span>
                            <p>{getContractTypeDisplay(notification.contract)}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <User className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-600">Lehrer:</span>
                            <p>{notification.contract.student?.teacher?.name}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Calendar className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-600">Abgeschlossen:</span>
                            <p>{formatDate(notification.created_at)}</p>
                          </div>
                        </div>
                      </div>
                    )}

                    {notification.trial_appointment && (
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                        <div className="flex items-center gap-2">
                          <User className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-600">Schüler:</span>
                            <p>{notification.trial_appointment.student_name}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <FileText className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-600">Instrument:</span>
                            <p>{notification.trial_appointment.instrument}</p>
                          </div>
                        </div>
                        {notification.trial_appointment.teacher && (
                          <div className="flex items-center gap-2">
                            <User className="h-4 w-4 text-gray-400" />
                            <div>
                              <span className="font-medium text-gray-600">Lehrer:</span>
                              <p>{notification.trial_appointment.teacher.name}</p>
                            </div>
                          </div>
                        )}
                                                  <div className="flex items-center gap-2">
                           <Calendar className="h-4 w-4 text-gray-400" />
                           <div>
                             <span className="font-medium text-gray-600">Erstellt:</span>
                             <p>{formatDate(notification.created_at)}</p>
                           </div>
                         </div>
                      </div>
                    )}

                    <Separator />

                    <div className="flex flex-wrap gap-2">
                      {notification.contract && (
                        <>
                          <Button
                            onClick={() => handleViewContract(notification)}
                            size="sm"
                            className="bg-brand-primary hover:bg-brand-primary/90"
                          >
                            <Eye className="h-4 w-4 mr-2" />
                            Vertrag anzeigen
                          </Button>
                          <Button
                            onClick={() => handleDownloadPDF(notification)}
                            variant="outline"
                            size="sm"
                          >
                            <Download className="h-4 w-4 mr-2" />
                            PDF herunterladen
                          </Button>
                          <Button
                            onClick={() => handleCreateNewContract(notification)}
                            variant="outline"
                            size="sm"
                          >
                            <Plus className="h-4 w-4 mr-2" />
                            Neuer Vertrag
                          </Button>
                        </>
                      )}

                      <Button
                        onClick={() => handleMarkAsRead(notification)}
                        variant="outline"
                        size="sm"
                      >
                        <Check className="h-4 w-4 mr-2" />
                        Als gelesen markieren
                      </Button>
                      <Button
                        onClick={() => handleDeleteNotification(notification)}
                        variant="outline"
                        size="sm"
                        className="text-red-600 border-red-200 hover:bg-red-50"
                      >
                        <Trash2 className="h-4 w-4 mr-2" />
                        Löschen
                      </Button>
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      {/* Read Notifications */}
      {readNotifications.length > 0 && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <BellOff className="h-5 w-5 text-gray-500" />
            <h2 className="text-xl font-semibold text-gray-900">Gelesene Benachrichtigungen</h2>
            <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200">
              {readNotifications.length}
            </Badge>
          </div>

          <div className="grid gap-4">
            {readNotifications.map((notification) => (
              <Card 
                key={notification.id} 
                className="border-gray-200 bg-gray-50"
              >
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-2">
                      {getNotificationIcon(notification.type)}
                      <CardTitle className="text-lg text-gray-700">{getNotificationTitle(notification.type)}</CardTitle>
                      <Badge variant="outline" className="bg-gray-100 text-gray-600">Gelesen</Badge>
                    </div>
                    {/* Removed top-right icon actions; footer buttons remain */}
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="space-y-3">
                    <p className="text-sm text-gray-600">{renderNotificationMessage(notification.message)}</p>
                    
                    {notification.contract && (
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                        <div className="flex items-center gap-2">
                          <User className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-500">Schüler:</span>
                            <p className="text-gray-600">{notification.contract.student?.name}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <FileText className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-500">Typ:</span>
                            <p className="text-gray-600">{getContractTypeDisplay(notification.contract)}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <User className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-500">Lehrer:</span>
                            <p className="text-gray-600">{notification.contract.student?.teacher?.name}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Calendar className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-500">Abgeschlossen:</span>
                            <p className="text-gray-600">{formatDate(notification.created_at)}</p>
                          </div>
                        </div>
                      </div>
                    )}

                    {notification.trial_appointment && (
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                        <div className="flex items-center gap-2">
                          <User className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-500">Schüler:</span>
                            <p className="text-gray-600">{notification.trial_appointment.student_name}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <FileText className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-500">Instrument:</span>
                            <p className="text-gray-600">{notification.trial_appointment.instrument}</p>
                          </div>
                        </div>
                        {notification.trial_appointment.teacher && (
                          <div className="flex items-center gap-2">
                            <User className="h-4 w-4 text-gray-400" />
                            <div>
                              <span className="font-medium text-gray-500">Lehrer:</span>
                              <p className="text-gray-600">{notification.trial_appointment.teacher.name}</p>
                            </div>
                          </div>
                        )}
                        <div className="flex items-center gap-2">
                          <Calendar className="h-4 w-4 text-gray-400" />
                          <div>
                            <span className="font-medium text-gray-500">Datum:</span>
                            <p className="text-gray-600">{formatDate(notification.created_at)}</p>
                          </div>
                        </div>
                      </div>
                    )}

                    <Separator />

                    <div className="flex flex-wrap gap-2">
                      {notification.contract && (
                        <>
                          <Button
                            onClick={() => handleViewContract(notification)}
                            size="sm"
                            variant="outline"
                            className="bg-white hover:bg-gray-50"
                          >
                            <Eye className="h-4 w-4 mr-2" />
                            Vertrag anzeigen
                          </Button>
                          <Button
                            onClick={() => handleDownloadPDF(notification)}
                            variant="outline"
                            size="sm"
                            className="bg-white hover:bg-gray-50"
                          >
                            <Download className="h-4 w-4 mr-2" />
                            PDF herunterladen
                          </Button>
                          <Button
                            onClick={() => handleCreateNewContract(notification)}
                            variant="outline"
                            size="sm"
                            className="bg-white hover:bg-gray-50"
                          >
                            <Plus className="h-4 w-4 mr-2" />
                            Neuer Vertrag
                          </Button>
                        </>
                      )}

                      <Button
                        onClick={() => handleDeleteNotification(notification)}
                        variant="outline"
                        size="sm"
                        className="bg-white hover:bg-gray-50 text-red-600 border-red-200 hover:bg-red-50"
                      >
                        <Trash2 className="h-4 w-4 mr-2" />
                        Löschen
                      </Button>
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      {/* Empty State */}
      {filteredNotifications.length === 0 && (
        <Card>
          <CardContent className="pt-6">
            <div className="text-center py-12">
              <Bell className="h-12 w-12 text-gray-300 mx-auto mb-4" />
              <p className="text-gray-500">
                {searchTerm 
                  ? 'Keine Benachrichtigungen gefunden, die Ihren Suchkriterien entsprechen.'
                  : 'Keine Benachrichtigungen vorhanden. Benachrichtigungen erscheinen hier, wenn Verträge abgeschlossen werden oder Probestunden zugewiesen werden.'
                }
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Lesson Tracker Modal */}
      {selectedContract && (
        <LessonTrackerModal
          contract={selectedContract}
          open={!!selectedContract}
          onClose={() => setSelectedContract(null)}
          onUpdate={() => {
            // Refresh notifications to get updated contract data
            fetchNotifications();
          }}
        />
      )}

      {/* New Contract Form Dialog */}
      <Dialog open={showNewContractForm} onOpenChange={setShowNewContractForm}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Neuen Vertrag erstellen</DialogTitle>
          </DialogHeader>
          <ContractForm
            students={students}
            initialStudentId={selectedStudentForNewContract}
            onSuccess={() => {
              setShowNewContractForm(false);
              setSelectedStudentForNewContract('');
              fetchNotifications(); // Refresh to see if notification should be updated
              toast.success('Neuer Vertrag erfolgreich erstellt');
            }}
            onCancel={() => {
              setShowNewContractForm(false);
              setSelectedStudentForNewContract('');
            }}
          />
        </DialogContent>
      </Dialog>
    </div>
  );
}