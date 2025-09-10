import { useRef, useState } from 'react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { toast } from 'sonner';
import { supabase } from '@/lib/supabase';

export default function AuthForgotPage() {
  const [email, setEmail] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const lastRequestRef = useRef<number>(0);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const now = Date.now();
    if (now - lastRequestRef.current < 60_000) {
      toast.info('Bitte warten Sie einen Moment, bevor Sie es erneut versuchen.');
      return;
    }
    lastRequestRef.current = now;
    setSubmitting(true);
    try {
      await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/auth/reset`,
      });
      toast.success('Wenn ein Konto existiert, erhalten Sie in Kürze eine E-Mail mit weiteren Anweisungen.');
    } catch {
      toast.success('Wenn ein Konto existiert, erhalten Sie in Kürze eine E-Mail mit weiteren Anweisungen.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen w-screen grid place-items-center bg-white p-4">
      <Card className="w-full max-w-lg border-0 shadow-xl">
        <CardHeader>
          <CardTitle>Passwort zurücksetzen</CardTitle>
          <CardDescription>
            Geben Sie Ihre E-Mail-Adresse ein. Wenn ein Konto existiert, erhalten Sie einen Link zum Zurücksetzen.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">E‑Mail</Label>
              <Input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <Button type="submit" disabled={submitting} className="w-full bg-brand-primary hover:bg-brand-primary/90">
              Link senden
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
} 