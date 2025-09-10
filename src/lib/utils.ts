import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { format } from 'date-fns';
import { de } from 'date-fns/locale';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const fmtDate = (d?: string | Date | null) =>
  d ? format(new Date(d), 'dd.MM.yyyy', { locale: de }) : '';

export const fmtMonthYear = (d?: string | Date | null) =>
  d ? format(new Date(d), 'MMMM yyyy', { locale: de }) : '';

export const fmtRange = (start?: string | Date | null, end?: string | Date | null) =>
  start && end ? `${fmtMonthYear(start)} – ${fmtMonthYear(end)}`
  : start ? fmtMonthYear(start)
  : end ? fmtMonthYear(end)
  : '';

export const formatMonthYearShort = (d?: string | Date | null) => {
  if (!d) return '';
  const date = new Date(d);
  return new Intl.DateTimeFormat('de-DE', { month: 'short', year: 'numeric' }).format(date);
};
