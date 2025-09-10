import { supabase } from '@/lib/supabase';

export async function POST(request: Request) {
  try {
    const { email, origin } = await request.json();
    const redirectTo = (origin || window.location.origin) + '/auth/reset';
    await supabase.auth.resetPasswordForEmail(email, { redirectTo });
  } catch {}
  return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
} 