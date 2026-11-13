import { createHash } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool, PoolClient } from "pg";
import { auditLog } from "../auth.js";
import { dbError } from "../middleware.js";
import { decryptSecret } from "../paiements_crypto.js";
import {
  getWaveCheckoutSession,
  verifierSignatureWebhookWave,
} from "../paiements_wave.js";
import {
  analyserNotificationOrange,
  estEchecOrange,
  estSuccesOrange,
} from "../paiements_orange.js";
import {
  analyserCallbackMtn,
  estSuccesMtn,
  interrogerStatutMtn,
  type IdentifiantsMtn,
} from "../paiements_mtn.js";
import { confirmerContribution } from "./contributions.js";
import {
  chargerConfigPaiement,
  chargerSecretsPaiement,
} from "./paiements.js";

/**
 * Webhooks de paiement — confirmation automatique des contributions
 * (tranche T8, Lot B, 13 novembre 2026).
 *
 * Routes PUBLIQUES (aucune session) : la sécurité vient de la
 * vérification propre à chaque fournisseur, jamais d'un jeton de
 * session — un membre ne peut donc pas « appeler le webhook comme une
 * route authentifiée », et un appel sans signature valide est rejeté
 * (401) avant toute lecture ou écriture.
 *
 * POST /webhooks/wave   — Wave (signature HMAC, re-interrogation).
 * POST /webhooks/orange — Orange Money (statut + montant, voir
 *                          paiements_orange.ts pour les limites).
 * POST /webhooks/mtn    — MTN MoMo (re-interrogation obligatoire,
 *                          le callback n'est pas signé) ; PUT accepté
 *                          aussi (le sens de la méthode varie selon
 *                          les versions de la documentation MTN).
 *
 * Principes (les mêmes pour les trois fournisseurs) :
 *  1. La contribution est résolue par sa payment_ref (référence
 *     enregistrée à l'exécution : id de session Wave, order_id
 *     Orange, X-Reference-Id MTN) et par le fournisseur.
 *  2. La configuration marchande de L'ÉGLISE de la contribution est
 *     chargée (chaque antenne garde son propre compte marchand) ;
 *     sans configuration active, l'événement est ignoré.
 *  3. L'événement est journalisé dans evenements_paiement
 *     (migration 026) — jamais la charge utile brute, jamais une
 *     signature : seulement l'identifiant, la référence, le montant,
 *     la devise et l'empreinte SHA-256 du corps brut.
 *  4. Idempotence : (fournisseur, evenement_id) est unique ; un
 *     événement déjà 'confirme' est renvoyé tel quel (deja_traite)
 *     sans aucun effet. La confirmation elle-même ne s'applique qu'à
 *     une contribution encore 'en_attente', verrouillée FOR UPDATE —
 *     une contribution déjà confirmée ne produit jamais de double
 *     effet (ni double reçu, ni double écriture en caisse).
 *  5. Une confirmation par webhook a les MÊMES effets qu'une
 *     confirmation manuelle (confirmerContribution, tranche T7) :
 *     reçu numéroté REC-AAAA-NNNN, écriture automatique en caisse,
 *     verrouillage. Seule différence : valide_par est NULL (aucun
 *     humain ne valide) et l'action d'audit est
 *     `contribution.confirmee_webhook`.
 *  6. Réponses : 200 pour toute notification bien formée (même
 *     ignorée — un code d'erreur déclencherait des renvois) ; 401
 *     pour une signature invalide ; 400 pour un corps inexploitable ;
 *     500 quand la re-interrogation du fournisseur échoue (cas
 *     rejouable : le fournisseur renverra la notification).
 */

type FournisseurWebhook = "wave" | "orange_money" | "mtn_momo";

type StatutEvenement = "recu" | "confirme" | "ignore" | "rejete" | "a_verifier";

interface ContributionWebhookRow {
  id: string;
  church_id: string;
  type: string;
  amount_fcfa: number;
  status: string;
  payment_method: string;
  payment_ref: string | null;
}

