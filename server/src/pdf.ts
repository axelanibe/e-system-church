import type { LogoPdf } from "./logo_pdf.js";

/**
 * Générateur PDF minimal, sans dépendance : le serveur n'a aucune librairie
 * PDF (package.json ne contient que fastify, pg, zod…), et une attestation
 * tient en une page de texte (Helvetica, WinAnsi). Le PDF est construit à
 * partir du contenu FIGÉ de l'attestation, jamais recalculé.
 * Caractères hors latin-1 (ex. ’) repliés sur l'apostrophe droite.
 */

export interface LignePdf {
  date: string; // AAAA-MM-JJ
  type: string; // Dîme, Offrande, Don
  montantFcfa: number;
}

export interface AttestationPdfData {
  egliseNom: string;
  egliseCode: string;
  /** Logo de l'église (chargé par la route), null : en-tête sans logo. */
  logo?: LogoPdf | null;
  numero: string;
  annee: number;
  dateEmission: string; // JJ/MM/AAAA
  donateurNom: string;
  donateurMatricule: string | null;
  dons: LignePdf[];
  totalFcfa: number;
}

export function formaterMontant(n: number): string {
  return `${String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ")} FCFA`;
}

function encoderLatin1(texte: string): Buffer {
  const corrige = texte
    .replace(/[’‘]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/…/g, "...")
    .replace(/–—/g, "-");
  const octets: number[] = [];
  for (const c of corrige) {
    const code = c.codePointAt(0) ?? 63;
    octets.push(code >= 32 && code <= 255 ? code : 63);
  }
  return Buffer.from(octets);
}

/** Chaîne littérale PDF : octets latin-1, parenthèses et \ échappés. */
function litteral(texte: string): string {
  const buf = encoderLatin1(texte);
  let out = "";
  for (const b of buf) {
    if (b === 0x28 || b === 0x29 || b === 0x5c) out += "\\" + String.fromCharCode(b);
    else out += String.fromCharCode(b);
  }
  return `(${out})`;
}

export interface AttestationEvenementPdfData {
  egliseNom: string;
  egliseCode: string;
  /** Logo de l'église (chargé par la route), null : en-tête sans logo. */
  logo?: LogoPdf | null;
  numero: string;
  /** Libellé du type, ex. « Attestation de mariage ». */
  libelleType: string;
  dateEmission: string; // JJ/MM/AAAA
  personneNom: string;
  personneMatricule: string | null;
  /** Date de l'événement, JJ/MM/AAAA. */
  dateEvenement: string;
  lieu: string | null;
  officiant: string | null;
  /** Détails propres au type, ex. conjoint, parents, parrain et marraine. */
  details: { label: string; valeur: string }[];
}

/** Objet image PDF (XObject) : JPEG brut ou RVB brut, selon le logo. */
function objetImage(logo: LogoPdf): Buffer {
  const filtre = logo.jpeg ? "/DCTDecode" : "/FlateDecode";
  const dict =
    `<< /Type /XObject /Subtype /Image /Width ${logo.largeur} ` +
    `/Height ${logo.hauteur} /ColorSpace /DeviceRGB /BitsPerComponent 8 ` +
    `/Filter ${filtre} /Length ${logo.donnees.length} >>\nstream\n`;
  return Buffer.concat([
    Buffer.from(dict, "latin1"),
    logo.donnees,
    Buffer.from("\nendstream", "latin1"),
  ]);
}

/**
 * Opérateur de dessin du logo, ajusté dans un carré de `taille` points
 * (proportions gardées), coin haut-gauche (x, yHaut).
 */
function operateurLogo(
  logo: LogoPdf,
  x: number,
  yHaut: number,
  taille: number,
): string {
  const echelle = Math.min(taille / logo.largeur, taille / logo.hauteur);
  const l = Math.max(1, Math.round(logo.largeur * echelle));
  const h = Math.max(1, Math.round(logo.hauteur * echelle));
  const dx = Math.round(x + (taille - l) / 2);
  const dy = Math.round(yHaut - h);
  return `q ${l} 0 0 ${h} ${dx} ${dy} cm /Im1 Do Q`;
}

