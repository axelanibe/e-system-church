import { createHmac, timingSafeEqual } from "node:crypto";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";

/**
 * Adaptateur Wave (module 14, MVP) — API Checkout Wave Business
 * (https://api.wave.com/v1/checkout/sessions) et webhooks
 * (docs.wave.com/webhook, tranche T8).
 *
 * La clé API de l'église est passée en mémoire uniquement, jamais
 * journalisée. Les autres fournisseurs (Orange, MTN, M-Pesa, PayPal,
 * Stripe) sont configurables mais leur exécution reste à brancher
 * selon leur API — le framework (catalogue + secrets chiffrés) est
 * le même pour tous.
 *
 * URL de base surchargeable par WAVE_API_BASE_URL (tests : un faux
 * serveur local en http://127.0.0.1:PORT) — par défaut l'API réelle.
 */

function waveBaseUrl(): URL {
  const raw = process.env.WAVE_API_BASE_URL?.trim() || "https://api.wave.com";
  try {
    return new URL(raw);
  } catch {
    return new URL("https://api.wave.com");
  }
}

interface WaveHttpResult {
  status: number;
  body: string;
}

function waveRequest(
  apiKey: string,
  method: "GET" | "POST",
  path: string,
  payload?: Record<string, string>,
): Promise<WaveHttpResult> {
  return new Promise((resolve, reject) => {
    const data = payload ? JSON.stringify(payload) : undefined;
    const base = waveBaseUrl();
    const requestFn = base.protocol === "http:" ? httpRequest : httpsRequest;
    const req = requestFn(
      {
        hostname: base.hostname,
        port: base.port ? Number(base.port) : undefined,
        path: `/v1${path}`,
        method,
        timeout: 15000,
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          ...(data
            ? { "Content-Length": Buffer.byteLength(data).toString() }
            : {}),
        },
      },
      (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk: Buffer | string) => {
          chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        });
        res.on("end", () => {
          resolve({
            status: res.statusCode ?? 0,
            body: Buffer.concat(chunks).toString("utf8"),
          });
        });
      },
    );
    req.on("timeout", () => {
      req.destroy(new Error("Délai dépassé (Wave)."));
    });
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

/**
 * Vérifie l'en-tête `Wave-Signature` d'un webhook Wave
 * (docs.wave.com/webhook) : `Wave-Signature: t=<horodatage>,v1=<hex>`.
 * HMAC-SHA256 de `horodatage + corps brut` (l'exemple officiel concatène
 * directement, sans point — on accepte aussi `horodatage.corps` par
 * tolérance). Plusieurs signatures v1 sont possibles (rotation de clé) :
 * l'une d'elles suffit. Comparaison en temps constant ; rejet si
 * l'horodatage est trop ancien (tolérance 5 min par défaut).
 * Retourne false pour tout en-tête absent ou mal formé.
 */
export function verifierSignatureWebhookWave(
  secret: string,
  signatureHeader: string | string[] | undefined,
  rawBody: string,
  toleranceSec = 300,
): boolean {
  if (!secret || typeof signatureHeader !== "string") return false;
  const parties = new Map<string, string[]>();
  for (const morceau of signatureHeader.split(",")) {
    const [cle, ...reste] = morceau.split("=");
    if (!cle || reste.length === 0) continue;
    const valeurs = parties.get(cle.trim()) ?? [];
    valeurs.push(reste.join("=").trim());
    parties.set(cle.trim(), valeurs);
  }
  const horodatages = parties.get("t") ?? [];
  const signatures = parties.get("v1") ?? [];
  if (horodatages.length === 0 || signatures.length === 0) return false;
  const horodatage = Number(horodatages[0]);
  if (!Number.isFinite(horodatage)) return false;
  const maintenant = Math.floor(Date.now() / 1000);
  if (Math.abs(maintenant - horodatage) > toleranceSec) return false;
  for (const preimage of [`${horodatage}${rawBody}`, `${horodatage}.${rawBody}`]) {
    const attendu = createHmac("sha256", secret).update(preimage, "utf8").digest();
    for (const sig of signatures) {
      const recu = Buffer.from(sig, "hex");
      if (recu.length === attendu.length && timingSafeEqual(recu, attendu)) {
        return true;
      }
    }
  }
  return false;
}

