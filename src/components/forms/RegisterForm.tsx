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

  const validatePassword = (password: string) => {
    if (password.length < 12) return 'Passwort muss mindestens 12 Zeichen lang sein.';
    if (!/[A-Z]/.test(password)) return 'Passwort muss mindestens einen Großbuchstaben enthalten.';
    if (!/[a-z]/.test(password)) return 'Passwort muss mindestens einen Kleinbuchstaben enthalten.';
    if (!/[0-9]/.test(password)) return 'Passwort muss mindestens eine Zahl enthalten.';
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return 'Passwort muss mindestens ein Sonderzeichen enthalten.';
    return null;
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Validate password
    const validationError = validatePassword(password);
    if (validationError) {
      setError(validationError);
      return;
    }
    setLoading(true);
    const trimmedEmail = email.trim();
    
    try {
      console.log('Starting registration process for:', trimmedEmail);
      
      // 1. Check if teacher exists
      console.log('Checking if teacher exists...');
      const { data: teachers, error: teacherError } = await supabase
        .from('teachers')
        .select('id, email, name')
        .ilike('email', trimmedEmail);
      
      if (teacherError || !teachers || teachers.length === 0) {
        setError('Keine Lehrkraft mit dieser E-Mail gefunden. Bitte kontaktieren Sie die Verwaltung.');
        setLoading(false);
        return;
      }

      const teacher = teachers[0];
      console.log('Teacher found:', teacher);

      // 2. Check if user already exists
      console.log('Checking if user already exists...');
      const { data: existingUser, error: signInError } = await supabase.auth.signInWithPassword({
        email: trimmedEmail,
        password: 'temporary-password-for-check'
      });
      
      if (existingUser && !signInError) {
        // User exists and can sign in, so they're already registered
        await supabase.auth.signOut();
        setError('Ein Konto mit dieser E-Mail existiert bereits. Bitte melden Sie sich an.');
        setLoading(false);
        return;
      }

      // 3. Create new user
      console.log('Creating new user...');
      const { data: userData, error: signUpError } = await supabase.auth.signUp({
        email: trimmedEmail,
        password,
        options: {
          data: {
            full_name: teacher.name,
            role: 'teacher',
            teacher_id: teacher.id
          },
          emailRedirectTo: `${window.location.origin}/login`
        }
      });

      if (signUpError) {
        console.error('Signup error details:', {
          message: signUpError.message,
          status: signUpError.status,
          name: signUpError.name
        });
        
        if (signUpError.message.includes('Signups not allowed')) {
          setError('Registrierungen sind derzeit deaktiviert. Bitte kontaktieren Sie die Verwaltung.');
        } else if (signUpError.message.includes('already registered')) {
          setError('Ein Konto mit dieser E-Mail existiert bereits. Bitte melden Sie sich an.');
        } else {
          setError(`Registrierungsfehler: ${signUpError.message}`);
        }
        setLoading(false);
        return;
      }

      console.log('Signup successful:', userData);

      // 4. Sign out and show success message
      await supabase.auth.signOut();
      setMessage('Konto erfolgreich erstellt! Bitte überprüfen Sie Ihre E-Mail und bestätigen Sie Ihr Konto, bevor Sie sich anmelden.');
      
    } catch (error) {
      console.error('Registration error:', error);
      setError('Ein unerwarteter Fehler ist aufgetreten. Bitte versuchen Sie es erneut.');
    } finally {
      setLoading(false);
    }
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
                  placeholder="Wählen Sie ein sicheres Passwort (min. 12 Zeichen)"
                  className="h-12 text-base focus:ring-brand-primary focus:border-brand-primary"
                  minLength={12}
                />
                <p className="text-xs text-gray-500">
                  Mindestens 12 Zeichen, Groß-/Kleinbuchstaben, Zahl und Sonderzeichen
                </p>
              </div>
              {error && (
                <div className="mb-2 p-3 bg-red-50 border border-red-200 rounded-md">
                  <p className="text-red-600 text-sm">{error}</p>
                </div>
              )}
              {message && (
                <div className="mb-2 p-3 bg-green-50 border border-green-200 rounded-md">
                  <p className="text-green-600 text-sm">{message}</p>
                </div>
              )}
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