/** Assemblage d'un PDF une page à partir de lignes de contenu. */
function assemblerPdf(lignes: string[], logo?: LogoPdf | null): Buffer {
  const contenu = lignes.join("\n");
  const image = logo ? objetImage(logo) : null;
  const imageNum = image ? 7 : null;
  const objets: (string | Buffer)[] = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >>${imageNum ? ` /XObject << /Im1 ${imageNum} 0 R >>` : ""} >> /Contents 6 0 R >>`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    `<< /Length ${Buffer.byteLength(contenu)} >>\nstream\n${contenu}\nendstream`,
    ...(image ? [image] : []),
  ];
  const parties: Buffer[] = [Buffer.from("%PDF-1.4\n", "latin1")];
  const offsets: number[] = [0];
  let pos = parties[0].length;
  objets.forEach((o, i) => {
    offsets.push(pos);
    const b =
      typeof o === "string"
        ? Buffer.from(`${i + 1} 0 obj\n${o}\nendobj\n`, "latin1")
        : Buffer.concat([
            Buffer.from(`${i + 1} 0 obj\n`, "latin1"),
            o,
            Buffer.from("\nendobj\n", "latin1"),
          ]);
    parties.push(b);
    pos += b.length;
  });
  const xrefPos = pos;
  let xref = `xref\n0 ${objets.length + 1}\n0000000000 65535 f \n`;
  for (let i = 1; i <= objets.length; i++) {
    xref += `${String(offsets[i]).padStart(10, "0")} 00000 n \n`;
  }
  xref += `trailer\n<< /Size ${objets.length + 1} /Root 1 0 R >>\nstartxref\n${xrefPos}\n%%EOF`;
  parties.push(Buffer.from(xref, "latin1"));
  return Buffer.concat(parties);
}

/** Lignes de texte PDF : même mécanisme pour les deux générateurs. */
function lignesTexte(): { lignes: string[]; texte: (x: number, y: number, taille: number, s: string, gras?: boolean) => void } {
  const lignes: string[] = [];
  const texte = (x: number, yy: number, taille: number, s: string, gras = false) => {
    lignes.push(
      `BT /${gras ? "F2" : "F1"} ${taille} Tf ${x} ${yy} Td ${litteral(s)} Tj ET`,
    );
  };
  return { lignes, texte };
}

/**
 * Générateur de rapport générique, multipage (tranche C, exports PDF).
 * Même technique que l'attestation (PDF minimal sans dépendance, Helvetica,
 * WinAnsi), mais avec pagination : une section est un tableau avec en-têtes,
 * lignes et totaux ; quand il n'y a plus de place en bas de page, une
 * nouvelle page est ouverte et l'en-tête du tableau est répété. Aucune
 * ligne n'est perdue : l'attestation ci-dessus coupe à une page, ici on
 * continue tant qu'il y a des lignes.
 */

export interface ColonneRapport {
  titre: string;
  /** Largeur en points ; la somme des colonnes doit tenir dans 495. */
  largeur: number;
  alignerDroite?: boolean;
}

export interface SectionRapport {
  titre: string;
  colonnes: ColonneRapport[];
  /** Cellules déjà formatées (montants en « 12 000 FCFA », dates JJ/MM/AAAA). */
  lignes: string[][];
  /** Ligne de totaux (même longueur que les colonnes), ou null. */
  total?: string[] | null;
  messageVide?: string;
}

export interface RapportPdfData {
  titre: string;
  egliseNom: string;
  /** Logo de l'église (chargé par la route), null : en-tête sans logo. */
  logo?: LogoPdf | null;
  /** Lignes de contexte sous le titre (période, date d'émission, solde…). */
  lignesMeta: string[];
  sections: SectionRapport[];
  /** Note finale, ex. « Agrégats seulement, aucun détail nominatif. » */
  pied?: string;
}

const PAGE_LARGEUR = 595;
const PAGE_HAUTEUR = 842;
const MARGE = 50;
const LARGEUR_UTILE = PAGE_LARGEUR - MARGE * 2;
const HAUT_PAGE = 792;
const BAS_PAGE = 60;
const HAUTEUR_LIGNE = 15;

/** Largeur estimée d'un texte Helvetica : ~0,52 × taille par caractère. */
function largeurEstimee(texte: string, taille: number): number {
  return texte.length * taille * 0.52;
}

/** Tronque un texte pour tenir dans une colonne, avec « ... » si coupé. */
function tronquer(texte: string, largeurPts: number, taille: number): string {
  const max = Math.floor((largeurPts - 4) / (taille * 0.52));
  if (max <= 0) return "";
  if (texte.length <= max) return texte;
  if (max <= 3) return texte.slice(0, max);
  return `${texte.slice(0, max - 3)}...`;
}

/** Assemble un PDF multipage à partir des flux de contenu de chaque page. */
function construirePdfMultiPages(pages: string[], logo?: LogoPdf | null): Buffer {
  const image = logo ? objetImage(logo) : null;
  // 1 catalogue, 2 pages, 3 et 4 polices, puis 2 objets par page.
  const imageNum = image ? 5 + pages.length * 2 : null;
  const objets: (string | Buffer)[] = [
    `<< /Type /Catalog /Pages 2 0 R >>`,
    `<< /Type /Pages /Kids [${pages.map((_, i) => `${5 + i * 2} 0 R`).join(" ")}] /Count ${pages.length} >>`,
    `<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>`,
    `<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>`,
  ];
  pages.forEach((contenu, i) => {
    objets.push(
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_LARGEUR} ${PAGE_HAUTEUR}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >>${imageNum ? ` /XObject << /Im1 ${imageNum} 0 R >>` : ""} >> /Contents ${6 + i * 2} 0 R >>`,
    );
    objets.push(
      `<< /Length ${Buffer.byteLength(contenu)} >>\nstream\n${contenu}\nendstream`,
    );
  });
  if (image) objets.push(image);
  const parties: Buffer[] = [Buffer.from("%PDF-1.4\n", "latin1")];
  const offsets: number[] = [0];
  let pos = parties[0].length;
  objets.forEach((o, i) => {
    offsets.push(pos);
    const b =
      typeof o === "string"
        ? Buffer.from(`${i + 1} 0 obj\n${o}\nendobj\n`, "latin1")
        : Buffer.concat([
            Buffer.from(`${i + 1} 0 obj\n`, "latin1"),
            o,
            Buffer.from("\nendobj\n", "latin1"),
          ]);
    parties.push(b);
    pos += b.length;
  });
  const xrefPos = pos;
  let xref = `xref\n0 ${objets.length + 1}\n0000000000 65535 f \n`;
  for (let i = 1; i <= objets.length; i++) {
    xref += `${String(offsets[i]).padStart(10, "0")} 00000 n \n`;
  }
  xref += `trailer\n<< /Size ${objets.length + 1} /Root 1 0 R >>\nstartxref\n${xrefPos}\n%%EOF`;
  parties.push(Buffer.from(xref, "latin1"));
  return Buffer.concat(parties);
}