/** Corps brut tel que reçu (pour la signature et l'empreinte). */
function corpsBrut(req: FastifyRequest): string {
  if (typeof req.rawBody === "string") return req.rawBody;
  return JSON.stringify(req.body ?? {});
}

function empreinteCorps(corps: string): string {
  return createHash("sha256").update(corps, "utf8").digest("hex");
}

/** Résout la contribution par sa référence de paiement (la plus récente). */
async function resoudreContribution(
  db: Pool,
  paymentRef: string,
  paymentMethod: FournisseurWebhook,
): Promise<ContributionWebhookRow | null> {
  const { rows } = await db.query<ContributionWebhookRow>(
    `SELECT id, church_id, type, amount_fcfa, status, payment_method, payment_ref
       FROM contributions
      WHERE payment_ref = $1 AND payment_method = $2
      ORDER BY created_at DESC LIMIT 1`,
    [paymentRef, paymentMethod],
  );
  return rows[0] ?? null;
}

/** Charge et déchiffre les secrets d'une configuration (en mémoire). */
async function chargerSecretsClairs(
  db: Pool,
  configId: string,
): Promise<Map<string, string>> {
  const chiffres = await chargerSecretsPaiement(db, configId);
  const clairs = new Map<string, string>();
  for (const [nom, secret] of chiffres) {
    clairs.set(nom, decryptSecret(secret));
  }
  return clairs;
}

interface EvenementAEnregistrer {
  churchId: string | null;
  fournisseur: FournisseurWebhook;
  evenementId: string;
  contributionId: string | null;
  statut: StatutEvenement;
  montantFcfa: number | null;
  devise: string | null;
  referenceExterne: string | null;
  payloadHash: string;
}

/**
 * Insère un événement avec son statut final (hors confirmation : pas
 * de transaction nécessaire, l'insertion est atomique). En cas de
 * conflit sur (fournisseur, evenement_id), renvoie la ligne existante.
 */
async function enregistrerEvenement(
  db: Pool,
  ev: EvenementAEnregistrer,
): Promise<{ id: string; statut: StatutEvenement; nouveau: boolean }> {
  const { rows } = await db.query<{ id: string; statut: StatutEvenement }>(
    `INSERT INTO evenements_paiement
       (church_id, fournisseur, evenement_id, contribution_id, statut,
        montant_fcfa, devise, reference_externe, payload_hash, traite_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
     ON CONFLICT (fournisseur, evenement_id) DO NOTHING
     RETURNING id, statut`,
    [
      ev.churchId,
      ev.fournisseur,
      ev.evenementId,
      ev.contributionId,
      ev.statut,
      ev.montantFcfa,
      ev.devise,
      ev.referenceExterne,
      ev.payloadHash,
    ],
  );
  if (rows.length > 0) {
    return { id: rows[0].id, statut: rows[0].statut, nouveau: true };
  }
  const existants = await db.query<{ id: string; statut: StatutEvenement }>(
    `SELECT id, statut FROM evenements_paiement
      WHERE fournisseur = $1 AND evenement_id = $2`,
    [ev.fournisseur, ev.evenementId],
  );
  return {
    id: existants.rows[0].id,
    statut: existants.rows[0].statut,
    nouveau: false,
  };
}

/** Montant et devise d'une notification comparés à la contribution (FCFA). */
function verifierMontant(
  montantNotif: number,
  deviseNotif: string,
  contribution: ContributionWebhookRow,
): "ok" | "montant_incoherent" | "montant_absent" {
  // Les contributions sont en FCFA (amount_fcfa) ; les trois
  // fournisseurs opèrent en XOF en Côte d'Ivoire et au Sénégal.
  if (deviseNotif !== "" && deviseNotif !== "XOF") return "montant_incoherent";
  if (!Number.isFinite(montantNotif)) return "montant_absent";
  if (montantNotif !== contribution.amount_fcfa) return "montant_incoherent";
  return "ok";
}

/**
 * Chemin de confirmation, en UNE transaction : l'événement est inséré
 * ('recu'), la contribution est confirmée (confirmerContribution —
 * garde en_attente + FOR UPDATE), l'événement passe à 'confirme' et
 * l'audit est écrit. Un événement déjà 'confirme' (renvoi du
 * fournisseur) est renvoyé tel quel, sans effet.
 */
