import { useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Link } from 'react-router-dom';

export function RegisterForm() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const validate = () => {
    if (!email) return 'E-Mail ist erforderlich.';
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return 'Ungültiges E-Mail-Format.';
    if (!password) return 'Passwort ist erforderlich.';
    if (password.length < 8) return 'Passwort muss mindestens 8 Zeichen lang sein.';
    return null;
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setMessage(null);
    const validationError = validate();
    if (validationError) {
      setError(validationError);
      return;
    }
    setLoading(true);
    const trimmedEmail = email.trim();
    // 1. Check if teacher exists
    const { data: teachers, error: teacherError } = await supabase
      .from('teachers')
      .select('id, email, name')
      .ilike('email', trimmedEmail);
    console.log('Teacher query result:', teachers, teacherError, trimmedEmail);
    if (teacherError || !teachers || teachers.length === 0) {
      setError('Keine Lehrkraft mit dieser E-Mail gefunden.');
      setLoading(false);
      return;
    }
    // 2. Register user
    const { data: userData, error: signUpError } = await supabase.auth.signUp({
      email: trimmedEmail,
      password,
    });
    if (signUpError) {
      setError(signUpError.message);
      setLoading(false);
      return;
    }
    // Nach erfolgreichem signUp: Profil per RPC anlegen
    if (userData && userData.user) {
      const { data: rpcData, error: rpcError } = await supabase.rpc('create_profile_after_signup', {
        user_id: userData.user.id,
        user_email: userData.user.email,
      });
      if (rpcError) {
        console.error('RPC create_profile_after_signup failed:', rpcError);
      }
      if (rpcData) {
        console.log('RPC result:', rpcData);
        if (rpcData.success === false) {
          setError(rpcData.message || rpcData.error || 'Profil konnte nicht erstellt werden.');
          setLoading(false);
          return;
        }
      }
    }
    await supabase.auth.signOut();
    setMessage('Konto erstellt! Bitte überprüfen Sie Ihre E-Mail und melden Sie sich anschließend an.');
    setLoading(false);
  };

  return (
    <div className="h-screen w-screen flex items-center justify-center bg-white p-4">
      <div className="w-full max-w-lg space-y-8">
        <div className="text-center">
          <div className="flex justify-center mb-6">
            <img 
              src="/logo.png" 
              alt="MAM Logo" 
              className="h-20 w-auto"
            />
          </div>
          <h2 className="text-4xl font-bold text-gray-900">
            Musikakademie München
          </h2>
          <p className="mt-3 text-base text-gray-600">
            Mitarbeiter-Dashboard - Registrierung für Lehrkräfte
          </p>
        </div>
        <Card className="shadow-xl border-0">
          <CardHeader className="space-y-2 pb-6">
            <CardTitle className="text-2xl text-center">Lehrer Registrierung</CardTitle>
            <CardDescription className="text-center text-base">
              Bitte registrieren Sie sich mit der E-Mail, die von der Akademie hinterlegt wurde.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <form onSubmit={handleRegister} className="space-y-6">
              <div className="space-y-2">
                <Label htmlFor="email" className="text-sm font-medium">E-Mail-Adresse</Label>
                <Input
                  id="email"
                  type="email"
                  autoComplete="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="h-12 text-base focus:ring-brand-primary focus:border-brand-primary"
                  placeholder="Geben Sie Ihre E-Mail ein"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="password" className="text-sm font-medium">Passwort</Label>
                <Input
                  id="password"
                  type="password"
                  autoComplete="new-password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Wählen Sie ein sicheres Passwort"
                  className="h-12 text-base focus:ring-brand-primary focus:border-brand-primary"
                  minLength={8}
                />
              </div>
              {error && <div className="mb-2 text-red-600 text-center">{error}</div>}
              {message && <div className="mb-2 text-green-600 text-center">{message}</div>}
              <Button
                type="submit"
                disabled={loading}
                className="w-full h-12 bg-brand-primary hover:bg-brand-primary/90 text-white text-base font-medium focus:ring-brand-primary"
              >
                {loading ? (
                  <div className="flex items-center space-x-2">
                    <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
                    <span>Registrieren...</span>
                  </div>
                ) : (
                  'Registrieren'
                )}
              </Button>
            </form>
            <div className="pt-4 border-t border-gray-200">
              <div className="text-center space-y-2">
                <Link
                  to="/login"
                  className="text-sm text-gray-600 underline hover:text-brand-primary hover:no-underline transition-colors"
                >
                  Bereits ein Konto? Hier anmelden.
                </Link>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
} 