export function genererRapportPdf(d: RapportPdfData): Buffer {
  const pages: string[][] = [[]];
  let y = HAUT_PAGE;

  const texte = (
    x: number,
    yy: number,
    taille: number,
    s: string,
    gras = false,
  ) => {
    pages[pages.length - 1].push(
      `BT /${gras ? "F2" : "F1"} ${taille} Tf ${x} ${yy} Td ${litteral(s)} Tj ET`,
    );
  };
  /** Trait horizontal fin (filet sous un en-tête, au-dessus d'un total). */
  const filet = (yy: number) => {
    pages[pages.length - 1].push(
      `0.5 w ${MARGE} ${yy} m ${MARGE + LARGEUR_UTILE} ${yy} l S`,
    );
  };
  /** Ouvre une nouvelle page ; `repetition` redessine l'en-tête du tableau en cours. */
  const nouvellePage = (repetition?: () => void) => {
    pages.push([]);
    y = HAUT_PAGE;
    repetition?.();
  };
  /** Place sous le titre : assez de place pour `besoin` points, sinon nouvelle page. */
  const assurerPlace = (besoin: number, repetition?: () => void) => {
    if (y - besoin < BAS_PAGE) nouvellePage(repetition);
  };

  texte(
    MARGE,
    y,
    16,
    tronquer(d.titre, LARGEUR_UTILE - (d.logo ? 60 : 0), 16),
    true,
  );
  y -= 20;
  texte(MARGE, y, 11, d.egliseNom);
  y -= 18;
  for (const meta of d.lignesMeta) {
    texte(MARGE, y, 10, tronquer(meta, LARGEUR_UTILE, 10));
    y -= 15;
  }
  y -= 10;
  if (d.logo) {
    // Logo de l'église en haut à droite de la première page seulement.
    pages[0].push(operateurLogo(d.logo, MARGE + LARGEUR_UTILE - 48, 800, 48));
  }

  for (const section of d.sections) {
    assurerPlace(60);
    texte(MARGE, y, 13, tronquer(section.titre, LARGEUR_UTILE, 13), true);
    y -= 20;

    // Positions x des colonnes (largeurs plafonnées à la largeur utile).
    const largeurs = section.colonnes.map((c) => c.largeur);
    const totalLargeurs = largeurs.reduce((s, l) => s + l, 0);
    const facteur =
      totalLargeurs > LARGEUR_UTILE ? LARGEUR_UTILE / totalLargeurs : 1;
    const xs: number[] = [];
    {
      let x = MARGE;
      for (const l of largeurs) {
        xs.push(x);
        x += l * facteur;
      }
    }
    const dessinerEntete = () => {
      for (let i = 0; i < section.colonnes.length; i++) {
        const c = section.colonnes[i];
        const t = tronquer(c.titre, largeurs[i] * facteur, 10);
        if (c.alignerDroite) {
          const xDroite = xs[i] + largeurs[i] * facteur - 2;
          texte(
            Math.round(xDroite - largeurEstimee(t, 10)),
            y,
            10,
            t,
            true,
          );
        } else {
          texte(xs[i], y, 10, t, true);
        }
      }
      y -= 4;
      filet(y);
      y -= 12;
    };
    const dessinerLigne = (cellules: string[], gras = false) => {
      for (let i = 0; i < section.colonnes.length; i++) {
        const c = section.colonnes[i];
        const t = tronquer(cellules[i] ?? "", largeurs[i] * facteur, 10);
        if (c.alignerDroite) {
          const xDroite = xs[i] + largeurs[i] * facteur - 2;
          texte(
            Math.round(xDroite - largeurEstimee(t, 10)),
            y,
            10,
            t,
            gras,
          );
        } else {
          texte(xs[i], y, 10, t, gras);
        }
      }
      y -= HAUTEUR_LIGNE;
    };

    if (section.lignes.length === 0) {
      dessinerEntete();
      texte(
        MARGE,
        y,
        10,
        section.messageVide ?? "Aucune donnée sur cette période.",
      );
      y -= HAUTEUR_LIGNE;
    } else {
      dessinerEntete();
      for (const ligne of section.lignes) {
        assurerPlace(HAUTEUR_LIGNE, dessinerEntete);
        dessinerLigne(ligne);
      }
      if (section.total) {
        assurerPlace(HAUTEUR_LIGNE + 6, dessinerEntete);
        filet(y + 11);
        dessinerLigne(section.total, true);
      }
    }
    y -= 14;
  }

  if (d.pied) {
    assurerPlace(30);
    texte(MARGE, y, 10, tronquer(d.pied, LARGEUR_UTILE, 10));
    y -= 15;
  }

  // Pied de page : numéro « Page i / n » sur chaque page, ajouté à la fin
  // car le nombre total de pages n'est connu qu'une fois le rapport fini.
  const totalPages = pages.length;
  pages.forEach((lignes, i) => {
    const label = `Page ${i + 1} / ${totalPages}`;
    lignes.push(
      `BT /F1 9 Tf ${Math.round(MARGE + LARGEUR_UTILE - largeurEstimee(label, 9))} 35 Td ${litteral(label)} Tj ET`,
    );
    lignes.push(
      `BT /F1 9 Tf ${MARGE} 35 Td ${litteral("E-System Church")} Tj ET`,
    );
  });

  return construirePdfMultiPages(
    pages.map((p) => p.join("\n")),
    d.logo ?? null,
  );
}

