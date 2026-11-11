import type { FastifyInstance, FastifyReply } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { invalidInput, WRITE_ADMIN, WRITE_FINANCES, READ_ALL } from "../crud.js";
import {
  decryptSecret,
  encryptSecret,
  maskSecret,
} from "../paiements_crypto.js";
import {
  createWaveCheckoutSession,
  testWaveConnection,
} from "../paiements_wave.js";

/**
 * Paiements par pays et clés API de chaque église (module 14).
 *
 * - Catalogue de fournisseurs par pays (Wave, Orange, MTN, M-Pesa,
 *   PayPal, Stripe, virement, espèces) — extensible.
 * - Chaque église configure ses propres moyens dans « Mon église →
 *   Paiements » ; ses identifiants sont chiffrés en base (AES-256-GCM)
 *   et ne sont JAMAIS renvoyés par l'API (lecture masquée seulement).
 * - Exécution côté serveur uniquement : le serveur déchiffre en
 *   mémoire au moment du paiement, appelle le fournisseur, puis
 *   oublie. L'appli mobile ne voit jamais les clés.
 * - MVP : exécution et test branchés pour Wave ; les autres
 *   fournisseurs sont configurables, exécution à brancher (501).
 *
 * GET    /paiements/fournisseurs?pays=XX — catalogue par pays.
 * GET    /eglises/:id/paiements — configuration masquée de mon église.
 * POST   /eglises/:id/paiements — saisir / mettre à jour (admin).
 * DELETE /eglises/:id/paiements/:fournisseur — retirer un moyen (admin).
 * POST   /eglises/:id/paiements/:fournisseur/tester — test (admin).
 * POST   /paiements/executer — lancer un paiement (admin, trésorier).
 */

// -- Types et aides -----------------------------------------------------------

interface ChampRequis {
  nom: string;
  label: string;
  secret: boolean;
}

function parseChamps(value: unknown): ChampRequis[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter(
      (c): c is Record<string, unknown> =>
        typeof c === "object" && c !== null && typeof c.nom === "string",
    )
    .map((c) => ({
      nom: c.nom as string,
      label: typeof c.label === "string" ? c.label : (c.nom as string),
      secret: c.secret === true,
    }));
}

function parseStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === "string");
}

interface FournisseurRow {
  id: string;
  code: string;
  nom: string;
  pays: string[];
  type: string;
  champs_requis: unknown;
}

interface ConfigRow {
  id: string;
  fournisseur_id: string;
  fournisseur_code: string;
  fournisseur_nom: string;
  type: string;
  champs_requis: unknown;
  pays: string;
  libelle: string | null;
  apercu: string | null;
  actif: boolean;
  champs_configures: unknown;
}

interface SecretRow {
  nom_champ: string;
  valeur_chiffree: string;
  iv: string;
  tag: string;
}

function configPublique(row: ConfigRow): Record<string, unknown> {
  const champs = parseChamps(row.champs_requis);
  const configures = new Set(parseStringArray(row.champs_configures));
  return {
    id: row.id,
    fournisseur_code: row.fournisseur_code,
    fournisseur_nom: row.fournisseur_nom,
    type: row.type,
    pays: row.pays,
    libelle: row.libelle,
    apercu: row.apercu,
    actif: row.actif,
    champs: champs.map((c) => ({
      nom: c.nom,
      label: c.label,
      secret: c.secret,
      configure: configures.has(c.nom),
    })),
  };
}

/** Vrai si l'église du chemin est bien celle de la session. */
function isOwnChurch(reply: FastifyReply, paramId: string, sessionChurchId: string): boolean {
  if (paramId !== sessionChurchId) {
    reply.code(403).send({
      error: "forbidden",
      message: "On ne gère les paiements que de sa propre église.",
    });
    return false;
  }
  return true;
}

function cryptoConfigError(reply: FastifyReply, e: unknown): boolean {
  if (
    e instanceof Error &&
    e.message.startsWith("PAYMENT_SECRETS_KEY")
  ) {
    reply.code(500).send({
      error: "server_misconfigured",
      message:
        "Chiffrement des secrets non configuré sur le serveur (PAYMENT_SECRETS_KEY).",
    });
    return true;
  }
  return false;
}

