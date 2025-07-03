import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export function DatenschutzPage() {
  return (
    <div className="min-h-screen bg-gray-50 py-8 px-4">
      <div className="max-w-4xl mx-auto">
        <Card className="shadow-lg">
          <CardHeader className="text-center pb-6">
            <CardTitle className="text-3xl font-bold text-gray-900">
              Datenschutzerklärung
            </CardTitle>
            <p className="text-gray-600 mt-2">
              Musikakademie München - Verwaltungssystem
            </p>
          </CardHeader>
          <CardContent className="space-y-8">
            <div className="prose prose-gray max-w-none">
              <div className="space-y-6">
                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    1. Verantwortliche Stelle
                  </h2>
                  <div className="text-gray-700 leading-relaxed">
                    <p className="font-medium">Musikakademie München</p>
                    <p>[Adresse]</p>
                    <p>[Kontakt-E-Mail]</p>
                  </div>
                </section>

                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    2. Zweck der Datenverarbeitung
                  </h2>
                  <p className="text-gray-700 leading-relaxed">
                    Verwaltung von Verträgen, Schüler:innen und Lehrkräften.
                  </p>
                </section>

                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    3. Verarbeitete Daten
                  </h2>
                  <p className="text-gray-700 leading-relaxed">
                    Name, E-Mail, Unterrichtsdaten, Vertragsinformationen, Logins.
                  </p>
                </section>

                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    4. Supabase
                  </h2>
                  <p className="text-gray-700 leading-relaxed">
                    Datenverarbeitung durch Supabase mit AV-Vertrag und EU-Hosting.
                  </p>
                </section>

                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    5. Zugriff
                  </h2>
                  <p className="text-gray-700 leading-relaxed">
                    Nur durch autorisierte Admins und Lehrer:innen mit Login.
                  </p>
                </section>

                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    6. Speicherdauer
                  </h2>
                  <p className="text-gray-700 leading-relaxed">
                    Nur solange erforderlich, automatische Löschroutinen geplant.
                  </p>
                </section>

                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    7. Betroffenenrechte
                  </h2>
                  <p className="text-gray-700 leading-relaxed">
                    Auskunft, Löschung, Berichtigung, Widerspruch etc. – Kontakt über [E-Mail]
                  </p>
                </section>

                <section>
                  <h2 className="text-xl font-semibold text-gray-900 mb-3">
                    8. Sicherheit
                  </h2>
                  <p className="text-gray-700 leading-relaxed">
                    SSL-Verschlüsselung, Zugriffsschutz, RLS auf Datenbankebene.
                  </p>
                </section>
              </div>
            </div>

            <div className="pt-6 border-t border-gray-200">
              <p className="text-sm text-gray-500 text-center">
                Stand: {new Date().toLocaleDateString('de-DE')}
              </p>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}