export function genererAttestationPdf(d: AttestationPdfData): Buffer {
  const { lignes, texte } = lignesTexte();
  let y = 780;
  // Nom de l'église en titre (il manquait : seule la ligne « Code »
  // figurait, régression PR #46), logo en haut à droite.
  texte(50, y, 16, d.egliseNom, true);
  if (d.logo) lignes.push(operateurLogo(d.logo, 501, 792, 44));
  y -= 32;
  texte(50, y, 11, `Code : ${d.egliseCode}`);
  y -= 32;
  texte(50, y, 15, `Attestation annuelle de dons — ${d.annee}`, true);
  y -= 22;
  texte(50, y, 11, `Numéro : ${d.numero}`);
  y -= 18;
  texte(50, y, 11, `Date d'émission : ${d.dateEmission}`);
  y -= 32;
  texte(50, y, 12, `Donateur : ${d.donateurNom}`, true);
  if (d.donateurMatricule) {
    y -= 18;
    texte(50, y, 11, `Matricule : ${d.donateurMatricule}`);
  }
  y -= 32;
  texte(50, y, 12, "Dons confirmés", true);
  y -= 20;
  for (const don of d.dons) {
    if (y < 140) break; // une page : les dons au-delà sont dans le total
    texte(50, y, 11, don.date);
    texte(150, y, 11, don.type);
    texte(420, y, 11, formaterMontant(don.montantFcfa));
    y -= 16;
  }
  y -= 8;
  texte(50, y, 12, `Total : ${formaterMontant(d.totalFcfa)}`, true);
  y -= 40;
  texte(50, y, 10, "En Côte d'Ivoire, cette attestation n'a aucune valeur fiscale.");
  y -= 15;
  texte(50, y, 10, "Elle sert de reçu justificatif de vos dons,");
  y -= 15;
  texte(50, y, 10, "pas de déclaration d'impôt.");
  return assemblerPdf(lignes, d.logo ?? null);
}

