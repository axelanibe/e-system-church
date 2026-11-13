import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";

/**
 * Adaptateur MTN MoMo — callbacks Collection (tranche T8).
 *
 * Rappel du flux (momodeveloper.mtn.com) : le marchand appelle
 * POST /collection/v1_0/requesttopay avec X-Reference-Id (UUID, c'est
 * l'identifiant de la transaction) et X-Callback-Url ; MTN répond 202
 * (corps vide) puis POSTe un callback avec externalId, referenceId,
 * status et financialTransactionId.
 *
 * **MTN ne signe pas ses callbacks** : le statut reçu n'est jamais cru
 * sur parole. Chaque callback est confirmé par re-interrogation
 * (GET /collection/v1_0/requesttopay/{referenceId}, jeton OAuth obtenu
 * avec api_user / api_key, clé d'abonnement en en-tête) : on ne confirme
 * que si le statut re-interrogé est SUCCESSFUL et que le montant
 * correspond. Le callback est envoyé une seule fois, sans nouvelle
 * tentative — en cas d'échec de la re-interrogation, l'événement est
 * marqué 'a_verifier' (à traiter manuellement, jamais confirmé).
 *
 * Environnement par défaut : bac à sable (sandbox.momodeveloper.mtn.com,
 * devise EUR). Surcharge par MTN_API_BASE_URL et MTN_ENVIRONNEMENT
 * (tests : un faux serveur local en http://127.0.0.1:PORT).
 *
 * L'exécution MTN (requesttopay) n'existe pas encore dans l'application
 * (paiements.ts renvoie 501 pour mtn_momo) : ce fichier ne sert pour
 * l'instant qu'à vérifier les callbacks. Les champs de configuration
 * utilisés (subscription_key, api_user, api_key) sont ceux du catalogue
 * (migration 001).
 */

export interface IdentifiantsMtn {
  subscriptionKey: string;
  apiUser: string;
  apiKey: string;
}

export interface CallbackMtn {
  /** X-Reference-Id — identifiant de la transaction, = payment_ref. */
  referenceId: string | null;
  /** Référence externe du marchand (souvent la payment_ref aussi). */
  externalId: string | null;
  statut: string;
  financialTransactionId: string | null;
  montant: number;
  devise: string;
  payeur: string | null;
}

export interface StatutMtn {
  status: string;
  amount: number;
  currency: string;
  financialTransactionId: string | null;
}

function mtnBaseUrl(): URL {
  const raw =
    process.env.MTN_API_BASE_URL?.trim() ||
    "https://sandbox.momodeveloper.mtn.com";
  try {
    return new URL(raw);
  } catch {
    return new URL("https://sandbox.momodeveloper.mtn.com");
  }
}

function mtnEnvironnement(): string {
  return process.env.MTN_ENVIRONNEMENT?.trim() || "sandbox";
}

function chaine(valeur: unknown): string | null {
  if (typeof valeur === "string" && valeur.length > 0) return valeur;
  if (typeof valeur === "number") return String(valeur);
  return null;
}

function nombre(valeur: unknown): number {
  if (typeof valeur === "number") return valeur;
  if (typeof valeur === "string") {
    const n = Number(valeur);
    return Number.isFinite(n) ? n : NaN;
  }
  return NaN;
}

