/**
 * Logo d'église pour les PDF (tranche logo église) : charge le logo
 * stocké côté serveur (`/logos/...`) ou une URL externe, le décode
 * (JPEG brut, PNG décodé en RVB) et le rend prêt à intégrer comme
 * image PDF. Ne lève jamais : absence, fichier illisible ou format
 * non pris en charge donnent null, et le document est généré sans logo.
 */
import { readFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";

export interface LogoPdf {
  largeur: number;
  hauteur: number;
  /** true : JPEG brut (DCTDecode) ; false : RVB brut (FlateDecode). */
  jpeg: boolean;
  donnees: Buffer;
}

const LOGOS_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  "uploads",
  "logos",
);
const MAX_LOGO_OCTETS = 2 * 1024 * 1024; // 2 Mo, comme le téléversement
const MAX_LOGO_PIXELS = 4_000_000;

const PNG_MAGIC = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);
const JPG_MAGIC = Buffer.from([0xff, 0xd8, 0xff]);

function estPng(b: Buffer): boolean {
  return b.length >= 8 && b.subarray(0, 8).equals(PNG_MAGIC);
}

function estJpg(b: Buffer): boolean {
  return b.length >= 3 && b.subarray(0, 3).equals(JPG_MAGIC);
}

/** Dimensions d'un JPEG : cherche le premier segment SOF0, SOF1 ou SOF2. */
export function dimensionsJpeg(
  b: Buffer,
): { largeur: number; hauteur: number } | null {
  let i = 2; // après SOI
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) return null;
    const marqueur = b[i + 1];
    // Marqueurs sans longueur : SOI, TEM, RSTn.
    if (
      marqueur === 0xd8 ||
      marqueur === 0x01 ||
      (marqueur >= 0xd0 && marqueur <= 0xd7)
    ) {
      i += 2;
      continue;
    }
    // Début des données compressées : plus aucun segment à lire.
    if (marqueur === 0xda) return null;
    const longueur = b.readUInt16BE(i + 2);
    if (longueur < 2 || i + 2 + longueur > b.length) return null;
    if (marqueur === 0xc0 || marqueur === 0xc1 || marqueur === 0xc2) {
      return {
        hauteur: b.readUInt16BE(i + 5),
        largeur: b.readUInt16BE(i + 7),
      };
    }
    i += 2 + longueur;
  }
  return null;
}

/**
 * Décode un PNG 8 bits non entrelacé (types 0, 2, 3, 4, 6) en RVB brut.
 * Un PNG entrelacé ou d'une autre profondeur donne null : le document
 * est alors généré sans logo.
 */