/**
 * Attestation d'événement (mariage, naissance, baptême) : même approche
 * sans dépendance, une page, Helvetica. Contenu figé en JSONB à
 * l'émission, jamais recalculé. Signature et cachet prévus en texte,
 * pas d'image : aucune image n'est inventée.
 */
export function genererAttestationEvenementPdf(d: AttestationEvenementPdfData): Buffer {
  const { lignes, texte } = lignesTexte();
  let y = 760;
  texte(50, y, 16, d.egliseNom, true);
  if (d.logo) lignes.push(operateurLogo(d.logo, 501, 792, 44));
  y -= 20;
  texte(50, y, 11, `Code : ${d.egliseCode}`);
  y -= 32;
  texte(50, y, 15, d.libelleType, true);
  y -= 22;
  texte(50, y, 11, `Numéro : ${d.numero}`);
  y -= 18;
  texte(50, y, 11, `Date d'émission : ${d.dateEmission}`);
  y -= 32;
  texte(50, y, 12, `Personne concernée : ${d.personneNom}`, true);
  if (d.personneMatricule) {
    y -= 18;
    texte(50, y, 11, `Matricule : ${d.personneMatricule}`);
  }
  y -= 32;
  texte(50, y, 12, "Événement", true);
  y -= 20;
  texte(50, y, 11, `Date : ${d.dateEvenement}`);
  if (d.lieu) {
    y -= 18;
    texte(50, y, 11, `Lieu : ${d.lieu}`);
  }
  if (d.officiant) {
    y -= 18;
    texte(50, y, 11, `Officiant : ${d.officiant}`);
  }
  for (const detail of d.details) {
    y -= 18;
    texte(50, y, 11, `${detail.label} : ${detail.valeur}`);
  }
  y -= 48;
  texte(50, y, 11, "Signature : ____________________", true);
  y -= 40;
  texte(50, y, 11, "Cachet de l'église", true);
  return assemblerPdf(lignes, d.logo ?? null);
}

