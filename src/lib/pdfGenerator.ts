import jsPDF from 'jspdf';
import { Contract, Lesson, ContractDiscount } from './supabase';
import { format } from 'date-fns';
import { de } from 'date-fns/locale';

export interface PDFContractData extends Contract {
  lessons?: Lesson[];
  applied_discounts?: ContractDiscount[];
}

export const generateContractPDF = async (contract: PDFContractData): Promise<void> => {
  try {
    // Create new PDF document
    const doc = new jsPDF();
    
    // Set up fonts and colors
    const primaryColor = '#ed3b71';
    const darkGray = '#374151';
    const lightGray = '#6b7280';
    const mediumGray = '#9ca3af';
    const successGreen = '#059669';
    const warningOrange = '#d97706';
    
    // Helper function to add text with word wrapping
    const addWrappedText = (text: string, x: number, y: number, maxWidth: number, fontSize: number = 10) => {
      doc.setFontSize(fontSize);
      const lines = doc.splitTextToSize(text, maxWidth);
      doc.text(lines, x, y);
      return y + (lines.length * fontSize * 0.4);
    };

    // Helper function to format price
    const formatPrice = (price: number | null | undefined) => {
      if (!price) return '-';
      return `${price.toFixed(2)}€`;
    };

    // Helper function to get group type display
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

    // Helper function to get contract duration
    const getContractDuration = (variant: any) => {
      if (!variant?.duration_months) {
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

    // Helper function to safely format dates
    const formatDate = (dateString: string) => {
      if (!dateString) return 'Unbekannt';
      
      const date = new Date(dateString);
      if (isNaN(date.getTime())) return 'Ungültiges Datum';
      
      return format(date, 'dd.MM.yyyy', { locale: de });
    };

    // Header
    doc.setFillColor(237, 59, 113); // Brand primary color
    doc.rect(0, 0, 210, 30, 'F');
    
    doc.setTextColor(255, 255, 255);
    doc.setFontSize(22);
    doc.setFont('helvetica', 'bold');
    doc.text('Musikakademie München', 20, 18);
    
    doc.setFontSize(14);
    doc.setFont('helvetica', 'normal');
    doc.text('Vertragsübersicht & Stundenzettel', 20, 26);

    // Reset text color
    doc.setTextColor(darkGray);
    
    let yPosition = 45;

    // Contract Information Section
    doc.setFontSize(18);
    doc.setFont('helvetica', 'bold');
    doc.text('Vertragsdetails', 20, yPosition);
    yPosition += 12;

    // Contract details in two columns
    doc.setFontSize(11);
    doc.setFont('helvetica', 'normal');
    
    const leftColumn = 20;
    const rightColumn = 110;
    
    // Left column - Basic Information
    doc.setFont('helvetica', 'bold');
    doc.text('Schüler:', leftColumn, yPosition);
    doc.setFont('helvetica', 'normal');
    doc.text(contract.student?.name || 'Unbekannt', leftColumn + 25, yPosition);
    
    doc.setFont('helvetica', 'bold');
    doc.text('Instrument:', leftColumn, yPosition + 8);
    doc.setFont('helvetica', 'normal');
    doc.text(contract.student?.instrument || 'Unbekannt', leftColumn + 25, yPosition + 8);
    
    doc.setFont('helvetica', 'bold');
    doc.text('Lehrer:', leftColumn, yPosition + 16);
    doc.setFont('helvetica', 'normal');
    doc.text(contract.student?.teacher?.name || 'Unbekannt', leftColumn + 25, yPosition + 16);

    doc.setFont('helvetica', 'bold');
    doc.text('Bank-ID Lehrer:', leftColumn, yPosition + 24);
    doc.setFont('helvetica', 'normal');
    doc.text(contract.student?.teacher?.bank_id || 'Unbekannt', leftColumn + 35, yPosition + 24);

    // Right column - Contract Information
    doc.setFont('helvetica', 'bold');
    doc.text('Kategorie:', rightColumn, yPosition);
    doc.setFont('helvetica', 'normal');
    const categoryName = contract.contract_variant?.contract_category?.display_name || 'Unbekannt';
    doc.text(categoryName, rightColumn + 25, yPosition);
    
    doc.setFont('helvetica', 'bold');
    doc.text('Variante:', rightColumn, yPosition + 8);
    doc.setFont('helvetica', 'normal');
    const variantName = contract.contract_variant?.name || 'Unbekannt';
    doc.text(variantName, rightColumn + 25, yPosition + 8);
    
    doc.setFont('helvetica', 'bold');
    doc.text('Status:', rightColumn, yPosition + 16);
    doc.setFont('helvetica', 'normal');
    const status = contract.status === 'active' ? 'Aktiv' : 'Abgeschlossen';
    doc.text(status, rightColumn + 25, yPosition + 16);
    
    doc.setFont('helvetica', 'bold');
    doc.text('Erstellt am:', rightColumn, yPosition + 24);
    doc.setFont('helvetica', 'normal');
    const createdDate = formatDate(contract.created_at);
    doc.text(createdDate, rightColumn + 25, yPosition + 24);

    yPosition += 40;

    // Contract Specifications Section
    doc.setFontSize(16);
    doc.setFont('helvetica', 'bold');
    doc.text('Vertragskonditionen', 20, yPosition);
    yPosition += 10;

    doc.setFontSize(11);
    doc.setFont('helvetica', 'normal');

    // Contract specifications in grid layout
    const specs = [
      ['Unterrichtsform:', getGroupTypeDisplay(contract.contract_variant?.group_type || '')],
      ['Stundenlänge:', contract.contract_variant?.session_length_minutes ? `${contract.contract_variant.session_length_minutes} Minuten` : 'Variiert'],
      ['Gesamtstunden:', contract.contract_variant?.total_lessons ? `${contract.contract_variant.total_lessons} Stunden` : 'Unbekannt'],
      ['Laufzeit:', getContractDuration(contract.contract_variant)]
    ];

    specs.forEach((spec, index) => {
      const x = index % 2 === 0 ? leftColumn : rightColumn;
      const y = yPosition + Math.floor(index / 2) * 8;
      
      doc.setFont('helvetica', 'bold');
      doc.text(spec[0], x, y);
      doc.setFont('helvetica', 'normal');
      doc.text(spec[1], x + 35, y);
    });

    yPosition += 25;

    // Price Overview Section
    doc.setFontSize(16);
    doc.setFont('helvetica', 'bold');
    doc.text('Preisübersicht', 20, yPosition);
    yPosition += 10;

    // Price box background
    doc.setFillColor(249, 250, 251);
    doc.rect(20, yPosition - 5, 170, 35, 'F');
    doc.setDrawColor(229, 231, 235);
    doc.rect(20, yPosition - 5, 170, 35, 'S');

    doc.setFontSize(11);
    doc.setFont('helvetica', 'normal');

    // Base price
    doc.setFont('helvetica', 'bold');
    doc.text('Grundpreis:', leftColumn + 5, yPosition + 5);
    doc.setFont('helvetica', 'normal');
    
    let basePrice = '';
    if (contract.contract_variant?.monthly_price) {
      basePrice = `${formatPrice(contract.contract_variant.monthly_price)} / Monat`;
    } else if (contract.contract_variant?.one_time_price) {
      basePrice = `${formatPrice(contract.contract_variant.one_time_price)} einmalig`;
    } else {
      basePrice = 'Nicht verfügbar';
    }
    doc.text(basePrice, leftColumn + 35, yPosition + 5);

    // Final price
    doc.setFont('helvetica', 'bold');
    doc.text('Endpreis:', leftColumn + 5, yPosition + 15);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(237, 59, 113); // Brand color for final price
    
    let finalPrice = '';
    if (contract.final_price && contract.payment_type) {
      finalPrice = contract.payment_type === 'monthly' 
        ? `${formatPrice(contract.final_price)} / Monat`
        : `${formatPrice(contract.final_price)} einmalig`;
    } else {
      finalPrice = basePrice;
    }
    doc.text(finalPrice, leftColumn + 35, yPosition + 15);
    doc.setTextColor(darkGray); // Reset color

    // Payment type
    doc.setFont('helvetica', 'bold');
    doc.text('Zahlungsart:', rightColumn + 5, yPosition + 5);
    doc.setFont('helvetica', 'normal');
    const paymentType = contract.payment_type === 'monthly' ? 'Monatlich' : 'Einmalig';
    doc.text(paymentType, rightColumn + 35, yPosition + 5);

    yPosition += 40;

    // Discounts Section (if any applied)
    const allDiscounts: ContractDiscount[] = [];
    
    // Add standard discounts if available
    if (contract.applied_discounts && contract.applied_discounts.length > 0) {
      allDiscounts.push(...contract.applied_discounts);
    }
    
    // Add custom discount if available
    if (contract.custom_discount_percent && contract.custom_discount_percent > 0) {
      allDiscounts.push({
        id: 'custom-discount-pdf',
        name: 'Benutzerdefinierte Ermäßigung',
        discount_percent: contract.custom_discount_percent,
        conditions: 'manuell zugewiesen',
        is_active: true,
        created_at: ''
      });
    }
    
    if (allDiscounts.length > 0) {
      doc.setFontSize(16);
      doc.setFont('helvetica', 'bold');
      doc.text('Angewandte Ermäßigungen', 20, yPosition);
      yPosition += 10;

      // Discount box background
      doc.setFillColor(254, 249, 195); // Light yellow background
      doc.rect(20, yPosition - 5, 170, 8 + (allDiscounts.length * 8), 'F');
      doc.setDrawColor(251, 191, 36);
      doc.rect(20, yPosition - 5, 170, 8 + (allDiscounts.length * 8), 'S');

      doc.setFontSize(11);
      doc.setFont('helvetica', 'normal');

      allDiscounts.forEach((discount, index) => {
        const y = yPosition + (index * 8);
        
        doc.setFont('helvetica', 'bold');
        doc.text(`• ${discount.name}:`, leftColumn + 5, y);
        doc.setFont('helvetica', 'normal');
        doc.text(`-${discount.discount_percent}%`, leftColumn + 80, y);
        
        if (discount.conditions) {
          doc.setTextColor(lightGray);
          doc.text(`(${discount.conditions})`, leftColumn + 100, y);
          doc.setTextColor(darkGray);
        }
      });

      // Calculate total discount
      const totalDiscount = allDiscounts.reduce((sum, discount) => sum + discount.discount_percent, 0);
      
      yPosition += (allDiscounts.length * 8) + 8;
      doc.setFont('helvetica', 'bold');
      doc.setTextColor(successGreen);
      doc.text(`Gesamtermäßigung: -${totalDiscount.toFixed(1)}%`, leftColumn + 5, yPosition);
      doc.setTextColor(darkGray);
      
      yPosition += 15;
    }

    // Progress Section
    if (contract.lessons && contract.lessons.length > 0) {
      const availableLessons = contract.lessons.filter(lesson => lesson.is_available !== false);
      const completedLessons = availableLessons.filter(lesson => lesson.date).length;
      const totalAvailable = availableLessons.length;
      const progressPercentage = totalAvailable > 0 ? Math.round((completedLessons / totalAvailable) * 100) : 0;

      doc.setFontSize(16);
      doc.setFont('helvetica', 'bold');
      doc.text('Fortschrittsübersicht', 20, yPosition);
      yPosition += 10;

      // Progress bar background
      doc.setFillColor(243, 244, 246);
      doc.rect(20, yPosition, 170, 8, 'F');
      
      // Progress bar fill
      const progressWidth = (progressPercentage / 100) * 170;
      doc.setFillColor(237, 59, 113);
      doc.rect(20, yPosition, progressWidth, 8, 'F');
      
      // Progress text
      doc.setFontSize(10);
      doc.setFont('helvetica', 'bold');
      doc.setTextColor(255, 255, 255);
      doc.text(`${progressPercentage}%`, 25, yPosition + 5);
      doc.setTextColor(darkGray);

      yPosition += 15;

      doc.setFontSize(11);
      doc.setFont('helvetica', 'normal');
      doc.text(`Abgeschlossene Stunden: ${completedLessons} von ${totalAvailable}`, 20, yPosition);
      
      if (contract.lessons.length - totalAvailable > 0) {
        doc.text(`Nicht verfügbare Stunden: ${contract.lessons.length - totalAvailable}`, 20, yPosition + 8);
        yPosition += 8;
      }
      
      yPosition += 20;

      // Check if we need a new page for the lessons table
      if (yPosition > 200) {
        doc.addPage();
        yPosition = 20;
      }

      // Lessons Table
      doc.setFontSize(16);
      doc.setFont('helvetica', 'bold');
      doc.text('Stundenübersicht', 20, yPosition);
      yPosition += 10;

      // Table headers
      doc.setFillColor(245, 245, 245);
      doc.rect(20, yPosition - 5, 170, 10, 'F');
      
      doc.setFontSize(10);
      doc.setFont('helvetica', 'bold');
      doc.text('Nr.', 25, yPosition + 2);
      doc.text('Datum', 45, yPosition + 2);
      doc.text('Status', 75, yPosition + 2);
      doc.text('Kommentare', 120, yPosition + 2);
      
      yPosition += 12;

      // Table rows - Sort by lesson_number to maintain sequential order
      doc.setFont('helvetica', 'normal');
      
      const sortedLessons = [...contract.lessons].sort((a, b) => a.lesson_number - b.lesson_number);
      
      sortedLessons.forEach((lesson, index) => {
        // Check if we need a new page
        if (yPosition > 270) {
          doc.addPage();
          yPosition = 20;
          
          // Repeat table headers on new page
          doc.setFillColor(245, 245, 245);
          doc.rect(20, yPosition - 5, 170, 10, 'F');
          
          doc.setFontSize(10);
          doc.setFont('helvetica', 'bold');
          doc.text('Nr.', 25, yPosition + 2);
          doc.text('Datum', 45, yPosition + 2);
          doc.text('Status', 75, yPosition + 2);
          doc.text('Kommentare', 120, yPosition + 2);
          
          yPosition += 12;
          doc.setFont('helvetica', 'normal');
        }

        const isEven = index % 2 === 0;
        if (isEven) {
          doc.setFillColor(250, 250, 250);
          doc.rect(20, yPosition - 4, 170, 8, 'F');
        }

        // Lesson number
        doc.setFontSize(9);
        doc.text(lesson.lesson_number.toString(), 25, yPosition);
        
        // Date
        const dateText = lesson.date ? formatDate(lesson.date) : '-';
        doc.text(dateText, 45, yPosition);
        
        // Status with color coding
        let statusText = 'Ausstehend';
        let statusColor = mediumGray;
        
        if (!lesson.is_available) {
          statusText = 'Nicht verfügbar';
          statusColor = warningOrange;
        } else if (lesson.date) {
          statusText = lesson.comment ? 'Abgeschlossen + Notizen' : 'Abgeschlossen';
          statusColor = successGreen;
        }
        
        doc.setTextColor(statusColor);
        doc.text(statusText, 75, yPosition);
        doc.setTextColor(darkGray); // Reset to default color
        
        // Comments (truncated if too long)
        if (lesson.comment) {
          const maxCommentWidth = 65;
          const commentLines = doc.splitTextToSize(lesson.comment, maxCommentWidth);
          const displayComment = commentLines.length > 1 ? commentLines[0] + '...' : commentLines[0];
          doc.text(displayComment, 120, yPosition);
        } else {
          doc.text('-', 120, yPosition);
        }
        
        yPosition += 8;
      });
    }

    // Add some spacing before footer
    yPosition += 10;

    // Notes section (if contract variant has notes)
    if (contract.contract_variant?.notes) {
      // Check if we need a new page
      if (yPosition > 250) {
        doc.addPage();
        yPosition = 20;
      }

      doc.setFontSize(14);
      doc.setFont('helvetica', 'bold');
      doc.text('Zusätzliche Informationen', 20, yPosition);
      yPosition += 8;

      doc.setFontSize(10);
      doc.setFont('helvetica', 'normal');
      doc.setTextColor(lightGray);
      yPosition = addWrappedText(contract.contract_variant.notes, 20, yPosition, 170, 10);
      doc.setTextColor(darkGray);
    }

    // Footer
    const pageCount = doc.getNumberOfPages();
    for (let i = 1; i <= pageCount; i++) {
      doc.setPage(i);
      doc.setFontSize(8);
      doc.setTextColor(lightGray);
      
      // Footer line
      doc.setDrawColor(229, 231, 235);
      doc.line(20, 285, 190, 285);
      
      doc.text(`Seite ${i} von ${pageCount}`, 20, 292);
      doc.text(`Generiert am ${format(new Date(), 'dd.MM.yyyy HH:mm', { locale: de })}`, 100, 292);
      doc.text('Musikakademie München', 160, 292);
    }

    // Generate filename with contract variant name
    const studentName = contract.student?.name?.replace(/[^a-zA-Z0-9]/g, '_') || 'Unbekannt';
    const filenameVariantName = contract.contract_variant?.name?.replace(/[^a-zA-Z0-9]/g, '_') || 'Vertrag';
    const dateString = format(new Date(), 'yyyy-MM-dd');
    const filename = `Vertrag_${studentName}_${filenameVariantName}_${dateString}.pdf`;

    // Save the PDF
    doc.save(filename);
    
  } catch (error) {
    console.error('Error generating PDF:', error);
    throw new Error('Fehler beim Generieren der PDF-Datei');
  }
};