export interface WaveCheckoutSession {
  id: string;
  amount: number;
  currency: string;
  checkoutStatus: string;
  whenCompleted: string | null;
}

/**
 * Re-interroge une session de paiement Wave
 * (GET /v1/checkout/sessions/{id}). La notification webhook n'est
 * jamais crue sur parole : la session doit être `complete` côté Wave
 * pour confirmer. Retourne null si la session n'existe pas (404) ou
 * si la réponse est inexploitable ; lève une erreur sur un autre
 * statut HTTP (l'appelant décide alors de faire confiance à
 * l'événement signé ou de le marquer à vérifier).
 */
export async function getWaveCheckoutSession(
  apiKey: string,
  sessionId: string,
): Promise<WaveCheckoutSession | null> {
  const { status, body } = await waveRequest(
    apiKey,
    "GET",
    `/checkout/sessions/${encodeURIComponent(sessionId)}`,
  );
  if (status === 404) return null;
  if (status < 200 || status >= 300) {
    throw new Error(`Wave a refusé la re-interrogation de la session (HTTP ${status}).`);
  }
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(body) as Record<string, unknown>;
  } catch {
    return null;
  }
  if (typeof parsed.id !== "string") return null;
  return {
    id: parsed.id,
    amount: Number(parsed.amount ?? NaN),
    currency: typeof parsed.currency === "string" ? parsed.currency : "",
    checkoutStatus:
      typeof parsed.checkout_status === "string" ? parsed.checkout_status : "",
    whenCompleted:
      typeof parsed.when_completed === "string" ? parsed.when_completed : null,
  };
}

/**
 * Test de connexion (succès / échec seulement) : on interroge une
 * session inexistante — une clé valide renvoie 404, une clé invalide
 * 401 ou 403.
 */
export async function testWaveConnection(
  apiKey: string,
): Promise<{ ok: boolean; message: string }> {
  try {
    const { status } = await waveRequest(
      apiKey,
      "GET",
      "/checkout/sessions/cos-000000000000000000000000",
    );
    if (status === 401 || status === 403) {
      return {
        ok: false,
        message: "Clé API Wave refusée (vérifiez la clé saisie).",
      };
    }
    if (status === 404) {
      return { ok: true, message: "Connexion Wave OK." };
    }
    return {
      ok: true,
      message: `Wave a répondu (HTTP ${status}) : clé acceptée.`,
    };
  } catch (e) {
    return {
      ok: false,
      message: `Connexion Wave impossible : ${(e as Error).message}`,
    };
  }
}

export interface WaveCheckoutInput {
  amount: number;
  currency: string;
  successUrl: string;
  errorUrl: string;
}

/** Crée une session de paiement Wave et renvoie son lien de paiement. */
export async function createWaveCheckoutSession(
  apiKey: string,
  input: WaveCheckoutInput,
): Promise<{ sessionId: string; launchUrl: string }> {
  const { status, body } = await waveRequest(apiKey, "POST", "/checkout/sessions", {
    amount: String(input.amount),
    currency: input.currency,
    success_url: input.successUrl,
    error_url: input.errorUrl,
  });
  let parsed: { id?: string; wave_launch_url?: string } = {};
  try {
    parsed = JSON.parse(body) as { id?: string; wave_launch_url?: string };
  } catch {
    // Réponse non JSON : l'erreur HTTP ci-dessous suffit.
  }
  if (status < 200 || status >= 300) {
    throw new Error(`Wave a refusé la session de paiement (HTTP ${status}).`);
  }
  if (!parsed.id || !parsed.wave_launch_url) {
    throw new Error("Réponse Wave incomplète (session sans lien de paiement).");
  }
  return { sessionId: parsed.id, launchUrl: parsed.wave_launch_url };
}
