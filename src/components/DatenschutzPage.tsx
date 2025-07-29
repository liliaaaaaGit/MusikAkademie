import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';

const DatenschutzPage = () => {
  return (
    <div className="w-full px-6 py-10">
      <h1 className="text-center text-3xl font-bold mb-10">Datenschutzerklärung</h1>
      <div className="w-full text-left space-y-6">

        <p><strong>Verantwortlich für die Datenverarbeitung:</strong><br />
        Daniela Papadopoulos-Marotta<br />
        Sebenseestr. 10a<br />
        81377 München<br />
        info@musikakademie-muenchen.de</p>

        <h2 className="text-xl font-semibold">1. Allgemeine Hinweise</h2>
        <p>Diese Webanwendung dient der internen Verwaltung einer Musikakademie. Der Zugang ist ausschließlich für manuell angelegte Benutzer:innen (Lehrkräfte und Administrator:innen) vorgesehen. Die WebApp wurde unter Berücksichtigung der Vorgaben der Datenschutz-Grundverordnung (DSGVO) entwickelt.</p>

        <h2 className="text-xl font-semibold">2. Verantwortlicher und Hosting</h2>
        <p>Diese WebApp wird über die Plattform Supabase gehostet (Supabase Inc., USA).<br />
        Ein Auftragsverarbeitungsvertrag (AVV) gemäß Art. 28 DSGVO mit Standardvertragsklauseln wurde abgeschlossen. Die Daten werden ausschließlich auf EU-Servern verarbeitet. Supabase bietet mit Role-Level Security (RLS), Logging und Authentifizierung umfassende Datenschutzfunktionen, die in dieser App verwendet werden.</p>

        <h2 className="text-xl font-semibold">3. Zwecke der Datenverarbeitung</h2>
        <p>Die Verarbeitung personenbezogener Daten erfolgt zu folgenden Zwecken:</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Verwaltung von Schüler:innen, Lehrkräften und Unterrichtsverträgen</li>
          <li>Anzeige von Benachrichtigungen (z. B. bei Vertragsabschlüssen)</li>
          <li>Download von Vertragsdokumenten als PDF</li>
          <li>Zugriffsbeschränkung durch Rollenverwaltung (Admin, Lehrkraft)</li>
        </ul>

        <h2 className="text-xl font-semibold">4. Rechtsgrundlage</h2>
        <p>Rechtsgrundlage für die Datenverarbeitung ist Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung) sowie Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an effizienter Verwaltung und Kommunikation).</p>

        <h2 className="text-xl font-semibold">5. Art der verarbeiteten Daten</h2>
        <p><strong>a) Benutzerkonten (Lehrkräfte/Admins)</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Name</li>
          <li>E-Mail-Adresse</li>
          <li>Telefonnummer</li>
          <li>Rolle (admin/teacher)</li>
          <li>Interne Bank-Zuordnungs-ID (keine Kontodaten)</li>
          <li>Zugehörige Profile</li>
          <li>Login-Metadaten</li>
        </ul>
        <p><strong>b) Schüler:innen</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Name</li>
          <li>E-Mail-Adresse</li>
          <li>Telefonnummer</li>
          <li>Instrument</li>
          <li>Zugehörige Lehrkraft</li>
          <li>Vertragsdaten (z. B. Anzahl Unterrichtseinheiten, Fortschritt, Preis, Interne Bank-Zuordnungs-ID (keine Kontodaten))</li>
          <li>Optional: Kommentarfelder, sofern aktiv genutzt</li>
        </ul>
        <p><strong>c) Vertragsdaten</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Vertragsart (z. B. Schnupperkurs, Halbjahresvertrag, 10er-Karte, etc.)</li>
          <li>Laufzeit, Preis, Unterrichtseinheiten</li>
          <li>Fortschritt</li>
          <li>PDF-Export zur Dokumentation</li>
        </ul>
        <p><strong>d) Benachrichtigungen</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Statusmeldung zum Vertrag (z. B. „abgeschlossen“)</li>
          <li>Referenz auf beteiligte Personen (Lehrkraft, Schüler:in)</li>
        </ul>

        <h2 className="text-xl font-semibold">6. Speicherdauer</h2>
        <p>Die Daten werden nur so lange gespeichert, wie es für die genannten Zwecke erforderlich ist. Verträge und Schülerdaten werden nach Ende des Unterrichtsverhältnisses nach spätestens 12 Monaten gelöscht oder anonymisiert, sofern keine gesetzlichen Aufbewahrungspflichten entgegenstehen.</p>

        <h2 className="text-xl font-semibold">7. Datensparsamkeit (Art. 5 Abs. 1 lit. c DSGVO)</h2>
        <p>Die Anwendung speichert nur solche Daten, die für den Schulbetrieb notwendig sind. Es erfolgt keine Speicherung sensibler Daten (z. B. Geburtsdaten, Adressen, Zahlungsdaten).</p>

        <h2 className="text-xl font-semibold">8. Weitergabe an Dritte</h2>
        <p>Es erfolgt keine Weitergabe personenbezogener Daten an Dritte außerhalb des AV-Verhältnisses mit Supabase.</p>

        <h2 className="text-xl font-semibold">9. Betroffenenrechte</h2>
        <p>Nutzer:innen haben jederzeit das Recht auf:</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Auskunft (Art. 15 DSGVO)</li>
          <li>Berichtigung (Art. 16 DSGVO)</li>
          <li>Löschung (Art. 17 DSGVO)</li>
          <li>Einschränkung der Verarbeitung (Art. 18 DSGVO)</li>
          <li>Widerspruch gegen die Verarbeitung (Art. 21 DSGVO)</li>
          <li>Datenübertragbarkeit (Art. 20 DSGVO)</li>
        </ul>
        <p>Anfragen hierzu können an die oben genannte Kontaktadresse gerichtet werden.</p>

        <h2 className="text-xl font-semibold">10. Sicherheit</h2>
        <p>Zugriffe sind durch passwortgeschützte Konten, RLS-Policies und rollenbasierten Zugriff (RBAC) abgesichert. Supabase bietet Verschlüsselung bei der Datenübertragung (TLS) und Speicherung. PDF-Downloads werden clientseitig erzeugt oder über temporäre URLs bereitgestellt.</p>
            </div>

      <div className="flex justify-center mt-10">
        <Link to="/">
          <Button className="bg-brand-primary hover:bg-brand-primary/90 text-white text-base font-medium px-8 py-3 rounded-lg">
            Zurück zur Startseite
          </Button>
        </Link>
      </div>
    </div>
  );
};

export default DatenschutzPage;
