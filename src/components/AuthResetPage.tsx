import { useEffect, useState } from 'react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { toast } from 'sonner';
import { supabase } from '@/lib/supabase';
import { passwordSchema } from '@/lib/passwordPolicy';
import { Eye, EyeOff } from 'lucide-react';

export default function AuthResetPage() {
  const [ready, setReady] = useState(false);
  const [email, setEmail] = useState<string | undefined>(undefined);
  const [pw1, setPw1] = useState('');
  const [pw2, setPw2] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [show1, setShow1] = useState(false);
  const [show2, setShow2] = useState(false);

  useEffect(() => {
    // Exchange recovery code for session (Supabase appends it in the URL)
    const run = async () => {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (!session) {
          const { data: exData, error: exError } = await supabase.auth.exchangeCodeForSession(window.location.href);
          if (exError) throw exError;
          setEmail(exData.user?.email || undefined);
        } else {
          setEmail(session.user?.email || undefined);
        }
      } catch (e) {
        toast.error('Link ungültig oder abgelaufen. Bitte fordern Sie einen neuen Link an.');
      } finally {
        setReady(true);
      }
    };
    run();
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (pw1 !== pw2) {
      toast.error('Die Passwörter stimmen nicht überein.');
      return;
    }
    const res = passwordSchema(email).safeParse(pw1);
    if (!res.success) {
      toast.error('Das Passwort erfüllt nicht die Sicherheitsanforderungen.');
      return;
    }
    setSubmitting(true);
    try {
      const { error } = await supabase.auth.updateUser({ password: pw1 });
      if (error) throw error;
      toast.success('Ihr Passwort wurde aktualisiert.');
      window.location.href = '/';
    } catch {
      toast.error('Das Passwort erfüllt nicht die Sicherheitsanforderungen oder der Link ist abgelaufen.');
    } finally {
      setSubmitting(false);
    }
  };

  if (!ready) return null;

  return (
    <div className="min-h-screen w-screen grid place-items-center bg-white p-4">
      <Card className="w-full max-w-lg border-0 shadow-xl">
        <CardHeader>
          <CardTitle>Neues Passwort festlegen</CardTitle>
          <CardDescription>
            Bitte wählen Sie ein sicheres Passwort. Sie bleiben nach dem Zurücksetzen angemeldet.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="pw1">Neues Passwort</Label>
              <div className="relative">
                <Input id="pw1" type={show1 ? 'text' : 'password'} required value={pw1} onChange={(e) => setPw1(e.target.value)} className="pr-10" />
                <button type="button" className="absolute inset-y-0 right-0 pr-3 flex items-center" onClick={() => setShow1(!show1)}>
                  {show1 ? <EyeOff className="h-5 w-5 text-gray-400" /> : <Eye className="h-5 w-5 text-gray-400" />}
                </button>
              </div>
              <p className="text-xs text-gray-500">Mindestens 10 Zeichen, Groß-/Kleinbuchstaben, Zahl und Sonderzeichen. Keine Leerzeichen.</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="pw2">Passwort bestätigen</Label>
              <div className="relative">
                <Input id="pw2" type={show2 ? 'text' : 'password'} required value={pw2} onChange={(e) => setPw2(e.target.value)} className="pr-10" />
                <button type="button" className="absolute inset-y-0 right-0 pr-3 flex items-center" onClick={() => setShow2(!show2)}>
                  {show2 ? <EyeOff className="h-5 w-5 text-gray-400" /> : <Eye className="h-5 w-5 text-gray-400" />}
                </button>
              </div>
            </div>
            <Button type="submit" disabled={submitting} className="w-full bg-brand-primary hover:bg-brand-primary/90">
              Passwort speichern
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
} 