export function decoderPng(b: Buffer): LogoPdf | null {
  if (!estPng(b)) return null;
  let pos = 8;
  let largeur = 0;
  let hauteur = 0;
  let profondeur = 0;
  let typeCouleur = 0;
  let entrelacement = 0;
  let palette: Buffer | null = null;
  const idat: Buffer[] = [];
  while (pos + 8 <= b.length) {
    const longueur = b.readUInt32BE(pos);
    const type = b.toString("latin1", pos + 4, pos + 8);
    if (pos + 12 + longueur > b.length) return null;
    const donnees = b.subarray(pos + 8, pos + 8 + longueur);
    if (type === "IHDR") {
      largeur = donnees.readUInt32BE(0);
      hauteur = donnees.readUInt32BE(4);
      profondeur = donnees[8];
      typeCouleur = donnees[9];
      entrelacement = donnees[12];
    } else if (type === "PLTE") {
      palette = Buffer.from(donnees);
    } else if (type === "IDAT") {
      idat.push(Buffer.from(donnees));
    } else if (type === "IEND") {
      break;
    }
    pos += 12 + longueur;
  }
  if (!largeur || !hauteur || profondeur !== 8 || entrelacement !== 0) {
    return null;
  }
  if (largeur * hauteur > MAX_LOGO_PIXELS) return null;
  const canaux =
    typeCouleur === 2
      ? 3
      : typeCouleur === 6
        ? 4
        : typeCouleur === 0 || typeCouleur === 3
          ? 1
          : typeCouleur === 4
            ? 2
            : 0;
  if (!canaux || (typeCouleur === 3 && !palette)) return null;
  let brut: Buffer;
  try {
    brut = inflateSync(Buffer.concat(idat));
  } catch {
    return null;
  }
  const pas = largeur * canaux;
  if (brut.length < hauteur * (pas + 1)) return null;
  const pixels = Buffer.alloc(largeur * hauteur * 3);
  let precedente = Buffer.alloc(pas);
  for (let y = 0; y < hauteur; y++) {
    const filtre = brut[y * (pas + 1)];
    const ligne = brut.subarray(y * (pas + 1) + 1, (y + 1) * (pas + 1));
    const reconstruite = Buffer.alloc(pas);
    for (let x = 0; x < pas; x++) {
      const a = x >= canaux ? reconstruite[x - canaux] : 0;
      const bb = precedente[x];
      const c = x >= canaux ? precedente[x - canaux] : 0;
      let v = ligne[x];
      if (filtre === 1) v = (v + a) & 0xff;
      else if (filtre === 2) v = (v + bb) & 0xff;
      else if (filtre === 3) v = (v + ((a + bb) >> 1)) & 0xff;
      else if (filtre === 4) {
        const p = a + bb - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - bb);
        const pc = Math.abs(p - c);
        v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? bb : c)) & 0xff;
      } else if (filtre !== 0) return null;
      reconstruite[x] = v;
    }
    for (let x = 0; x < largeur; x++) {
      const o = (y * largeur + x) * 3;
      if (typeCouleur === 2) {
        pixels[o] = reconstruite[x * 3];
        pixels[o + 1] = reconstruite[x * 3 + 1];
        pixels[o + 2] = reconstruite[x * 3 + 2];
      } else if (typeCouleur === 6) {
        pixels[o] = reconstruite[x * 4];
        pixels[o + 1] = reconstruite[x * 4 + 1];
        pixels[o + 2] = reconstruite[x * 4 + 2];
      } else if (typeCouleur === 0) {
        const g = reconstruite[x];
        pixels[o] = g;
        pixels[o + 1] = g;
        pixels[o + 2] = g;
      } else if (typeCouleur === 4) {
        const g = reconstruite[x * 2];
        pixels[o] = g;
        pixels[o + 1] = g;
        pixels[o + 2] = g;
      } else {
        // Type 3 : palette.
        const idx = reconstruite[x] * 3;
        pixels[o] = palette![idx];
        pixels[o + 1] = palette![idx + 1];
        pixels[o + 2] = palette![idx + 2];
      }
    }
    precedente = reconstruite;
  }
  return { largeur, hauteur, jpeg: false, donnees: pixels };
}

/** Décode un logo JPEG ou PNG en image prête pour le PDF, sinon null. */
export function decoderImage(b: Buffer): LogoPdf | null {
  if (estJpg(b)) {
    const dims = dimensionsJpeg(b);
    if (
      !dims ||
      !dims.largeur ||
      !dims.hauteur ||
      dims.largeur * dims.hauteur > MAX_LOGO_PIXELS
    ) {
      return null;
    }
    return { ...dims, jpeg: true, donnees: b };
  }
  if (estPng(b)) return decoderPng(b);
  return null;
}

/**
 * Charge le logo d'une église depuis son URL stockée : `/logos/...`
 * (fichier local) ou URL externe. Ne lève jamais.
 */
export async function chargerLogo(
  logoUrl: string | null | undefined,
): Promise<LogoPdf | null> {
  try {
    if (!logoUrl) return null;
    let buffer: Buffer | null = null;
    if (logoUrl.startsWith("/logos/")) {
      const fichier = basename(logoUrl);
      if (
        fichier !== logoUrl.slice("/logos/".length) ||
        !/^[A-Za-z0-9._-]+$/.test(fichier)
      ) {
        return null;
      }
      try {
        buffer = await readFile(join(LOGOS_DIR, fichier));
      } catch {
        return null;
      }
    } else if (
      logoUrl.startsWith("https://") ||
      logoUrl.startsWith("http://")
    ) {
      const reponse = await fetch(logoUrl, {
        signal: AbortSignal.timeout(5000),
      });
      if (!reponse.ok) return null;
      const ab = await reponse.arrayBuffer();
      if (ab.byteLength === 0 || ab.byteLength > MAX_LOGO_OCTETS) return null;
      buffer = Buffer.from(ab);
    } else {
      return null;
    }
    if (buffer.length > MAX_LOGO_OCTETS) return null;
    return decoderImage(buffer);
  } catch {
    return null;
  }
}
