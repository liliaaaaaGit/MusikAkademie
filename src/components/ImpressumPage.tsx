import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';

const ImpressumPage = () => {
  return (
    <div className="min-h-screen bg-white w-full">
      <div className="w-full max-w-2xl px-4 py-12 mx-auto space-y-8">
        {/* Heading left-aligned */}
        <h1 className="text-3xl font-bold text-left">Impressum</h1>

        {/* Legal text block, left-aligned */}
        <div className="space-y-6 text-left">
          <div>
            <p className="font-semibold">Angaben gemäß § 5 TMG</p>
            <p>Daniela Papadopoulos-Marotta</p>
            <p>MusikAkademie München</p>
            <p>Finanzamt München</p>
            <p>Steuernummer: 145/194/80531</p>
          </div>

          <div>
            <p className="font-semibold">Kontakt:</p>
            <p>Sebeneseestr. 10a</p>
            <p>81377 München</p>
            <p>Telefon: +49 89 201 70 33</p>
            <p>Mail: info@musikakademie-muenchen.de</p>
          </div>

          <div>
            <p className="font-semibold">Verantwortlich für den Inhalt nach § 55 Abs. 2 RStV:</p>
            <p>Daniela Papadopoulos-Marotta</p>
          </div>
        </div>

        {/* Button left-aligned under the text block */}
        <div className="mt-10">
          <Link to="/">
            <Button className="bg-brand-primary hover:bg-brand-primary/90 text-white text-base font-medium px-8 py-3 rounded-lg">
              Zurück zur Startseite
            </Button>
          </Link>
        </div>
      </div>
    </div>
  );
};

export default ImpressumPage;