async function confirmerParWebhook(
  db: Pool,
  ev: EvenementAEnregistrer,
  contribution: ContributionWebhookRow,
  fournisseur: FournisseurWebhook,
): Promise<
  | { traite: "confirme"; recuNumero: string; dejaTraite: false }
  | { traite: "deja_traite"; recuNumero: null; dejaTraite: true }
  | { traite: "deja_confirme"; recuNumero: null; dejaTraite: true }
> {
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const { rows } = await client.query<{ id: string; statut: StatutEvenement }>(
      `INSERT INTO evenements_paiement
         (church_id, fournisseur, evenement_id, contribution_id, statut,
          montant_fcfa, devise, reference_externe, payload_hash)
       VALUES ($1, $2, $3, $4, 'recu', $5, $6, $7, $8)
       ON CONFLICT (fournisseur, evenement_id) DO NOTHING
       RETURNING id, statut`,
      [
        ev.churchId,
        ev.fournisseur,
        ev.evenementId,
        ev.contributionId,
        ev.montantFcfa,
        ev.devise,
        ev.referenceExterne,
        ev.payloadHash,
      ],
    );
    let evenementId = "";
    if (rows.length === 0) {
      const existants = await client.query<{ id: string; statut: StatutEvenement }>(
        `SELECT id, statut FROM evenements_paiement
          WHERE fournisseur = $1 AND evenement_id = $2`,
        [ev.fournisseur, ev.evenementId],
      );
      evenementId = existants.rows[0].id;
      if (existants.rows[0].statut === "confirme") {
        await client.query("COMMIT");
        return { traite: "deja_traite", recuNumero: null, dejaTraite: true };
      }
      // Renvoi d'un événement ignoré ou à vérifier : on le retraite
      // (la contribution a pu devenir confirmable entre-temps).
    } else {
      evenementId = rows[0].id;
    }
    const confirme = await confirmerContribution(client, contribution.church_id, contribution.id, {
      validePar: null,
      actionAudit: "contribution.confirmee_webhook",
    });
    if (!confirme.ok) {
      // La contribution n'est plus en_attente (déjà confirmée
      // manuellement, ou annulée) : rien à faire, l'événement est
      // marqué ignoré — sans double effet.
      await client.query(
        `UPDATE evenements_paiement SET statut = 'ignore', traite_at = now() WHERE id = $1`,
        [evenementId],
      );
      await client.query("COMMIT");
      return { traite: "deja_confirme", recuNumero: null, dejaTraite: true };
    }
    await client.query(
      `UPDATE evenements_paiement SET statut = 'confirme', traite_at = now() WHERE id = $1`,
      [evenementId],
    );
    await auditLog(client, {
      churchId: contribution.church_id,
      userId: null,
      action: `webhook.${fournisseur}.confirme`,
      details: {
        contribution_id: contribution.id,
        evenement_id: ev.evenementId,
        montant_fcfa: contribution.amount_fcfa,
        recu_numero: confirme.contribution.recu_numero,
      },
    });
    await client.query("COMMIT");
    return {
      traite: "confirme",
      recuNumero: confirme.contribution.recu_numero ?? "",
      dejaTraite: false,
    };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw e;
  } finally {
    client.release();
  }
}

/** Réponse 200 standard, avec le détail du traitement (sans secret). */
function reponseTraitee(
  reply: FastifyReply,
  traite: string,
  extra: Record<string, unknown> = {},
): void {
  reply.send({ recu: true, traite, ...extra });
}

