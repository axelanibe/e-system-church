import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * TOTP RFC 6238 (2FA, tranche T11) : sans dépendance externe.
 *
 * - Secret : 20 octets aléatoires, encodés base32 (RFC 4648).
 * - Code : HMAC-SHA1 du compteur (pas de 30 s), troncature dynamique,
 *   6 chiffres. Vérification avec une fenêtre de ±1 pas (dérive
 *   d'horloge du téléphone).
 * - Le secret n'est JAMAIS stocké en clair : il est chiffré AES-256-GCM
 *   (paiements_crypto) avant insertion en base, et n'est renvoyé qu'une
 *   seule fois, à l'activation (URI otpauth à scanner en QR).
 */

const ALPHABET_BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/** 20 octets aléatoires encodés en base32 (sans bourrage). */
export function genererSecretTOTP(): string {
  const octets = randomBytes(20);
  let bits = 0;
  let valeur = 0;
  let sortie = "";
  for (const octet of octets) {
    valeur = (valeur << 8) | octet;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sortie += ALPHABET_BASE32[(valeur >> bits) & 31];
    }
  }
  if (bits > 0) {
    sortie += ALPHABET_BASE32[(valeur << (5 - bits)) & 31];
  }
  return sortie;
}

/** Décodage base32 (insensible à la casse, bourrage facultatif). */
export function decoderBase32(secret: string): Buffer {
  const propre = secret.toUpperCase().replace(/=+$/, "");
  let bits = 0;
  let valeur = 0;
  const octets: number[] = [];
  for (const caractere of propre) {
    const index = ALPHABET_BASE32.indexOf(caractere);
    if (index < 0) throw new Error("Secret TOTP invalide.");
    valeur = (valeur << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      octets.push((valeur >> bits) & 255);
    }
  }
  return Buffer.from(octets);
}

/** URI otpauth:// à afficher en QR Code dans l'application. */
export function uriTOTP(secret: string, compte: string, emetteur = "e-System Church"): string {
  const libelle = `${encodeURIComponent(emetteur)}:${encodeURIComponent(compte)}`;
  return (
    `otpauth://totp/${libelle}` +
    `?secret=${secret}&issuer=${encodeURIComponent(emetteur)}` +
    `&algorithm=SHA1&digits=6&period=30`
  );
}

function codePourCompteur(secret: Buffer, compteur: number): string {
  const tampon = Buffer.alloc(8);
  tampon.writeBigUInt64BE(BigInt(compteur));
  const hmac = createHmac("sha1", secret).update(tampon).digest();
  const decalage = hmac[hmac.length - 1] & 0x0f;
  const valeur =
    ((hmac[decalage] & 0x7f) << 24) |
    ((hmac[decalage + 1] & 0xff) << 16) |
    ((hmac[decalage + 2] & 0xff) << 8) |
    (hmac[decalage + 3] & 0xff);
  return String(valeur % 1_000_000).padStart(6, "0");
}

/**
 * Vérifie un code à 6 chiffres, fenêtre ±1 pas de 30 s.
 * La comparaison est à temps constant (pas de fuite par chronométrage).
 */
export function verifierCodeTOTP(secret: string, code: string, fenetre = 1): boolean {
  if (!/^\d{6}$/.test(code)) return false;
  let cle: Buffer;
  try {
    cle = decoderBase32(secret);
  } catch {
    return false;
  }
  const compteur = Math.floor(Date.now() / 1000 / 30);
  for (let delta = -fenetre; delta <= fenetre; delta += 1) {
    const attendu = codePourCompteur(cle, compteur + delta);
    if (timingSafeEqual(Buffer.from(attendu, "utf8"), Buffer.from(code, "utf8"))) {
      return true;
    }
  }
  return false;
}
