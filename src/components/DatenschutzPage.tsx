import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';

const DatenschutzPage = () => {
  return (
    <div className="w-full px-6 py-10">
      <h1 className="text-center text-3xl font-bold mb-10">Datenschutzerklärung für die interne WebApp der Musikakademie München (MAM)</h1>
      <div className="w-full text-left space-y-6">

        <p><strong>Verantwortlich für die Datenverarbeitung</strong><br />
        Daniela Papadopoulos-Marotta<br />
        Sebenseestr. 10a<br />
        81377 München<br />
        info@musikakademie-muenchen.de</p>

        <p><strong>Datenschutzbeauftragter</strong><br />
        Roland Weber (Datenschutznetz)<br />
        Andechser Weg 9<br />
        82041 Oberhaching<br />
        roland.weber@datenschutznetz.de<br />
        +49 179 2421881</p>

        <h2 className="text-xl font-semibold">1. Allgemeine Hinweise</h2>
        <p>Diese Webanwendung dient der internen Verwaltung der Musikakademie München. Der Zugang ist ausschließlich für manuell angelegte Benutzer:innen (Lehrkräfte und Administrator:innen) vorgesehen. Die WebApp wurde unter Berücksichtigung der Vorgaben der Datenschutz-Grundverordnung (DSGVO) entwickelt.</p>

        <h2 className="text-xl font-semibold">2. Verantwortlicher und Hosting</h2>
        <p>Die WebApp wird bei Vercel Inc. (USA) gehostet, die Datenbankdienste werden von Supabase Inc. (Irland/USA) bereitgestellt.</p>
        <p>Mit beiden Anbietern bestehen Auftragsverarbeitungsverträge gemäß Art. 28 DSGVO einschließlich Standardvertragsklauseln (SCCs) zur Absicherung von Datentransfers in Drittländer. Die Daten werden – soweit möglich – auf Servern innerhalb der EU verarbeitet.</p>
        <p><strong>Drittlandstransfer:</strong><br />
        Soweit eine Verarbeitung in den USA erfolgt, geschieht dies auf Grundlage:</p>
        <ul className="list-disc list-inside space-y-1">
          <li>des EU-US Data Privacy Frameworks (DPF), sofern die Anbieter dort zertifiziert sind,</li>
          <li>oder der Standardvertragsklauseln (SCC, 2021/914) einschließlich zusätzlicher technischer und organisatorischer Maßnahmen (Transfer Impact Assessment).</li>
        </ul>

        <h2 className="text-xl font-semibold">3. Zwecke der Datenverarbeitung</h2>
        <p>Die Verarbeitung personenbezogener Daten erfolgt zu folgenden Zwecken:</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Verwaltung von Schüler:innen, Lehrkräften, Probestunden, Unterrichtsfortschritten und Vertragsdaten</li>
          <li>Anzeige von Benachrichtigungen (z. B. bei Vertragsvollendung oder verfügbaren Probestunden)</li>
          <li>Erstellung und Download von Unterrichtsvereinbarungen als PDF</li>
          <li>Zugriffsbeschränkung durch Rollenverwaltung (Admin, Lehrkraft)</li>
        </ul>

        <h2 className="text-xl font-semibold">4. Rechtsgrundlage</h2>
        <p>Ihre personenbezogenen Daten werden aufgrund folgender Rechtsgrundlagen verarbeitet:</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung)</li>
          <li>Art. 6 Abs. 1 c DSGVO (Rechtliche Verpflichtung § 147 AO und § 257 HGB)</li>
          <li>Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an effizienter Verwaltung und Kommunikation)</li>
        </ul>
        <p>Bei minderjährigen Schüler:innen erfolgt die Verarbeitung auf Grundlage des Vertrags mit den Erziehungsberechtigten.</p>

        <h2 className="text-xl font-semibold">5. Art der verarbeiteten Daten</h2>
        <p><strong>a) Benutzerkonten (Lehrkräfte/Admins)</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Name, E-Mail-Adresse, Telefonnummer, Rolle (Admin/Teacher), interne Bank-Zuordnungs-ID (keine Kontodaten), Login-Metadaten</li>
        </ul>
        <p><strong>b) Schüler:innen</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Name, E-Mail-Adresse, Telefonnummer, Instrument, zugehörige Lehrkraft, Vertragsdaten / Unterrichtsvereinbarungen (z. B. Unterrichtseinheiten, Preis, Fortschritt, interne Bank-ID ohne Kontodaten), optionale Freitext-/Kommentarfelder</li>
        </ul>
        <p><strong>c) Vertragsdaten</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Vertragsart (z. B. Schnupperkurs, Halbjahresvertrag, 10er-Karte), Laufzeit, Preis, Ermäßigungen, Unterrichtseinheiten, Fortschritt, PDF-Export zur Dokumentation</li>
        </ul>
        <p><strong>d) Benachrichtigungen</strong></p>
        <ul className="list-disc list-inside space-y-1">
          <li>Statusmeldung zum Vertrag (z. B. „abgeschlossen"), Referenzen auf beteiligte Personen (Lehrkraft, Schüler:in)</li>
        </ul>

        <h2 className="text-xl font-semibold">6. Cookies / Protokolldaten</h2>
        <ul className="list-disc list-inside space-y-1">
          <li>Für die Anmeldung und den sicheren Betrieb werden technisch notwendige Session-Cookies eingesetzt (z. B. für Authentifizierung über Supabase). Diese sind für die Nutzung der WebApp erforderlich und bedürfen keiner Einwilligung.</li>
          <li>Es werden keine Cookies oder Tracking-Technologien zu Analyse- oder Marketingzwecken eingesetzt.</li>
          <li>Vercel speichert IP-Adressen und Zugriffsdaten in Logs für max. 90 Tage zur Sicherstellung von Betrieb und Sicherheit.</li>
        </ul>

        <h2 className="text-xl font-semibold">7. Speicherdauer</h2>
        <ul className="list-disc list-inside space-y-1">
          <li>Schüler- und Vertragsdaten: Löschung oder Anonymisierung spätestens 12 Monate nach Beendigung des Unterrichtsverhältnisses, sofern keine gesetzlichen Aufbewahrungspflichten bestehen.</li>
          <li>Logdaten (z. B. IP-Adressen bei Zugriffen): Speicherung durch Vercel für maximal 90 Tage.</li>
        </ul>

        <h2 className="text-xl font-semibold">8. Datensparsamkeit (Art. 5 Abs. 1 lit. c DSGVO)</h2>
        <p>Es werden ausschließlich die Daten erhoben und verarbeitet, die für den Betrieb der Akademie notwendig sind. Sensible Daten (z. B. Geburtsdaten, Adressen, Zahlungsdaten) werden nicht gespeichert.</p>

        <h2 className="text-xl font-semibold">9. Weitergabe an Dritte</h2>
        <p>Eine Weitergabe personenbezogener Daten erfolgt nur an die genannten Auftragsverarbeiter (Vercel, Supabase) und deren Subprozessoren. Eine aktuelle Liste der Sub-Prozessoren finden Sie in den veröffentlichten Datenschutzbestimmungen der jeweiligen Anbieter.</p>
        <p>Ein Datentransfer in die USA findet nur auf Grundlage der Standardvertragsklauseln (Art. 46 Abs. 2 lit. c DSGVO) statt.</p>

        <h2 className="text-xl font-semibold">10. Datensicherheit</h2>
        <ul className="list-disc list-inside space-y-1">
          <li>Zugriff nur über passwortgeschützte Konten mit rollenbasierter Zugriffskontrolle (RBAC, RLS in Supabase).</li>
          <li>Supabase setzt Verschlüsselung bei der Übertragung (TLS) und Speicherung (AES-256) ein.</li>
          <li>PDF-Downloads werden nur über temporäre, geschützte Links oder clientseitig erzeugt.</li>
          <li>Protokollierung von Administratorenzugriffen.</li>
          <li>Vercel speichert Logs ausschließlich zweckgebunden und zeitlich befristet.</li>
        </ul>

        <h2 className="text-xl font-semibold">11. Betroffenenrechte</h2>
        <p>Nutzer:innen haben jederzeit das Recht auf:</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Auskunft (Art. 15 DSGVO)</li>
          <li>Berichtigung (Art. 16 DSGVO)</li>
          <li>Löschung (Art. 17 DSGVO)</li>
          <li>Einschränkung der Verarbeitung (Art. 18 DSGVO)</li>
          <li>Widerspruch gegen die Verarbeitung (Art. 21 DSGVO)</li>
          <li>Datenübertragbarkeit (Art. 20 DSGVO)</li>
        </ul>
        <p>Anfragen können an die oben genannte Kontaktadresse gerichtet werden.</p>

        <h2 className="text-xl font-semibold">12. Beschwerderecht</h2>
        <p>Betroffene haben das Recht, sich bei einer Datenschutz-Aufsichtsbehörde über die Verarbeitung ihrer personenbezogenen Daten zu beschweren (Art. 77 DSGVO).</p>

        <p><strong>Stand:</strong> 13.09.2025 Version: 1.0</p>
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