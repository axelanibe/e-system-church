import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";

/**
 * Chiffrement des identifiants API de paiement (module 14).
 *
 * - AES-256-GCM : une clé serveur de 32 octets, lue dans la variable
 *   d'environnement PAYMENT_SECRETS_KEY (64 caractères hex ou base64).
 * - Chaque secret a son propre IV aléatoire (12 octets) et son tag GCM.
 * - L'empreinte SHA-256 de la valeur claire permet de détecter un
 *   changement sans jamais stocker la valeur.
 * - La valeur claire n'existe qu'en mémoire, au moment de l'exécution ;
 *   elle n'est jamais renvoyée par l'API, jamais journalisée.
 *
 * Limite honnête : le serveur doit déchiffrer pour exécuter — la
 * protection vaut contre toute lecture (plateforme, autres églises,
 * base volée), pas contre celui qui contrôle physiquement le serveur.
 */

export interface EncryptedSecret {
  /** Chiffré, encodé base64. */
  valeur_chiffree: string;
  /** IV, hex (12 octets). */
  iv: string;
  /** Tag d'authentification GCM, hex. */
  tag: string;
  /** SHA-256 hex de la valeur claire. */
  empreinte: string;
}

/** Clé AES-256 (32 octets) depuis PAYMENT_SECRETS_KEY. */
export function getPaymentSecretsKey(): Buffer {
  const raw = (process.env.PAYMENT_SECRETS_KEY ?? "").trim();
  if (!raw) {
    throw new Error("PAYMENT_SECRETS_KEY non configurée.");
  }
  let key: Buffer;
  if (/^[0-9a-fA-F]{64}$/.test(raw)) {
    key = Buffer.from(raw, "hex");
  } else {
    key = Buffer.from(raw, "base64");
  }
  if (key.length !== 32) {
    throw new Error(
      "PAYMENT_SECRETS_KEY invalide : 32 octets attendus (64 caractères hex ou base64).",
    );
  }
  return key;
}

/** Chiffre une valeur claire (IV aléatoire à chaque appel). */
export function encryptSecret(plaintext: string): EncryptedSecret {
  const key = getPaymentSecretsKey();
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const chiffre = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  return {
    valeur_chiffree: chiffre.toString("base64"),
    iv: iv.toString("hex"),
    tag: cipher.getAuthTag().toString("hex"),
    empreinte: createHash("sha256").update(plaintext, "utf8").digest("hex"),
  };
}

/** Déchiffre en mémoire. Lève une erreur si le tag ne correspond pas. */
export function decryptSecret(enc: {
  valeur_chiffree: string;
  iv: string;
  tag: string;
}): string {
  const key = getPaymentSecretsKey();
  const decipher = createDecipheriv(
    "aes-256-gcm",
    key,
    Buffer.from(enc.iv, "hex"),
  );
  decipher.setAuthTag(Buffer.from(enc.tag, "hex"));
  const clair = Buffer.concat([
    decipher.update(Buffer.from(enc.valeur_chiffree, "base64")),
    decipher.final(),
  ]);
  return clair.toString("utf8");
}

/** Aperçu masqué d'un secret : •••• + 4 derniers caractères. */
export function maskSecret(value: string): string {
  const v = value.trim();
  if (v.length <= 4) return "••••";
  return `••••${v.slice(-4)}`;
}