async function loadConfig(
  db: Pool,
  churchId: string,
  fournisseurCode: string,
): Promise<{ config: ConfigRow; fournisseur: FournisseurRow } | null> {
  const { rows } = await db.query<ConfigRow>(
    `SELECT ep.id, ep.fournisseur_id, f.code AS fournisseur_code,
            f.nom AS fournisseur_nom, f.type, f.champs_requis,
            ep.pays, ep.libelle, ep.apercu, ep.actif,
            COALESCE(
              (SELECT json_agg(s.nom_champ)
                 FROM eglise_paiement_secrets s
                WHERE s.eglise_paiement_id = ep.id),
              '[]'::json) AS champs_configures
       FROM eglise_paiements ep
       JOIN fournisseurs_paiement f ON f.id = ep.fournisseur_id
      WHERE ep.church_id = $1 AND f.code = $2`,
    [churchId, fournisseurCode],
  );
  if (rows.length === 0) return null;
  const config = rows[0];
  const { rows: fRows } = await db.query<FournisseurRow>(
    `SELECT id, code, nom, pays, type, champs_requis
       FROM fournisseurs_paiement WHERE id = $1`,
    [config.fournisseur_id],
  );
  if (fRows.length === 0) return null;
  return { config, fournisseur: fRows[0] };
}

async function loadSecrets(
  db: Pool,
  configId: string,
): Promise<Map<string, SecretRow>> {
  const { rows } = await db.query<SecretRow>(
    `SELECT nom_champ, valeur_chiffree, iv, tag
       FROM eglise_paiement_secrets WHERE eglise_paiement_id = $1`,
    [configId],
  );
  return new Map(rows.map((r) => [r.nom_champ, r]));
}

// -- Schémas -----------------------------------------------------------------

const catalogueQuerySchema = z.object({
  pays: z.string().max(10).optional(),
});

const upsertSchema = z.object({
  fournisseur_code: z.string().min(1).max(50),
  pays: z.string().regex(/^[A-Z]{2}$/).or(z.literal("INTL")),
  libelle: z.string().max(120).optional(),
  actif: z.boolean().optional(),
  secrets: z
    .array(
      z.object({
        nom_champ: z.string().min(1).max(80),
        valeur: z.string().min(1).max(1000),
      }),
    )
    .max(20)
    .default([]),
});

const executerSchema = z.object({
  fournisseur_code: z.string().min(1).max(50),
  type: z.enum(["dime", "offrande", "don"]),
  montant: z.number().int().positive().max(100_000_000),
  devise: z.string().regex(/^[A-Z]{3}$/).default("XOF"),
  member_id: z.string().uuid().optional(),
  success_url: z.string().url().max(500),
  error_url: z.string().url().max(500),
  note: z.string().max(500).optional(),
});

/** Fournisseurs dont l'exécution est branchée dans le MVP. */
const EXECUTABLE: Record<string, "wave" | "manuel"> = {
  wave: "wave",
  virement: "manuel",
  especes: "manuel",
};

