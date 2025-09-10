import { useState } from 'react';
import { Navigate, Link } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Eye, EyeOff } from 'lucide-react';
import { toast } from 'sonner';

export function LoginForm() {
  const { user, profile, signIn, loading } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (user && profile) {
    return <Navigate to="/" replace />;
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);

    try {
      const { error } = await signIn(email, password);
      
      if (error) {
        toast.error('Anmeldung fehlgeschlagen', {
          description: error.message === 'Invalid login credentials' 
            ? 'Ungültige E-Mail oder Passwort. Bitte überprüfen Sie Ihre Anmeldedaten.'
            : error.message
        });
      }
    } catch (error) {
      toast.error('Anmeldung fehlgeschlagen', {
        description: 'Ein unerwarteter Fehler ist aufgetreten. Bitte versuchen Sie es erneut.'
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  if (loading) {
    return (
      <div className="h-screen w-screen flex items-center justify-center bg-white">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-primary"></div>
      </div>
    );
  }

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
            Mitarbeiter-Dashboard - Sicherer Zugang
          </p>
        </div>

        <Card className="shadow-xl border-0">
          <CardHeader className="space-y-2 pb-6">
            <CardTitle className="text-2xl text-center">Bei Ihrem Konto anmelden</CardTitle>
            <CardDescription className="text-center text-base">
              Der Zugang ist nur für vorab registrierte Mitarbeiter möglich.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <form onSubmit={handleSubmit} className="space-y-6">
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
                <div className="relative">
                  <Input
                    id="password"
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Geben Sie Ihr Passwort ein"
                    className="h-12 text-base pr-12 focus:ring-brand-primary focus:border-brand-primary"
                  />
                  <button
                    type="button"
                    className="absolute inset-y-0 right-0 pr-3 flex items-center"
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    {showPassword ? (
                      <EyeOff className="h-5 w-5 text-gray-400" />
                    ) : (
                      <Eye className="h-5 w-5 text-gray-400" />
                    )}
                  </button>
                </div>
              </div>

              <Button
                type="submit"
                disabled={isSubmitting}
                className="w-full h-12 bg-brand-primary hover:bg-brand-primary/90 text-white text-base font-medium focus:ring-brand-primary"
              >
                {isSubmitting ? (
                  <div className="flex items-center space-x-2">
                    <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
                    <span>Anmeldung läuft...</span>
                  </div>
                ) : (
                  'Anmelden'
                )}
              </Button>
              <div className="flex justify-center mt-2">
                <Link to="/auth/forgot" className="text-sm text-muted-foreground hover:underline">
                  Passwort vergessen?
                </Link>
              </div>
            </form>

            <div className="mt-6 flex flex-col items-center">
              <div className="flex justify-center items-center space-x-4 text-sm text-muted-foreground">
                <Link to="/datenschutz" className="hover:underline">
                  Datenschutzerklärung
                </Link>
                <span>|</span>
                <Link to="/impressum" className="hover:underline">
                  Impressum
                </Link>
              </div>
              <Link to="/register" className="mt-2 text-sm text-muted-foreground hover:underline">
                Noch kein Konto? Hier registrieren.
              </Link>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}