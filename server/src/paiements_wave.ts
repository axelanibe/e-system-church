import { request as httpsRequest } from "node:https";

/**
 * Adaptateur Wave (module 14, MVP) — API Checkout Wave Business
 * (https://api.wave.com/v1/checkout/sessions).
 *
 * La clé API de l'église est passée en mémoire uniquement, jamais
 * journalisée. Les autres fournisseurs (Orange, MTN, M-Pesa, PayPal,
 * Stripe) sont configurables mais leur exécution reste à brancher
 * selon leur API — le framework (catalogue + secrets chiffrés) est
 * le même pour tous.
 */

const WAVE_HOST = "api.wave.com";

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
    const req = httpsRequest(
      {
        hostname: WAVE_HOST,
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