export function registerWebhooksPaiementsRoutes(app: FastifyInstance, db: Pool): void {
  // -- Wave ------------------------------------------------------------------
  app.post("/webhooks/wave", async (req, reply) => {
    const brut = corpsBrut(req);
    const hash = empreinteCorps(brut);
    const body = req.body as Record<string, unknown> | null;
    const type = typeof body?.type === "string" ? body.type : "";
    const data =
      typeof body?.data === "object" && body.data !== null
        ? (body.data as Record<string, unknown>)
        : {};
    const sessionId =
      typeof data.id === "string"
        ? data.id
        : typeof data.checkout_session_id === "string"
          ? data.checkout_session_id
          : typeof data.session_id === "string"
            ? data.session_id
            : "";
    if (type !== "checkout.session.completed" || sessionId === "") {
      // Autre type d'événement Wave (ex. session expirée) ou corps
      // inexploitable : rien à confirmer, on accuse réception.
      return reponseTraitee(reply, "ignore", { raison: "evenement_non_concernant" });
    }
    const evenementId =
      typeof body?.id === "string" && body.id !== ""
        ? body.id
        : `checkout.session.completed:${sessionId}`;
    const contribution = await resoudreContribution(db, sessionId, "wave");
    if (!contribution) {
      await enregistrerEvenement(db, {
        churchId: null,
        fournisseur: "wave",
        evenementId,
        contributionId: null,
        statut: "ignore",
        montantFcfa: null,
        devise: null,
        referenceExterne: sessionId,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "reference_inconnue" });
    }
    const config = await chargerConfigPaiement(db, contribution.church_id, "wave");
    if (!config || !config.config.actif) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "wave",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: null,
        devise: null,
        referenceExterne: sessionId,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "fournisseur_non_configure" });
    }
    let secrets: Map<string, string>;
    try {
      secrets = await chargerSecretsClairs(db, config.config.id);
    } catch (e) {
      if (e instanceof Error && e.message.startsWith("PAYMENT_SECRETS_KEY")) {
        return reply.code(500).send({
          error: "server_misconfigured",
          message: "Chiffrement des secrets non configuré sur le serveur (PAYMENT_SECRETS_KEY).",
        });
      }
      throw e;
    }
    const webhookSecret = secrets.get("webhook_secret") ?? "";
    // Sans secret configuré, la signature ne peut pas être vérifiée :
    // on rejette (401) plutôt que de confirmer sur parole. Le rejet
    // n'est PAS journalisé dans evenements_paiement (il empoisonnerait
    // la déduplication d'un vrai événement ultérieur) — il l'est dans
    // audit_logs (sans la signature).
    if (webhookSecret === "") {
      await auditLog(db, {
        churchId: contribution.church_id,
        userId: null,
        action: "webhook.wave.signature_rejetee",
        details: { evenement_id: evenementId, raison: "secret_non_configure" },
      });
      return reply.code(401).send({
        error: "unauthorized",
        message: "Secret de signature du webhook Wave non configuré pour cette église.",
      });
    }
    if (!verifierSignatureWebhookWave(webhookSecret, req.headers["wave-signature"], brut)) {
      await auditLog(db, {
        churchId: contribution.church_id,
        userId: null,
        action: "webhook.wave.signature_rejetee",
        details: { evenement_id: evenementId, raison: "signature_invalide" },
      });
      return reply.code(401).send({
        error: "unauthorized",
        message: "Signature du webhook Wave invalide.",
      });
    }
    // La notification n'est pas crue sur parole : la session doit être
    // `complete` côté Wave. Une erreur de re-interrogation est rejouable
    // (500 — Wave renverra la notification) ; l'événement est marqué
    // 'a_verifier' pour le suivi manuel.
    const apiKey = secrets.get("api_key") ?? "";
    let session: Awaited<ReturnType<typeof getWaveCheckoutSession>>;
    try {
      session = await getWaveCheckoutSession(apiKey, sessionId);
    } catch (e) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "wave",
        evenementId,
        contributionId: contribution.id,
        statut: "a_verifier",
        montantFcfa: null,
        devise: null,
        referenceExterne: sessionId,
        payloadHash: hash,
      });
      return reply.code(500).send({
        error: "provider_unavailable",
        message: `Re-interrogation Wave impossible : ${(e as Error).message}`,
      });
    }
    if (!session || session.checkoutStatus !== "complete") {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "wave",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(session?.amount) ? session?.amount ?? null : null,
        devise: session?.currency ?? null,
        referenceExterne: sessionId,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "session_non_complete" });
    }
    const montant = verifierMontant(session.amount, session.currency, contribution);
    if (montant !== "ok") {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "wave",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(session.amount) ? session.amount : null,
        devise: session.currency || null,
        referenceExterne: sessionId,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: montant });
    }
    try {
      const resultat = await confirmerParWebhook(
        db,
        {
          churchId: contribution.church_id,
          fournisseur: "wave",
          evenementId,
          contributionId: contribution.id,
          statut: "recu",
          montantFcfa: contribution.amount_fcfa,
          devise: "XOF",
          referenceExterne: sessionId,
          payloadHash: hash,
        },
        contribution,
        "wave",
      );
      return reponseTraitee(reply, resultat.traite, {
        deja_traite: resultat.dejaTraite,
        ...(resultat.recuNumero ? { recu_numero: resultat.recuNumero } : {}),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Orange Money ------------------------------------------------------------
  app.post("/webhooks/orange", async (req, reply) => {
    const brut = corpsBrut(req);
    const hash = empreinteCorps(brut);
    const notif = analyserNotificationOrange(req.body);
    if (!notif) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Notification Orange inexploitable.",
      });
    }
    // Identifiant d'événement : l'identifiant de transaction Orange,
    // sinon la référence marchande (order_id).
    const evenementId = notif.transactionId ?? notif.orderId ?? "";
    const reference = notif.orderId ?? notif.transactionId ?? "";
    if (evenementId === "" || reference === "") {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Notification Orange sans référence exploitable.",
      });
    }
    const contribution = await resoudreContribution(db, reference, "orange_money");
    if (!contribution) {
      await enregistrerEvenement(db, {
        churchId: null,
        fournisseur: "orange_money",
        evenementId,
        contributionId: null,
        statut: "ignore",
        montantFcfa: Number.isFinite(notif.montant) ? notif.montant : null,
        devise: notif.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "reference_inconnue" });
    }
    const config = await chargerConfigPaiement(db, contribution.church_id, "orange_money");
    if (!config || !config.config.actif) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "orange_money",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(notif.montant) ? notif.montant : null,
        devise: notif.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "fournisseur_non_configure" });
    }
    if (estEchecOrange(notif.statut)) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "orange_money",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(notif.montant) ? notif.montant : null,
        devise: notif.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "paiement_echoue" });
    }
    if (!estSuccesOrange(notif.statut)) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "orange_money",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(notif.montant) ? notif.montant : null,
        devise: notif.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "statut_non_succes" });
    }
    const montant = verifierMontant(notif.montant, notif.devise, contribution);
    if (montant !== "ok") {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "orange_money",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(notif.montant) ? notif.montant : null,
        devise: notif.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: montant });
    }
    try {
      const resultat = await confirmerParWebhook(
        db,
        {
          churchId: contribution.church_id,
          fournisseur: "orange_money",
          evenementId,
          contributionId: contribution.id,
          statut: "recu",
          montantFcfa: contribution.amount_fcfa,
          devise: "XOF",
          referenceExterne: reference,
          payloadHash: hash,
        },
        contribution,
        "orange_money",
      );
      return reponseTraitee(reply, resultat.traite, {
        deja_traite: resultat.dejaTraite,
        ...(resultat.recuNumero ? { recu_numero: resultat.recuNumero } : {}),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- MTN MoMo ----------------------------------------------------------------
  const traiterMtn = async (req: FastifyRequest, reply: FastifyReply) => {
    const brut = corpsBrut(req);
    const hash = empreinteCorps(brut);
    const callback = analyserCallbackMtn(req.body);
    if (!callback) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Callback MTN inexploitable.",
      });
    }
    // Identifiant d'événement : la référence de transaction MTN
    // (X-Reference-Id), sinon la référence externe du marchand.
    const reference = callback.referenceId ?? callback.externalId ?? "";
    if (reference === "") {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Callback MTN sans référence exploitable.",
      });
    }
    const evenementId = reference;
    const contribution = await resoudreContribution(db, reference, "mtn_momo");
    if (!contribution) {
      await enregistrerEvenement(db, {
        churchId: null,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: null,
        statut: "ignore",
        montantFcfa: Number.isFinite(callback.montant) ? callback.montant : null,
        devise: callback.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "reference_inconnue" });
    }
    const config = await chargerConfigPaiement(db, contribution.church_id, "mtn_momo");
    if (!config || !config.config.actif) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(callback.montant) ? callback.montant : null,
        devise: callback.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "fournisseur_non_configure" });
    }
    let secrets: Map<string, string>;
    try {
      secrets = await chargerSecretsClairs(db, config.config.id);
    } catch (e) {
      if (e instanceof Error && e.message.startsWith("PAYMENT_SECRETS_KEY")) {
        return reply.code(500).send({
          error: "server_misconfigured",
          message: "Chiffrement des secrets non configuré sur le serveur (PAYMENT_SECRETS_KEY).",
        });
      }
      throw e;
    }
    const identifiants: IdentifiantsMtn = {
      subscriptionKey: secrets.get("subscription_key") ?? "",
      apiUser: secrets.get("api_user") ?? "",
      apiKey: secrets.get("api_key") ?? "",
    };
    if (!identifiants.subscriptionKey || !identifiants.apiUser || !identifiants.apiKey) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: contribution.id,
        statut: "a_verifier",
        montantFcfa: Number.isFinite(callback.montant) ? callback.montant : null,
        devise: callback.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "a_verifier", { raison: "identifiants_manquants" });
    }
    // MTN ne signe pas ses callbacks : on re-interroge systématiquement.
    // Le statut reçu est ignoré ; seul le statut re-interrogé compte.
    let statut: Awaited<ReturnType<typeof interrogerStatutMtn>>;
    try {
      statut = await interrogerStatutMtn(identifiants, reference);
    } catch (e) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: contribution.id,
        statut: "a_verifier",
        montantFcfa: Number.isFinite(callback.montant) ? callback.montant : null,
        devise: callback.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reply.code(500).send({
        error: "provider_unavailable",
        message: `Re-interrogation MTN impossible : ${(e as Error).message}`,
      });
    }
    if (!statut) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(callback.montant) ? callback.montant : null,
        devise: callback.devise || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "transaction_inconnue_mtn" });
    }
    if (statut.status.toUpperCase() === "PENDING") {
      // Paiement pas encore terminé côté MTN : à suivre manuellement
      // (le callback n'est envoyé qu'une fois, sans nouvelle tentative).
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: contribution.id,
        statut: "a_verifier",
        montantFcfa: Number.isFinite(statut.amount) ? statut.amount : null,
        devise: statut.currency || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "a_verifier", { raison: "paiement_en_cours" });
    }
    if (!estSuccesMtn(statut.status)) {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(statut.amount) ? statut.amount : null,
        devise: statut.currency || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: "paiement_echoue" });
    }
    const montant = verifierMontant(statut.amount, statut.currency, contribution);
    if (montant !== "ok") {
      await enregistrerEvenement(db, {
        churchId: contribution.church_id,
        fournisseur: "mtn_momo",
        evenementId,
        contributionId: contribution.id,
        statut: "ignore",
        montantFcfa: Number.isFinite(statut.amount) ? statut.amount : null,
        devise: statut.currency || null,
        referenceExterne: reference,
        payloadHash: hash,
      });
      return reponseTraitee(reply, "ignore", { raison: montant });
    }
    try {
      const resultat = await confirmerParWebhook(
        db,
        {
          churchId: contribution.church_id,
          fournisseur: "mtn_momo",
          evenementId,
          contributionId: contribution.id,
          statut: "recu",
          montantFcfa: contribution.amount_fcfa,
          devise: "XOF",
          referenceExterne: reference,
          payloadHash: hash,
        },
        contribution,
        "mtn_momo",
      );
      return reponseTraitee(reply, resultat.traite, {
        deja_traite: resultat.dejaTraite,
        ...(resultat.recuNumero ? { recu_numero: resultat.recuNumero } : {}),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  };
  app.post("/webhooks/mtn", traiterMtn);
  app.put("/webhooks/mtn", traiterMtn);
}
