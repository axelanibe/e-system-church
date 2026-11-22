// Témoignages (lot 3c, 22 novembre 2026) : règles de validation
// partagées par les routes, sans accès base — testables sans PostgreSQL.
// Modèle : Connexion Prophétique (server-production/src/temoignages.js),
// adapté à e-System Church : isolation par church_id, statuts
// en_attente / approuve / rejete, médias stockés en base (BYTEA) faute
// de compartiment objet — pas de R2 ici, les prédications ne stockent
// que des URL externes. Le type réel est vérifié dans les octets
// (signature magique), jamais d'après le nom ou l'en-tête envoyé.

/// Taille maximale d'une photo, comme les stories de Connexion Prophétique.
export const TAILLE_MAX_PHOTO_TEMOIGNAGE_OCTETS = 5 * 1024 * 1024;

/// Taille maximale d'une vidéo, envoyée telle quelle, courte.
export const TAILLE_MAX_VIDEO_TEMOIGNAGE_OCTETS = 25 * 1024 * 1024;

/// Taille maximale d'un audio, 10 Mo.
export const TAILLE_MAX_AUDIO_TEMOIGNAGE_OCTETS = 10 * 1024 * 1024;

/// Durée maximale d'une vidéo, vérifiée côté application seulement :
/// 60 secondes, comme les stories.
export const DUREE_MAX_VIDEO_TEMOIGNAGE_SECONDES = 60;

/// Durée maximale d'un audio, vérifiée côté application seulement :
/// 5 minutes.
export const DUREE_MAX_AUDIO_TEMOIGNAGE_SECONDES = 300;

/// Longueur maximale du texte, côté application et serveur.
export const LONGUEUR_MAX_TEXTE_TEMOIGNAGE = 2000;

/// Nombre maximal de publications par heure et par auteur (anti-spam,
/// même motif que le limiteur de la messagerie).
export const LIMITE_PUBLICATIONS_TEMOIGNAGE_PAR_HEURE = 10;

/// Taille maximale du corps JSON accepté à la publication (base64
/// d'une vidéo de 25 Mo ≈ 33,4 Mo, plus le texte et l'enveloppe).
export const LIMITE_CORPS_PUBLICATION_TEMOIGNAGE_OCTETS = 40 * 1024 * 1024;

export const MIMES_PHOTO_TEMOIGNAGE = Object.freeze([
  "image/jpeg",
  "image/png",
  "image/webp",
] as const);
export const MIMES_VIDEO_TEMOIGNAGE = Object.freeze([
  "video/mp4",
  "video/quicktime",
  "video/webm",
] as const);
export const MIMES_AUDIO_TEMOIGNAGE = Object.freeze([
  "audio/mp4",
  "audio/mpeg",
  "audio/ogg",
  "audio/wav",
  "audio/x-m4a",
] as const);

/// États d'un témoignage : en attente à la publication, approuvé
/// visible dans le fil, rejeté visible par son auteur seulement.
export const STATUTS_TEMOIGNAGE = Object.freeze([
  "en_attente",
  "approuve",
  "rejete",
] as const);

export type StatutTemoignage = (typeof STATUTS_TEMOIGNAGE)[number];

export type TypeMediaTemoignage = "texte" | "photo" | "video" | "audio";

/// Vrai quand le statut est l'un des trois connus.
export function statutTemoignageValide(statut: unknown): statut is StatutTemoignage {
  return (
    typeof statut === "string" &&
    (STATUTS_TEMOIGNAGE as readonly string[]).includes(statut)
  );
}

/// Type de média depuis le type réel : photo, vidéo, audio, ou texte
/// quand il n'y a pas de média.
export function typeMediaDepuisMime(mime: string | null | undefined): TypeMediaTemoignage {
  if (typeof mime !== "string") return "texte";
  if (mime.startsWith("image/")) return "photo";
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  return "texte";
}