export interface RecuPdfData {
  egliseNom: string;
  egliseCode: string;
  /** Logo de l'église (chargé par la route), null : en-tête sans logo. */
  logo?: LogoPdf | null;
  numero: string; // REC-AAAA-NNNN, par église et par année
  dateEmission: string; // JJ/MM/AAAA
  membreNom: string | null;
  membreMatricule: string | null;
  /** Libellé du type, ex. « Dîme », « Cotisation ». */
  typeLibelle: string;
  montantFcfa: number;
  /** Libellé du canal, ex. « Wave », « Espèces ». */
  paiementLibelle: string;
  dateContribution: string; // JJ/MM/AAAA
  campagneNom: string | null;
}

/**
 * Reçu numéroté d'une contribution (tranche T7, Lot B) : même approche
 * sans dépendance, une page, Helvetica. Contenu figé à la validation
 * (numéro, montant, canal), jamais recalculé. En Côte d'Ivoire, ce reçu
 * n'a aucune valeur fiscale : il sert de justificatif de la contribution.
 */
export function genererRecuPdf(d: RecuPdfData): Buffer {
  const { lignes, texte } = lignesTexte();
  let y = 760;
  texte(50, y, 16, d.egliseNom, true);
  if (d.logo) lignes.push(operateurLogo(d.logo, 501, 792, 44));
  y -= 20;
  texte(50, y, 11, `Code : ${d.egliseCode}`);
  y -= 32;
  texte(50, y, 15, "Reçu de contribution", true);
  y -= 22;
  texte(50, y, 11, `Numéro : ${d.numero}`);
  y -= 18;
  texte(50, y, 11, `Date d'émission : ${d.dateEmission}`);
  y -= 32;
  texte(50, y, 12, `Reçu de : ${d.membreNom ?? "Donateur non identifié"}`, true);
  if (d.membreMatricule) {
    y -= 18;
    texte(50, y, 11, `Matricule : ${d.membreMatricule}`);
  }
  y -= 32;
  texte(50, y, 12, `Type : ${d.typeLibelle}`, true);
  y -= 20;
  texte(50, y, 11, `Montant : ${formaterMontant(d.montantFcfa)}`);
  y -= 18;
  texte(50, y, 11, `Payé par : ${d.paiementLibelle}`);
  y -= 18;
  texte(50, y, 11, `Date de la contribution : ${d.dateContribution}`);
  if (d.campagneNom) {
    y -= 18;
    texte(50, y, 11, `Campagne : ${d.campagneNom}`);
  }
  y -= 48;
  texte(50, y, 11, "Signature : ____________________", true);
  y -= 40;
  texte(50, y, 11, "Cachet de l'église", true);
  y -= 32;
  texte(50, y, 10, "En Côte d'Ivoire, ce reçu n'a aucune valeur fiscale.");
  y -= 15;
  texte(50, y, 10, "Il sert de justificatif de votre contribution,");
  y -= 15;
  texte(50, y, 10, "pas de déclaration d'impôt.");
  return assemblerPdf(lignes, d.logo ?? null);
}
