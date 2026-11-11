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
  numero: string;
  annee: number;
  dateEmission: string; // JJ/MM/AAAA
  donateurNom: string;
  donateurMatricule: string | null;
  dons: LignePdf[];
  totalFcfa: number;
}

function formaterMontant(n: number): string {
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

export function genererAttestationPdf(d: AttestationPdfData): Buffer {
  const lignes: string[] = [];
  let y = 760;
  const texte = (x: number, yy: number, taille: number, s: string, gras = false) => {
    lignes.push(
      `BT /${gras ? "F2" : "F1"} ${taille} Tf ${x} ${yy} Td ${litteral(s)} Tj ET`,
    );
  };
  texte(50, y, 16, d.egliseNom, true);
  y -= 20;
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
  const contenu = lignes.join("\n");
  const objets: string[] = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    `<< /Length ${Buffer.byteLength(contenu)} >>\nstream\n${contenu}\nendstream`,
  ];
  const parties: Buffer[] = [Buffer.from("%PDF-1.4\n", "latin1")];
  const offsets: number[] = [0];
  let pos = parties[0].length;
  objets.forEach((o, i) => {
    offsets.push(pos);
    const b = Buffer.from(`${i + 1} 0 obj\n${o}\nendobj\n`, "latin1");
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