/// Taille maximale acceptée pour un type réel, null quand le type
/// n'est pas autorisé.
export function tailleMaxPourMime(mime: string): number | null {
  if ((MIMES_PHOTO_TEMOIGNAGE as readonly string[]).includes(mime)) {
    return TAILLE_MAX_PHOTO_TEMOIGNAGE_OCTETS;
  }
  if ((MIMES_AUDIO_TEMOIGNAGE as readonly string[]).includes(mime)) {
    return TAILLE_MAX_AUDIO_TEMOIGNAGE_OCTETS;
  }
  if ((MIMES_VIDEO_TEMOIGNAGE as readonly string[]).includes(mime)) {
    return TAILLE_MAX_VIDEO_TEMOIGNAGE_OCTETS;
  }
  return null;
}

/**
 * Type MIME réel détecté dans les premiers octets (signature
 * magique), null quand le contenu n'est pas reconnu. MP4, M4A et MOV
 * partagent la boîte `ftyp` : la marque majeure distingue la vidéo
 * (isom, mp41, mp42, dash), l'audio M4A (M4A ) et QuickTime (qt  ).
 */
export function detecterMimeReel(octets: Buffer): string | null {
  if (octets.length >= 3 && octets[0] === 0xff && octets[1] === 0xd8 && octets[2] === 0xff) {
    return "image/jpeg";
  }
  if (
    octets.length >= 8 &&
    octets[0] === 0x89 && octets[1] === 0x50 && octets[2] === 0x4e && octets[3] === 0x47 &&
    octets[4] === 0x0d && octets[5] === 0x0a && octets[6] === 0x1a && octets[7] === 0x0a
  ) {
    return "image/png";
  }
  if (
    octets.length >= 12 &&
    octets.subarray(0, 4).toString("ascii") === "RIFF" &&
    octets.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return "image/webp";
  }
  if (
    octets.length >= 12 &&
    octets.subarray(0, 4).toString("ascii") === "RIFF" &&
    octets.subarray(8, 12).toString("ascii") === "WAVE"
  ) {
    return "audio/wav";
  }
  if (octets.length >= 4 && octets.subarray(0, 4).toString("ascii") === "OggS") {
    return "audio/ogg";
  }
  if (
    octets.length >= 3 &&
    octets.subarray(0, 3).toString("ascii") === "ID3"
  ) {
    return "audio/mpeg";
  }
  if (
    octets.length >= 2 &&
    octets[0] === 0xff && (octets[1] & 0xe0) === 0xe0
  ) {
    return "audio/mpeg";
  }
  if (octets.length >= 4 && octets[0] === 0x1a && octets[1] === 0x45 && octets[2] === 0xdf && octets[3] === 0xa3) {
    return "video/webm";
  }
  if (octets.length >= 12 && octets.subarray(4, 8).toString("ascii") === "ftyp") {
    const marque = octets.subarray(8, 12).toString("ascii");
    if (marque === "M4A ") return "audio/mp4";
    if (marque === "qt  ") return "video/quicktime";
    if (["isom", "mp41", "mp42", "dash", "M4V "].includes(marque)) return "video/mp4";
    return null;
  }
  return null;
}

/**
 * Refus de publication, null quand tout est bon. Le type réel est
 * vérifié dans les octets, jamais d'après le nom ou le type déclaré :
 * un écart entre le type déclaré et le type réel est refusé (415).
 * Un texte seul est accepté, sans média : média null et texte non vide.
 */
export function validerTemoignage({
  mime,
  tailleOctets,
  texte,
}: {
  mime: string | null | undefined;
  tailleOctets: number | null | undefined;
  texte: unknown;
}): { statut: number; message: string } | null {
  const textePropre = typeof texte === "string" ? texte.trim() : "";
  if (textePropre.length > LONGUEUR_MAX_TEXTE_TEMOIGNAGE) {
    return { statut: 400, message: "Texte trop long : 2000 caractères au plus." };
  }
  if (mime == null) {
    if (textePropre.length === 0) {
      return { statut: 400, message: "Ajoutez un texte ou un média." };
    }
    return null;
  }
  const max = tailleMaxPourMime(mime);
  if (max == null) {
    return { statut: 415, message: "Type de média non autorisé." };
  }
  if (!Number.isInteger(tailleOctets) || (tailleOctets as number) <= 0 || (tailleOctets as number) > max) {
    return { statut: 413, message: "Média trop volumineux." };
  }
  return null;
}

