import { useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { Button } from '@/components/ui/button';

export function PrivacyPolicyPage() {
  const navigate = useNavigate();
  return (
    <div className="min-h-screen bg-gray-50 py-8 px-4 flex flex-col items-center justify-center">
      <div className="w-full max-w-3xl mx-auto relative">
        <Button
          variant="ghost"
          className="absolute left-0 top-0 flex items-center gap-2"
          onClick={() => navigate(-1)}
        >
          <ArrowLeft className="h-5 w-5 mr-1" />
          Zurück
        </Button>
        <div className="prose prose-gray mx-auto pt-12">
          <h1>Datenschutzerklärung</h1>
          <p><strong>Verantwortlich für die Datenverarbeitung:</strong><br />
          Daniela Papadopoulos-Marotta<br />
          Sebenseestr. 10a<br />
          81377 München<br />
          info@musikakademie-muenchen.de</p>

          <h2>1. Allgemeine Hinweise</h2>
          <p>Diese Webanwendung dient der internen Verwaltung einer Musikakademie. Der Zugang ist ausschließlich für manuell angelegte Benutzer:innen (Lehrkräfte und Administrator:innen) vorgesehen. Die WebApp wurde unter Berücksichtigung der Vorgaben der Datenschutz-Grundverordnung (DSGVO) entwickelt.</p>

          <h2>2. Verantwortlicher und Hosting</h2>
          <p>Diese WebApp wird über die Plattform Supabase gehostet (Supabase Inc., USA). Ein Auftragsverarbeitungsvertrag (AVV) gemäß Art. 28 DSGVO mit Standardvertragsklauseln wurde abgeschlossen. Die Daten werden ausschließlich auf EU-Servern verarbeitet. Supabase bietet mit Role-Level Security (RLS), Logging und Authentifizierung umfassende Datenschutzfunktionen, die in dieser App verwendet werden.</p>

          <h2>3. Zwecke der Datenverarbeitung</h2>
          <p>Die Verarbeitung personenbezogener Daten erfolgt zu folgenden Zwecken:</p>
          <ul>
            <li>Verwaltung von Schüler:innen, Lehrkräften und Unterrichtsverträgen</li>
            <li>Anzeige von Benachrichtigungen (z. B. bei Vertragsabschlüssen)</li>
            <li>Download von Vertragsdokumenten als PDF</li>
            <li>Zugriffsbeschränkung durch Rollenverwaltung (Admin, Lehrkraft)</li>
          </ul>

          <h2>4. Rechtsgrundlage</h2>
          <p>Rechtsgrundlage für die Datenverarbeitung ist Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung) sowie Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an effizienter Verwaltung und Kommunikation).</p>

          <h2>5. Art der verarbeiteten Daten</h2>
          <p><strong>a) Benutzerkonten (Lehrkräfte/Admins)</strong></p>
          <ul>
            <li>Name</li>
            <li>E-Mail-Adresse</li>
            <li>Telefonnummer</li>
            <li>Rolle (admin/teacher)</li>
            <li>Interne Bank-Zuordnungs-ID (keine Kontodaten)</li>
            <li>Zugehörige Profile</li>
            <li>Login-Metadaten</li>
          </ul>
          <p><strong>b) Schüler:innen</strong></p>
          <ul>
            <li>Name</li>
            <li>E-Mail-Adresse</li>
            <li>Telefonnummer</li>
            <li>Instrument</li>
            <li>Zugehörige Lehrkraft</li>
            <li>Vertragsdaten (z. B. Anzahl Unterrichtseinheiten, Fortschritt, Preis, Interne Bank-Zuordnungs-ID (keine Kontodaten))</li>
            <li>Optional: Kommentarfelder, sofern aktiv genutzt</li>
          </ul>
          <p><strong>c) Vertragsdaten</strong></p>
          <ul>
            <li>Vertragsart (z. B. Schnupperkurs, Halbjahresvertrag, 10er-Karte, etc.)</li>
            <li>Laufzeit, Preis, Unterrichtseinheiten</li>
            <li>Fortschritt</li>
            <li>PDF-Export zur Dokumentation</li>
          </ul>
          <p><strong>d) Benachrichtigungen</strong></p>
          <ul>
            <li>Statusmeldung zum Vertrag (z. B. „abgeschlossen“)</li>
            <li>Referenz auf beteiligte Personen (Lehrkraft, Schüler:in)</li>
          </ul>

          <h2>6. Speicherdauer</h2>
          <p>Die Daten werden nur so lange gespeichert, wie es für die genannten Zwecke erforderlich ist. Verträge und Schülerdaten werden nach Ende des Unterrichtsverhältnisses nach spätestens 12 Monaten gelöscht oder anonymisiert, sofern keine gesetzlichen Aufbewahrungspflichten entgegenstehen.</p>

          <h2>7. Datensparsamkeit (Art. 5 Abs. 1 lit. c DSGVO)</h2>
          <p>Die Anwendung speichert nur solche Daten, die für den Schulbetrieb notwendig sind. Es erfolgt keine Speicherung sensibler Daten (z. B. Geburtsdaten, Adressen, Zahlungsdaten).</p>

          <h2>8. Weitergabe an Dritte</h2>
          <p>Es erfolgt keine Weitergabe personenbezogener Daten an Dritte außerhalb des AV-Verhältnisses mit Supabase.</p>

          <h2>9. Betroffenenrechte</h2>
          <p>Nutzer:innen haben das Recht auf Auskunft, Berichtigung, Löschung und Einschränkung der Verarbeitung ihrer Daten sowie das Recht auf Datenübertragbarkeit gemäß den gesetzlichen Vorgaben. Anfragen können an die oben genannte Kontaktadresse gerichtet werden.</p>
        </div>
      </div>
    </div>
  );
} 