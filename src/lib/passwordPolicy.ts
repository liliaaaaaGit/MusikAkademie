import { z } from 'zod';

export const bannedPasswords = new Set([
  'password', 'passwort', '123456', '123456789', 'qwerty', 'letmein', 'welcome', 'abc123', 'admin', 'iloveyou', '000000'
]);

export const passwordSchema = (email?: string) => z.string()
  .min(12, 'Mindestens 12 Zeichen')
  .refine((v) => !/\s/.test(v) === true, 'Keine Leerzeichen erlaubt')
  .refine((v) => /[a-z]/.test(v), 'Mindestens ein Kleinbuchstabe erforderlich')
  .refine((v) => /[A-Z]/.test(v), 'Mindestens ein Großbuchstabe erforderlich')
  .refine((v) => /\d/.test(v), 'Mindestens eine Ziffer erforderlich')
  .refine((v) => /[~!@#$%^&*()_+\-=[\]{};':"\\|,.<>\/?]/.test(v), 'Mindestens ein Sonderzeichen erforderlich')
  .refine((v) => !bannedPasswords.has(v.toLowerCase()), 'Zu schwaches Passwort')
  .refine((v) => !/(.)\1{3,}/.test(v), 'Zu vorhersehbar (Wiederholungen)')
  .refine((v) => {
    if (!email) return true;
    const local = email.split('@')[0]?.toLowerCase();
    return !local || !v.toLowerCase().includes(local);
  }, 'Passwort darf keine Teile der E-Mail enthalten');

export function validatePassword(password: string, email?: string): { ok: boolean; error?: string } {
  const res = passwordSchema(email).safeParse(password);
  return { ok: res.success, error: res.success ? undefined : 'Das Passwort erfüllt nicht die Sicherheitsanforderungen.' };
} 