export function registerPaiementsRoutes(app: FastifyInstance, db: Pool): void {
  // -- Catalogue des fournisseurs, par pays ---------------------------------
  app.get(
    "/paiements/fournisseurs",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = catalogueQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const pays = parsed.data.pays;
      try {
        const { rows } = await db.query<FournisseurRow>(
          `SELECT id, code, nom, pays, type, champs_requis
             FROM fournisseurs_paiement
            WHERE actif = TRUE
              AND ($1::text IS NULL OR $1 = ANY(pays) OR '*' = ANY(pays))
            ORDER BY nom`,
          [pays ?? null],
        );
        return reply.send({
          total: rows.length,
          items: rows.map((f) => ({
            code: f.code,
            nom: f.nom,
            pays: f.pays,
            type: f.type,
            champs_requis: parseChamps(f.champs_requis),
          })),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Configuration masquée de mon église ------------------------------------
  app.get(
    "/eglises/:id/paiements",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const churchId = (req.params as { id: string }).id;
      if (!isOwnChurch(reply, churchId, req.session.churchId)) return;
      try {
        const { rows } = await db.query<ConfigRow>(
          `SELECT ep.id, ep.fournisseur_id, f.code AS fournisseur_code,
                  f.nom AS fournisseur_nom, f.type, f.champs_requis,
                  ep.pays, ep.libelle, ep.apercu, ep.actif,
                  COALESCE(
                    (SELECT json_agg(s.nom_champ)
                       FROM eglise_paiement_secrets s
                      WHERE s.eglise_paiement_id = ep.id),
                    '[]'::json) AS champs_configures
             FROM eglise_paiements ep
             JOIN fournisseurs_paiement f ON f.id = ep.fournisseur_id
            WHERE ep.church_id = $1
            ORDER BY f.nom`,
          [churchId],
        );
        return reply.send({
          total: rows.length,
          items: rows.map(configPublique),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Saisie / mise à jour d'un moyen de paiement (admin) ---------------------
  app.post(
    "/eglises/:id/paiements",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ADMIN)] },
    async (req, reply) => {
      const churchId = (req.params as { id: string }).id;
      if (!isOwnChurch(reply, churchId, req.session.churchId)) return;
      const parsed = upsertSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      try {
        const { rows: fRows } = await db.query<FournisseurRow>(
          `SELECT id, code, nom, pays, type, champs_requis
             FROM fournisseurs_paiement WHERE code = $1 AND actif = TRUE`,
          [data.fournisseur_code],
        );
        if (fRows.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Fournisseur inconnu ou inactif.",
          });
        }
        const fournisseur = fRows[0];
        if (!fournisseur.pays.includes(data.pays) && !fournisseur.pays.includes("*")) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Ce fournisseur n'est pas disponible pour ce pays.",
          });
        }
        const champs = parseChamps(fournisseur.champs_requis);
        const nomsConnus = new Set(champs.map((c) => c.nom));
        for (const s of data.secrets) {
          if (!nomsConnus.has(s.nom_champ)) {
            return reply.code(400).send({
              error: "invalid_input",
              message: `Champ inconnu pour ce fournisseur : ${s.nom_champ}.`,
            });
          }
        }
        const existant = await loadConfig(db, churchId, data.fournisseur_code);
        if (!existant) {
          const manquants = champs
            .filter((c) => !data.secrets.some((s) => s.nom_champ === c.nom))
            .map((c) => c.label);
          if (manquants.length > 0) {
            return reply.code(400).send({
              error: "invalid_input",
              message: `Champs obligatoires manquants : ${manquants.join(", ")}.`,
            });
          }
        }
        // Chiffrement AVANT toute écriture (clé manquante → 500 explicite).
        const chiffres = data.secrets.map((s) => ({
          nom_champ: s.nom_champ,
          enc: encryptSecret(s.valeur),
          valeur: s.valeur,
        }));
        const apercu =
          chiffres.length > 0 ? maskSecret(chiffres[0].valeur) : undefined;

        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows } = await client.query<{ id: string; apercu: string | null }>(
            `INSERT INTO eglise_paiements
               (church_id, fournisseur_id, pays, libelle, apercu, actif)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (church_id, fournisseur_id) DO UPDATE SET
               pays = EXCLUDED.pays,
               libelle = COALESCE(EXCLUDED.libelle, eglise_paiements.libelle),
               apercu = COALESCE(EXCLUDED.apercu, eglise_paiements.apercu),
               actif = EXCLUDED.actif,
               updated_at = now()
             RETURNING id, apercu`,
            [
              churchId,
              fournisseur.id,
              data.pays,
              data.libelle ?? null,
              apercu ?? null,
              data.actif ?? true,
            ],
          );
          const configId = rows[0].id;
          for (const c of chiffres) {
            await client.query(
              `INSERT INTO eglise_paiement_secrets
                 (eglise_paiement_id, nom_champ, valeur_chiffree, iv, tag, empreinte)
               VALUES ($1, $2, $3, $4, $5, $6)
               ON CONFLICT (eglise_paiement_id, nom_champ) DO UPDATE SET
                 valeur_chiffree = EXCLUDED.valeur_chiffree,
                 iv = EXCLUDED.iv,
                 tag = EXCLUDED.tag,
                 empreinte = EXCLUDED.empreinte,
                 updated_at = now()`,
              [
                configId,
                c.nom_champ,
                c.enc.valeur_chiffree,
                c.enc.iv,
                c.enc.tag,
                c.enc.empreinte,
              ],
            );
          }
          await client.query("COMMIT");
        } catch (e) {
          await client.query("ROLLBACK");
          throw e;
        } finally {
          client.release();
        }
        await auditLog(db, {
          churchId,
          userId: req.session.userId,
          action: "paiement.configure",
          details: { fournisseur_code: data.fournisseur_code, pays: data.pays },
        });
        const apres = await loadConfig(db, churchId, data.fournisseur_code);
        return reply.code(201).send(apres ? configPublique(apres.config) : { ok: true });
      } catch (e) {
        if (cryptoConfigError(reply, e)) return;
        return dbError(reply, e);
      }
    },
  );

  // -- Retrait d'un moyen de paiement (admin) ----------------------------------
  app.delete(
    "/eglises/:id/paiements/:fournisseur",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ADMIN)] },
    async (req, reply) => {
      const churchId = (req.params as { id: string }).id;
      const code = (req.params as { fournisseur: string }).fournisseur;
      if (!isOwnChurch(reply, churchId, req.session.churchId)) return;
      try {
        const { rows } = await db.query<{ id: string }>(
          `DELETE FROM eglise_paiements ep USING fournisseurs_paiement f
            WHERE ep.fournisseur_id = f.id
              AND ep.church_id = $1 AND f.code = $2
            RETURNING ep.id`,
          [churchId, code],
        );
        if (rows.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Ce moyen de paiement n'est pas configuré.",
          });
        }
        await auditLog(db, {
          churchId,
          userId: req.session.userId,
          action: "paiement.supprime",
          details: { fournisseur_code: code },
        });
        return reply.send({ ok: true, id: rows[0].id });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Test de connexion d'un moyen configuré (admin) ---------------------------
  app.post(
    "/eglises/:id/paiements/:fournisseur/tester",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ADMIN)] },
    async (req, reply) => {
      const churchId = (req.params as { id: string }).id;
      const code = (req.params as { fournisseur: string }).fournisseur;
      if (!isOwnChurch(reply, churchId, req.session.churchId)) return;
      try {
        const found = await loadConfig(db, churchId, code);
        if (!found) {
          return reply.code(404).send({
            error: "not_found",
            message: "Ce moyen de paiement n'est pas configuré.",
          });
        }
        if (code !== "wave") {
          return reply.code(501).send({
            error: "not_implemented",
            message:
              "Le test de connexion n'est disponible que pour Wave dans le MVP.",
          });
        }
        const secrets = await loadSecrets(db, found.config.id);
        const apiKeyRow = secrets.get("api_key");
        if (!apiKeyRow) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Clé API Wave non configurée pour cette église.",
          });
        }
        const apiKey = decryptSecret(apiKeyRow);
        const result = await testWaveConnection(apiKey);
        await auditLog(db, {
          churchId,
          userId: req.session.userId,
          action: "paiement.teste",
          details: { fournisseur_code: code, ok: result.ok },
        });
        return reply.send(result);
      } catch (e) {
        if (cryptoConfigError(reply, e)) return;
        return dbError(reply, e);
      }
    },
  );

  // -- Exécution d'un paiement (serveur uniquement) -----------------------------
  app.post(
    "/paiements/executer",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const churchId = req.session.churchId;
      const parsed = executerSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      try {
        const found = await loadConfig(db, churchId, data.fournisseur_code);
        if (!found || !found.config.actif) {
          return reply.code(404).send({
            error: "not_configured",
            message:
              "Ce moyen de paiement n'est pas configuré pour votre église.",
          });
        }
        if (data.member_id) {
          const member = await db.query(
            `SELECT id FROM members WHERE id = $1 AND church_id = $2`,
            [data.member_id, churchId],
          );
          if (member.rowCount === 0) {
            return reply.code(400).send({
              error: "invalid_reference",
              message: "Ce membre n'appartient pas à votre église.",
            });
          }
        }
        const mode = EXECUTABLE[data.fournisseur_code];
        if (!mode) {
          return reply.code(501).send({
            error: "not_implemented",
            message:
              "L'exécution pour ce fournisseur n'est pas encore branchée (MVP : Wave, virement, espèces).",
          });
        }
        let paymentRef: string | null = null;
        let launchUrl: string | null = null;
        if (mode === "wave") {
          const secrets = await loadSecrets(db, found.config.id);
          const apiKeyRow = secrets.get("api_key");
          if (!apiKeyRow) {
            return reply.code(400).send({
              error: "invalid_input",
              message: "Clé API Wave non configurée pour cette église.",
            });
          }
          const apiKey = decryptSecret(apiKeyRow);
          try {
            const session = await createWaveCheckoutSession(apiKey, {
              amount: data.montant,
              currency: data.devise,
              successUrl: data.success_url,
              errorUrl: data.error_url,
            });
            paymentRef = session.sessionId;
            launchUrl = session.launchUrl;
          } catch (e) {
            return reply.code(502).send({
              error: "provider_error",
              message: (e as Error).message,
            });
          }
        }
        const { rows } = await db.query(
          `INSERT INTO contributions
             (church_id, member_id, type, amount_fcfa, payment_method,
              payment_ref, status, received_by, note)
           VALUES ($1, $2, $3, $4, $5, $6, 'en_attente', $7, $8)
           RETURNING id, church_id, member_id, type, amount_fcfa,
                     payment_method, payment_ref, status, note, created_at`,
          [
            churchId,
            data.member_id ?? null,
            data.type,
            data.montant,
            data.fournisseur_code,
            paymentRef,
            req.session.userId,
            data.note ?? null,
          ],
        );
        await auditLog(db, {
          churchId,
          userId: req.session.userId,
          action: "paiement.execute",
          details: {
            fournisseur_code: data.fournisseur_code,
            type: data.type,
            montant: data.montant,
          },
        });
        return reply.code(201).send({
          contribution: rows[0],
          ...(launchUrl ? { session_id: paymentRef, launch_url: launchUrl } : {}),
        });
      } catch (e) {
        if (cryptoConfigError(reply, e)) return;
        return dbError(reply, e);
      }
    },
  );
}
