import { supabase } from '@/lib/supabase';

export async function POST(request: Request) {
  try {
    const { password } = await request.json();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response('Unauthorized', { status: 401 });
    const { error } = await supabase.auth.updateUser({ password });
    if (error) return new Response('Weak password', { status: 400 });
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response('Bad Request', { status: 400 });
  }
} 