function mtnRequest(
  method: "GET" | "POST",
  path: string,
  headers: Record<string, string>,
  payload?: Record<string, string>,
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const data = payload ? JSON.stringify(payload) : undefined;
    const base = mtnBaseUrl();
    const requestFn = base.protocol === "http:" ? httpRequest : httpsRequest;
    const req = requestFn(
      {
        hostname: base.hostname,
        port: base.port ? Number(base.port) : undefined,
        path,
        method,
        timeout: 15000,
        headers: {
          "Content-Type": "application/json",
          ...(data
            ? { "Content-Length": Buffer.byteLength(data).toString() }
            : {}),
          ...headers,
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
      req.destroy(new Error("Délai dépassé (MTN)."));
    });
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

/**
 * Extrait les champs utiles d'un callback MTN. Le corps porte
 * externalId, referenceId (ou reference_id), status et
 * financialTransactionId ; le montant et la devise sont parfois
 * absents du callback — la re-interrogation les fournit. Retourne null
 * si le corps n'est pas un objet JSON exploitable.
 */
export function analyserCallbackMtn(body: unknown): CallbackMtn | null {
  if (typeof body !== "object" || body === null) return null;
  const b = body as Record<string, unknown>;
  const statut = chaine(b.status ?? b.statut);
  if (!statut) return null;
  const payeur = b.payer;
  return {
    referenceId: chaine(b.referenceId ?? b.reference_id ?? b.reference),
    externalId: chaine(b.externalId ?? b.external_id),
    statut,
    financialTransactionId: chaine(
      b.financialTransactionId ?? b.financial_transaction_id,
    ),
    montant: nombre(b.amount ?? b.montant),
    devise: chaine(b.currency ?? b.devise) ?? "",
    payeur:
      typeof payeur === "object" && payeur !== null
        ? chaine((payeur as Record<string, unknown>).partyId)
        : chaine(payeur),
  };
}

/** Vrai si le statut MTN (re-interrogé) signifie un paiement réussi. */
export function estSuccesMtn(statut: string): boolean {
  return statut.toUpperCase() === "SUCCESSFUL";
}

/** Jeton d'accès MTN (POST /collection/token/, Basic api_user:api_key). */
export async function obtenirJetonMtn(
  identifiants: IdentifiantsMtn,
): Promise<string> {
  const basic = Buffer.from(
    `${identifiants.apiUser}:${identifiants.apiKey}`,
    "utf8",
  ).toString("base64");
  const { status, body } = await mtnRequest("POST", "/collection/token/", {
    Authorization: `Basic ${basic}`,
    "Ocp-Apim-Subscription-Key": identifiants.subscriptionKey,
  });
  if (status < 200 || status >= 300) {
    throw new Error(`MTN a refusé le jeton d'accès (HTTP ${status}).`);
  }
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(body) as Record<string, unknown>;
  } catch {
    throw new Error("Réponse MTN inexploitable (jeton).");
  }
  if (typeof parsed.access_token !== "string" || parsed.access_token === "") {
    throw new Error("Réponse MTN inexploitable (jeton absent).");
  }
  return parsed.access_token;
}

/**
 * Re-interroge le statut d'une transaction MTN
 * (GET /collection/v1_0/requesttopay/{referenceId}). Retourne null si
 * la référence est inconnue (404) ; lève une erreur sur tout autre
 * échec (l'appelant marque alors l'événement 'a_verifier').
 */
export async function interrogerStatutMtn(
  identifiants: IdentifiantsMtn,
  referenceId: string,
): Promise<StatutMtn | null> {
  const jeton = await obtenirJetonMtn(identifiants);
  const { status, body } = await mtnRequest(
    "GET",
    `/collection/v1_0/requesttopay/${encodeURIComponent(referenceId)}`,
    {
      Authorization: `Bearer ${jeton}`,
      "Ocp-Apim-Subscription-Key": identifiants.subscriptionKey,
      "X-Target-Environment": mtnEnvironnement(),
    },
  );
  if (status === 404) return null;
  if (status < 200 || status >= 300) {
    throw new Error(`MTN a refusé la re-interrogation (HTTP ${status}).`);
  }
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(body) as Record<string, unknown>;
  } catch {
    throw new Error("Réponse MTN inexploitable (statut).");
  }
  if (typeof parsed.status !== "string") {
    throw new Error("Réponse MTN inexploitable (statut absent).");
  }
  return {
    status: parsed.status,
    amount: nombre(parsed.amount),
    currency: chaine(parsed.currency) ?? "",
    financialTransactionId: chaine(parsed.financialTransactionId),
  };
}