/**
 * Décodage et contrôle complet d'une publication reçue en base64 :
 * base64 valide, taille, type réel détecté dans les octets, cohérence
 * avec le type déclaré. Renvoie les octets et le type réel, ou le
 * refus à renvoyer tel quel.
 */
export function decoderMediaTemoignage({
  mediaBase64,
  mediaMime,
  texte,
}: {
  mediaBase64: unknown;
  mediaMime: unknown;
  texte: unknown;
}):
  | { octets: Buffer; mimeReel: string; typeMedia: TypeMediaTemoignage }
  | { statut: number; message: string } {
  if (mediaBase64 == null || mediaBase64 === "") {
    const refus = validerTemoignage({ mime: null, tailleOctets: null, texte });
    if (refus) return refus;
    return { octets: Buffer.alloc(0), mimeReel: "", typeMedia: "texte" };
  }
  if (typeof mediaBase64 !== "string" || typeof mediaMime !== "string") {
    return { statut: 400, message: "Média invalide : contenu base64 et type MIME attendus." };
  }
  let octets: Buffer;
  try {
    octets = Buffer.from(mediaBase64, "base64");
  } catch {
    return { statut: 400, message: "Média invalide : contenu base64 illisible." };
  }
  // Un base64 mal formé se décode sans erreur en octets parasites :
  // le ré-encodage doit retomber sur la même chaîne (à la casse et
  // au remplissage près).
  const reencode = octets.toString("base64");
  const normalise = (s: string) => s.replace(/=+$/, "");
  if (normalise(reencode) !== normalise(mediaBase64.replace(/\s/g, ""))) {
    return { statut: 400, message: "Média invalide : contenu base64 illisible." };
  }
  const mimeReel = detecterMimeReel(octets);
  if (mimeReel == null) {
    return { statut: 415, message: "Type de média non reconnu." };
  }
  if (mimeReel !== mediaMime) {
    return {
      statut: 415,
      message: "Le type de média déclaré ne correspond pas au contenu du fichier.",
    };
  }
  const refus = validerTemoignage({ mime: mimeReel, tailleOctets: octets.length, texte });
  if (refus) return refus;
  return { octets, mimeReel, typeMedia: typeMediaDepuisMime(mimeReel) };
}

/// Forme publique d'un témoignage : jamais les octets du média, jamais
/// l'identifiant de l'auteur, seulement le lien de téléchargement, le
/// nom de l'auteur et le statut. Le texte et le type de média sont
/// renvoyés, le lien est null pour un texte seul.
export function formaterTemoignagePublic(ligne: {
  id: string;
  auteur_nom?: string | null;
  texte?: string | null;
  type_media?: string | null;
  type_mime?: string | null;
  media_octets?: Buffer | null;
  statut?: string | null;
  cree_le?: Date | string | null;
}): {
  id: string;
  auteur_nom: string;
  url_media: string | null;
  texte: string;
  type_media: TypeMediaTemoignage;
  statut: string;
  cree_le: string | null;
} {
  const typeMedia = (ligne.type_media as TypeMediaTemoignage | undefined) ??
    typeMediaDepuisMime(ligne.type_mime);
  const aMedia = typeMedia !== "texte";
  return {
    id: ligne.id,
    auteur_nom: ligne.auteur_nom ?? "",
    url_media: aMedia ? `/temoignages/${ligne.id}/media` : null,
    texte: ligne.texte ?? "",
    type_media: typeMedia,
    statut: ligne.statut ?? "en_attente",
    cree_le:
      ligne.cree_le == null
        ? null
        : ligne.cree_le instanceof Date
          ? ligne.cree_le.toISOString()
          : String(ligne.cree_le),
  };
}
