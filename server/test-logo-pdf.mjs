/* Test local tranche logo église — décodeur d'image et intégration du
 * logo dans les PDF, sans base de données ni API.
 * Usage (depuis server/) : npm run build && node test-logo-pdf.mjs
 * Les imports visent dist/ (compilé) : la CI tourne sous Node 20, qui ne
 * lit pas les .ts directement (Node 24 le fait, d'où le piège).
 */
import { deflateSync } from "node:zlib";
import {
  genererAttestationEvenementPdf,
  genererAttestationPdf,
  genererRapportPdf,
  genererRecuPdf,
} from "./dist/pdf.js";
import {
  chargerLogo,
  decoderImage,
  dimensionsJpeg,
} from "./dist/logo_pdf.js";

let ok = 0;
let ko = 0;
function check(nom, cond, extra = "") {
  if (cond) {
    ok++;
    console.log(`  OK  ${nom}`);
  } else {
    ko++;
    console.log(`  KO  ${nom} ${extra}`);
  }
}

// -- PNG 1x1 rouge, construit ici (CRC32 + zlib, aucune fixture). --------
const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunkPng(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const corps = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(corps));
  return Buffer.concat([len, corps, crc]);
}
const png1x1 = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunkPng(
    "IHDR",
    Buffer.from([0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]),
  ),
  chunkPng("IDAT", deflateSync(Buffer.from([0, 255, 0, 0]))),
  chunkPng("IEND", Buffer.alloc(0)),
]);

// -- JPEG minimal (SOI + APP0 + SOF0 4x3), pour le parseur de dimensions. --
const jpgMini = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xc0, 0x00, 0x11,
  0x08, 0x00, 0x03, 0x00, 0x04, 0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01,
  0x03, 0x11, 0x01,
]);

const logoPng = decoderImage(png1x1);
check("PNG 1x1 rouge décodé", logoPng !== null);
check("PNG : dimensions 1x1", logoPng?.largeur === 1 && logoPng?.hauteur === 1);
check(
  "PNG : pixel rouge RVB",
  logoPng !== null &&
    logoPng.donnees.length === 3 &&
    logoPng.donnees[0] === 255 &&
    logoPng.donnees[1] === 0 &&
    logoPng.donnees[2] === 0,
);
check("PNG : pas JPEG", logoPng?.jpeg === false);

const dims = dimensionsJpeg(jpgMini);
check(
  "JPEG : dimensions lues dans SOF0",
  dims?.largeur === 4 && dims?.hauteur === 3,
  JSON.stringify(dims),
);
check("JPEG : décodé comme JPEG brut", decoderImage(jpgMini)?.jpeg === true);
check(
  "Octets inconnus : null",
  decoderImage(Buffer.from("ceci n'est pas une image")) === null,
);

check("chargerLogo(null) : null", (await chargerLogo(null)) === null);
check(
  "chargerLogo('') : null",
  (await chargerLogo("")) === null,
);
check(
  "chargerLogo fichier absent : null, sans lever",
  (await chargerLogo("/logos/inexistant-xyz.png")) === null,
);
check(
  "chargerLogo traversée de chemin : null",
  (await chargerLogo("/logos/../secret.png")) === null,
);

const rapportBase = {
  titre: "Bilan annuel",
  egliseNom: "Eglise Test",
  lignesMeta: ["Émis le 2026-11-14"],
  sections: [
    {
      titre: "Chiffres du rapport",
      colonnes: [
        { titre: "Indicateur", largeur: 335 },
        { titre: "Valeur", largeur: 160, alignerDroite: true },
      ],
      lignes: [["Membres", "12"]],
      total: ["Solde", "0 FCFA"],
    },
  ],
};
const pdfRapportLogo = genererRapportPdf({ ...rapportBase, logo: logoPng });
check("Rapport avec logo : PDF valide", pdfRapportLogo.subarray(0, 8).toString("latin1").startsWith("%PDF-1.4"));
check(
  "Rapport avec logo : image embarquée",
  pdfRapportLogo.includes(Buffer.from("/Subtype /Image", "latin1")) &&
    pdfRapportLogo.includes(Buffer.from("/Im1 Do", "latin1")),
);
const pdfRapportSans = genererRapportPdf(rapportBase);
check(
  "Rapport sans logo : aucune image",
  !pdfRapportSans.includes(Buffer.from("/Subtype /Image", "latin1")) &&
    !pdfRapportSans.includes(Buffer.from("/Im1 Do", "latin1")),
);

const attestationBase = {
  egliseNom: "Eglise Test",
  egliseCode: "ESC-AAAAAA",
  numero: "ATT-2026-0001",
  annee: 2026,
  dateEmission: "14/11/2026",
  donateurNom: "Jean Test",
  donateurMatricule: null,
  dons: [{ date: "01/01/2026", type: "Dîme", montantFcfa: 10000 }],
  totalFcfa: 10000,
};
const pdfAttLogo = genererAttestationPdf({ ...attestationBase, logo: logoPng });
check(
  "Attestation avec logo : nom de l'église en titre",
  pdfAttLogo.includes(Buffer.from("Eglise Test", "latin1")),
);
check(
  "Attestation avec logo : image embarquée",
  pdfAttLogo.includes(Buffer.from("/Subtype /Image", "latin1")),
);
const pdfAttSans = genererAttestationPdf(attestationBase);
check(
  "Attestation sans logo : nom présent, aucune image",
  pdfAttSans.includes(Buffer.from("Eglise Test", "latin1")) &&
    !pdfAttSans.includes(Buffer.from("/Subtype /Image", "latin1")),
);

const pdfEvt = genererAttestationEvenementPdf({
  egliseNom: "Eglise Test",
  egliseCode: "ESC-AAAAAA",
  logo: logoPng,
  numero: "ATT-2026-0002",
  libelleType: "Attestation de mariage",
  dateEmission: "14/11/2026",
  personneNom: "Jean Test",
  personneMatricule: null,
  dateEvenement: "14/11/2026",
  lieu: null,
  officiant: null,
  details: [],
});
check(
  "Attestation événement avec logo : image embarquée",
  pdfEvt.includes(Buffer.from("/Subtype /Image", "latin1")),
);

const pdfRecu = genererRecuPdf({
  egliseNom: "Eglise Test",
  egliseCode: "ESC-AAAAAA",
  logo: logoPng,
  numero: "REC-2026-0001",
  dateEmission: "14/11/2026",
  membreNom: "Jean Test",
  membreMatricule: null,
  typeLibelle: "Dîme",
  montantFcfa: 5000,
  paiementLibelle: "Wave",
  dateContribution: "14/11/2026",
  campagneNom: null,
});
check(
  "Reçu avec logo : image embarquée",
  pdfRecu.includes(Buffer.from("/Subtype /Image", "latin1")),
);

console.log(`\nLogo PDF : ${ok} OK, ${ko} KO.`);
process.exit(ko > 0 ? 1 : 0);
