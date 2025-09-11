import { supabase } from '@/lib/supabase';
import { sendEmail } from '@/lib/email/sendEmail';

export async function maybeNotifyPostfachMessage(messageId: string) {
  if (import.meta.env.VITE_EMAIL_NOTIFICATIONS_ENABLED !== 'true') return;

  // Load message; must reference a teacher
  const { data: msg, error: mErr } = await supabase
    .from('postbox_messages')
    .select('id, teacher_id, email_notified_at')
    .eq('id', messageId)
    .single();
  if (mErr || !msg) return;
  if (msg.email_notified_at) return;                 // idempotency
  if (!msg.teacher_id) return;                       // not for a teacher → no email

  // Resolve teacher email via teachers.profile_id -> profiles.email
  const { data: tRows, error: tErr } = await supabase
    .from('teachers')
    .select('id, profile_id, profiles:profile_id(email, is_active)')
    .eq('id', msg.teacher_id)
    .limit(1);
  if (tErr || !tRows?.length) return;                // no such teacher

  const prof = tRows[0]?.profiles as any;
  const email = prof?.email;
  const active = prof?.is_active ?? true;            // adapt if you track active flags
  if (!email || !active) return;                     // no valid recipient

  await sendEmail([email], 'New message in Postfach', 'You received a new message. Please log in to view it.');

  // Best-effort stamp; don't throw if blocked by policies
  await supabase
    .from('postbox_messages')
    .update({ email_notified_at: new Date().toISOString() })
    .eq('id', msg.id);
}
