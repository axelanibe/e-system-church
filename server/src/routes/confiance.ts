import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { createHash } from "node:crypto";
import { z } from "zod";
import { auditLog, logConsultationSensible, verifierChaineAudit } from "../auth.js";
import { ErreurMetier } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { decryptSecret, encryptSecret } from "../paiements_crypto.js";
import { genererSecretTOTP, uriTOTP, verifierCodeTOTP } from "../totp.js";
import { creerContribution } from "./contributions.js";
import { pointerPresence, pointerSchema } from "./presences.js";

/**
 * Tranche T11 — Socle de confiance.
 *
 * - 2FA TOTP (Pasteur = responsable_culte, Trésorier, Admin) : secret
 *   chiffré AES-256-GCM, code exigé à la connexion quand il est actif.
 * - Journal d'audit immuable à hash chaîné (lecture seule, vérifiable),
 *   lectures sensibles journalisées à part (US17).
 * - Sauvegarde chiffrée (toutes les tables à church_id) avec restauration
 *   testée, et sauvegarde automatique horaire (meilleur effort sur
 *   l'offre gratuite : le service s'endort, le déclenchement manuel
 *   reste toujours disponible).
 * - Notifications : boîte d'envoi configurable. AUCUN fournisseur n'est
 *   branché (choix d'Axel en attente) : tant qu'aucun adaptateur
 *   n'existe, l'envoi échoue proprement et rien ne part.
 * - File d'actions hors ligne (pointages et saisies) avec rejeu ordonné
 *   et idempotent (cle_client).
 * - RLS Postgres : politiques définies en migration 029, deuxième ligne
 *   de défense, sans effet tant que l'application se connecte avec le
 *   rôle propriétaire.
 */

const uuid = z.string().uuid();
const ADMIN = ["admin_eglise"];
const EQUIPE = ["admin_eglise", "tresorier", "responsable_culte"];
const ROLES_2FA = ["admin_eglise", "tresorier", "responsable_culte"];

const paginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

function nomTableValide(nom: string): boolean {
  return /^[a-z_][a-z0-9_]*$/.test(nom);
}

// -- Paramètres de confiance (eglise_parametres) -----------------------------

async function assurerParametres(db: Pool, churchId: string): Promise<void> {
  await db.query(
    `INSERT INTO eglise_parametres (church_id) VALUES ($1)
     ON CONFLICT (church_id) DO NOTHING`,
    [churchId],
  );
}

interface ParametresConfiance {
  sauvegarde_frequence: string;
  sauvegarde_heure: string;
  sauvegarde_auto_derniere_at: string | null;
  notification_fournisseur: string | null;
  notification_plafond_mensuel: number;
  notifications_actives: boolean;
  notifications_configurees: boolean;
}

async function lireParametres(db: Pool, churchId: string): Promise<ParametresConfiance> {
  await assurerParametres(db, churchId);
  const { rows } = await db.query(
    `SELECT sauvegarde_frequence, sauvegarde_heure, sauvegarde_auto_derniere_at,
            notification_fournisseur, notification_plafond_mensuel, notifications_actives
       FROM eglise_parametres WHERE church_id = $1`,
    [churchId],
  );
  const r = rows[0];
  return {
    sauvegarde_frequence: r.sauvegarde_frequence as string,
    sauvegarde_heure: r.sauvegarde_heure as string,
    sauvegarde_auto_derniere_at: r.sauvegarde_auto_derniere_at
      ? (r.sauvegarde_auto_derniere_at as Date).toISOString()
      : null,
    notification_fournisseur: r.notification_fournisseur as string | null,
    notification_plafond_mensuel: r.notification_plafond_mensuel as number,
    notifications_actives: r.notifications_actives as boolean,
    notifications_configurees: r.notification_fournisseur !== null,
  };
}

// -- Sauvegarde : export et restauration -------------------------------------

async function listerTablesEglise(client: Pool | PoolClient): Promise<string[]> {
  // Seulement les vraies tables (BASE TABLE) : information_schema.columns
  // liste aussi les vues (v_radar_absences…), qu'on ne peut pas supprimer.
  // audit_logs est exclu : journal immuable, il ne se restaure pas
  // (le déclencheur refuse DELETE, et réécrire l'historique casserait
  // la chaîne) ; il reste consultable, la sauvegarde archive le reste.
  const { rows } = await client.query<{ table_name: string }>(
    `SELECT c.table_name FROM information_schema.columns c
      JOIN information_schema.tables t
        ON t.table_schema = c.table_schema AND t.table_name = c.table_name
      WHERE c.table_schema = 'public' AND c.column_name = 'church_id'
        AND t.table_type = 'BASE TABLE'
        AND c.table_name NOT IN ('sauvegardes', 'audit_logs')
      ORDER BY c.table_name`,
  );
  return rows.map((r) => r.table_name).filter(nomTableValide);
}

/** Ordre topologique des tables (parents avant enfants), par les clés étrangères. */
async function ordreTables(client: Pool | PoolClient, tables: string[]): Promise<string[]> {
  const ensemble = new Set(tables);
  const { rows } = await client.query<{ table_name: string; referenced: string }>(
    `SELECT tc.table_name, ccu.table_name AS referenced
       FROM information_schema.table_constraints tc
       JOIN information_schema.key_column_usage kcu
         ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
       JOIN information_schema.constraint_column_usage ccu
         ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public'`,
  );
  const dependances = new Map<string, Set<string>>();
  for (const table of tables) dependances.set(table, new Set());
  for (const ligne of rows) {
    if (ensemble.has(ligne.table_name) && ensemble.has(ligne.referenced) && ligne.table_name !== ligne.referenced) {
      dependances.get(ligne.table_name)?.add(ligne.referenced);
    }
  }
  const ordre: string[] = [];
  const restantes = new Set(tables);
  while (restantes.size > 0) {
    const pretes = [...restantes].filter((t) => [...(dependances.get(t) ?? [])].every((d) => !restantes.has(d))).sort();
    if (pretes.length === 0) {
      // Cycle résiduel (référence circulaire) : on prend le reste par
      // ordre alphabétique, l'insertion lèvera une erreur claire.
      ordre.push(...[...restantes].sort());
      break;
    }
    for (const table of pretes) {
      ordre.push(table);
      restantes.delete(table);
    }
  }
  return ordre;
}

async function insererLigne(client: PoolClient, table: string, ligne: Record<string, unknown>): Promise<void> {
  const colonnes = Object.keys(ligne).filter(nomTableValide);
  const valeurs = colonnes.map((c) => ligne[c]);
  const placeholders = colonnes.map((_, i) => `$${i + 1}`).join(", ");
  await client.query(
    `INSERT INTO ${table} (${colonnes.join(", ")}) VALUES (${placeholders})`,
    valeurs,
  );
}

/** Crée une sauvegarde chiffrée de l'église et la stocke. */
export async function creerSauvegarde(
  db: Pool,
  churchId: string,
  userId: string | null,
): Promise<Record<string, unknown>> {
  const tables = await listerTablesEglise(db);
  const ordre = await ordreTables(db, tables);
  const contenu: Record<string, unknown[]> = {};
  const eglise = await db.query(`SELECT * FROM churches WHERE id = $1`, [churchId]);
  contenu["churches"] = eglise.rows;
  for (const table of tables) {
    const { rows } = await db.query(`SELECT * FROM ${table} WHERE church_id = $1`, [churchId]);
    contenu[table] = rows;
  }
  const clair = JSON.stringify(contenu);
  const chiffre = encryptSecret(clair);
  const empreinte = createHash("sha256").update(clair, "utf8").digest("hex");
  const { rows } = await db.query(
    `INSERT INTO sauvegardes
       (church_id, cree_par, taille_octets, empreinte, nb_tables, tables, contenu_chiffre, iv, tag)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING id, church_id, cree_par, taille_octets, empreinte, nb_tables, tables, statut, created_at`,
    [
      churchId,
      userId,
      Buffer.byteLength(clair, "utf8"),
      empreinte,
      tables.length + 1,
      [...ordre, "churches"],
      chiffre.valeur_chiffree,
      chiffre.iv,
      chiffre.tag,
    ],
  );
  return rows[0] as Record<string, unknown>;
}

/** Restaure une sauvegarde : remplace les données de l'église (transaction). */
export async function restaurerSauvegarde(
  db: Pool,
  churchId: string,
  sauvegardeId: string,
): Promise<{ tables: number; lignes: number }> {
  const { rows } = await db.query(
    `SELECT * FROM sauvegardes WHERE id = $1 AND church_id = $2`,
    [sauvegardeId, churchId],
  );
  if (rows.length === 0) {
    throw new ErreurMetier("not_found", "Sauvegarde introuvable.", 404);
  }
  const svg = rows[0];
  let clair: string;
  try {
    clair = decryptSecret({
      valeur_chiffree: svg.contenu_chiffre as string,
      iv: svg.iv as string,
      tag: svg.tag as string,
    });
  } catch {
    throw new ErreurMetier("invalid_input", "Sauvegarde illisible (chiffrement invalide).");
  }
  if (createHash("sha256").update(clair, "utf8").digest("hex") !== svg.empreinte) {
    throw new ErreurMetier("invalid_input", "Sauvegarde corrompue (empreinte différente).");
  }
  const contenu = JSON.parse(clair) as Record<string, Record<string, unknown>[]>;
  const tables = Object.keys(contenu).filter((t) => t !== "churches" && nomTableValide(t));
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const ordre = await ordreTables(client, tables);
    // Suppression enfants d'abord, puis réinsertion parents d'abord.
    for (const table of [...ordre].reverse()) {
      await client.query(`DELETE FROM ${table} WHERE church_id = $1`, [churchId]);
    }
    let lignes = 0;
    for (const ligne of contenu["churches"] ?? []) {
      const colonnes = Object.keys(ligne).filter((c) => c !== "id" && nomTableValide(c));
      const valeurs = colonnes.map((c) => ligne[c]);
      const sets = colonnes.map((c, i) => `${c} = $${i + 2}`).join(", ");
      await client.query(
        `INSERT INTO churches (id, ${colonnes.join(", ")}) VALUES ($1, ${colonnes.map((_, i) => `$${i + 2}`).join(", ")})
         ON CONFLICT (id) DO UPDATE SET ${sets}`,
        [ligne["id"], ...valeurs],
      );
      lignes += 1;
    }
    for (const table of ordre) {
      for (const ligne of contenu[table] ?? []) {
        await insererLigne(client, table, ligne);
        lignes += 1;
      }
    }
    await client.query(`UPDATE sauvegardes SET statut = 'restauree' WHERE id = $1`, [sauvegardeId]);
    await client.query("COMMIT");
    return { tables: tables.length + 1, lignes };
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

// -- Sauvegarde automatique (meilleur effort, offre gratuite) -----------------

let planificateurDemarre = false;

async function verifierSauvegardesAuto(db: Pool): Promise<void> {
  const { rows } = await db.query(
    `SELECT church_id, sauvegarde_frequence, sauvegarde_heure, sauvegarde_auto_derniere_at
       FROM eglise_parametres
      WHERE sauvegarde_frequence IN ('quotidienne', 'hebdomadaire')`,
  );
  const maintenant = new Date();
  const heureActuelle = maintenant.getUTCHours();
  for (const p of rows) {
    const frequence = p.sauvegarde_frequence as string;
    const heureVoulue = Number(String(p.sauvegarde_heure as string).slice(0, 2));
    const derniere = p.sauvegarde_auto_derniere_at as Date | null;
    const ageMs = derniere ? maintenant.getTime() - new Date(derniere).getTime() : Number.POSITIVE_INFINITY;
    const periodeMs = frequence === "quotidienne" ? 23 * 3600 * 1000 : 6 * 24 * 3600 * 1000 + 20 * 3600 * 1000;
    // Due quand la période est dépassée et que l'heure voulue est atteinte,
    // ou en rattrapage quand la période est dépassée de plus d'un jour.
    const due =
      ageMs > periodeMs && (heureActuelle >= heureVoulue || ageMs > periodeMs + 24 * 3600 * 1000);
    if (!due) continue;
    try {
      const svg = await creerSauvegarde(db, p.church_id as string, null);
      await db.query(
        `UPDATE eglise_parametres SET sauvegarde_auto_derniere_at = now() WHERE church_id = $1`,
        [p.church_id],
      );
      await db.query(
        `INSERT INTO notifications (church_id, canal, titre, message, statut)
         VALUES ($1, 'push', 'Sauvegarde automatique', $2, 'en_attente')`,
        [
          p.church_id,
          `Sauvegarde automatique terminée (${svg.nb_tables} tables, ${svg.taille_octets} octets).`,
        ],
      );
      await auditLog(db, {
        churchId: p.church_id as string,
        userId: null,
        action: "sauvegarde.auto",
        details: { sauvegarde_id: svg.id },
      });
    } catch {
      // Une église en échec ne bloque pas les autres.
    }
  }
}

function demarrerPlanificateurSauvegarde(db: Pool): void {
  if (planificateurDemarre) return;
  planificateurDemarre = true;
  if (process.env.SAUVEGARDE_AUTO === "off") return;
  const timer = setInterval(() => {
    void verifierSauvegardesAuto(db);
  }, 60 * 60 * 1000);
  timer.unref();
}

// -- Rejeu hors ligne ----------------------------------------------------------

const chargePointageSchema = pointerSchema;
const chargeContributionSchema = z.object({
  type: z.enum(["dime", "offrande", "don", "depense", "cotisation"]),
  amount_fcfa: z.number().int().positive().max(100_000_000),
  payment_method: z.enum(["wave", "orange_money", "mtn_momo", "especes", "virement"]),
  payment_ref: z.string().min(1).max(120).optional(),
  member_id: z.string().uuid().optional(),
  campagne_id: z.string().uuid().optional(),
  note: z.string().max(500).optional(),
});

/** Exécute une action mise en file (même code métier que la route directe). */
async function executerAction(
  db: Pool,
  churchId: string,
  userId: string,
  typeAction: string,
  charge: unknown,
): Promise<unknown> {
  if (typeAction === "presence.pointer") {
    const parsed = chargePointageSchema.safeParse(charge);
    if (!parsed.success) {
      throw new ErreurMetier("invalid_input", "Charge de pointage invalide.");
    }
    return pointerPresence(db, churchId, userId, parsed.data);
  }
  if (typeAction === "contribution.creer") {
    const parsed = chargeContributionSchema.safeParse(charge);
    if (!parsed.success) {
      throw new ErreurMetier("invalid_input", "Charge de contribution invalide.");
    }
    return creerContribution(db, churchId, userId, parsed.data);
  }
  throw new ErreurMetier("invalid_input", "Type d'action inconnu.");
}

async function rejouerAction(
  db: Pool,
  action: { id: string; church_id: string; user_id: string | null; type_action: string; charge: unknown },
): Promise<{ ok: boolean; erreur?: string }> {
  try {
    await executerAction(db, action.church_id, action.user_id ?? "", action.type_action, action.charge);
    await db.query(
      `UPDATE actions_hors_ligne SET statut = 'rejouee', rejoue_at = now(), erreur = NULL WHERE id = $1`,
      [action.id],
    );
    return { ok: true };
  } catch (e) {
    const message = e instanceof Error ? e.message : "Erreur inconnue.";
    await db.query(
      `UPDATE actions_hors_ligne SET statut = 'echouee', erreur = $2 WHERE id = $1`,
      [action.id, message],
    );
    return { ok: false, erreur: message };
  }
}

export function registerConfianceRoutes(app: FastifyInstance, db: Pool) {
  demarrerPlanificateurSauvegarde(db);

  // -- Double authentification TOTP -------------------------------------------
  app.get(
    "/auth/2fa/etat",
    { preHandler: [requireAuth(db)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT actif FROM auth_2fa WHERE user_id = $1`,
          [req.session.userId],
        );
        return reply.send({ actif: rows[0]?.actif === true });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/auth/2fa/demarrer",
    { preHandler: [requireAuth(db), requireRole(...ROLES_2FA)] },
    async (req, reply) => {
      try {
        const existant = await db.query(
          `SELECT actif FROM auth_2fa WHERE user_id = $1`,
          [req.session.userId],
        );
        if (existant.rows[0]?.actif === true) {
          return reply.code(409).send({ error: "deja_active", message: "La double authentification est déjà active." });
        }
        const { rows: users } = await db.query(
          `SELECT email FROM users WHERE id = $1`,
          [req.session.userId],
        );
        const secret = genererSecretTOTP();
        const chiffre = encryptSecret(secret);
        await db.query(
          `INSERT INTO auth_2fa (user_id, church_id, secret_chiffre, secret_iv, secret_tag, actif)
           VALUES ($1, $2, $3, $4, $5, FALSE)
           ON CONFLICT (user_id) DO UPDATE
             SET secret_chiffre = EXCLUDED.secret_chiffre, secret_iv = EXCLUDED.secret_iv,
                 secret_tag = EXCLUDED.secret_tag, actif = FALSE, verified_at = NULL`,
          [req.session.userId, req.session.churchId, chiffre.valeur_chiffree, chiffre.iv, chiffre.tag],
        );
        // Le secret n'est renvoyé qu'ici, une seule fois, pour le QR Code.
        return reply.send({
          otpauth_uri: uriTOTP(secret, users[0]?.email as string),
          secret,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/auth/2fa/verifier",
    { preHandler: [requireAuth(db), requireRole(...ROLES_2FA)] },
    async (req, reply) => {
      const parsed = z.object({ code: z.string().regex(/^\d{6}$/) }).safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Code à 6 chiffres requis." });
      }
      try {
        const { rows } = await db.query(
          `SELECT secret_chiffre, secret_iv, secret_tag, actif FROM auth_2fa WHERE user_id = $1`,
          [req.session.userId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Aucune activation en cours. Démarrez d'abord la double authentification." });
        }
        if (rows[0].actif === true) {
          return reply.code(409).send({ error: "deja_active", message: "La double authentification est déjà active." });
        }
        const secret = decryptSecret({
          valeur_chiffree: rows[0].secret_chiffre as string,
          iv: rows[0].secret_iv as string,
          tag: rows[0].secret_tag as string,
        });
        if (!verifierCodeTOTP(secret, parsed.data.code)) {
          return reply.code(401).send({ error: "code_invalide", message: "Code incorrect." });
        }
        await db.query(
          `UPDATE auth_2fa SET actif = TRUE, verified_at = now() WHERE user_id = $1`,
          [req.session.userId],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "auth.2fa_activee",
          details: {},
        });
        return reply.send({ ok: true, actif: true });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/auth/2fa/desactiver",
    { preHandler: [requireAuth(db), requireRole(...ROLES_2FA)] },
    async (req, reply) => {
      const parsed = z.object({ code: z.string().regex(/^\d{6}$/) }).safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Code à 6 chiffres requis." });
      }
      try {
        const { rows } = await db.query(
          `SELECT secret_chiffre, secret_iv, secret_tag FROM auth_2fa WHERE user_id = $1 AND actif = TRUE`,
          [req.session.userId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "La double authentification n'est pas active." });
        }
        const secret = decryptSecret({
          valeur_chiffree: rows[0].secret_chiffre as string,
          iv: rows[0].secret_iv as string,
          tag: rows[0].secret_tag as string,
        });
        if (!verifierCodeTOTP(secret, parsed.data.code)) {
          return reply.code(401).send({ error: "code_invalide", message: "Code incorrect." });
        }
        await db.query(`DELETE FROM auth_2fa WHERE user_id = $1`, [req.session.userId]);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "auth.2fa_desactivee",
          details: {},
        });
        return reply.send({ ok: true, actif: false });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Journal d'audit (lecture seule) -----------------------------------------
  app.get(
    "/audit",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = paginationSchema
        .extend({
          action: z.string().max(120).optional(),
          user_id: uuid.optional(),
        })
        .safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Paramètres invalides." });
      }
      const { limit, offset, action, user_id } = parsed.data;
      try {
        const conditions = [`a.church_id = $1`];
        const valeurs: unknown[] = [req.session.churchId];
        if (action) {
          valeurs.push(action);
          conditions.push(`a.action = $${valeurs.length}`);
        }
        if (user_id) {
          valeurs.push(user_id);
          conditions.push(`a.user_id = $${valeurs.length}`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM audit_logs a ${where}`,
          valeurs,
        );
        const { rows } = await db.query(
          `SELECT a.id, a.church_id, a.user_id, u.full_name AS user_nom, a.action,
                  a.details, a.hash, a.hash_precedent, a.created_at
             FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id
            ${where} ORDER BY a.seq DESC
            LIMIT $${valeurs.length + 1} OFFSET $${valeurs.length + 2}`,
          [...valeurs, limit, offset],
        );
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/audit/verifier",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, church_id, user_id, action, details, hash, hash_precedent, created_at
             FROM audit_logs WHERE church_id = $1 ORDER BY seq ASC`,
          [req.session.churchId],
        );
        const resultat = verifierChaineAudit(rows);
        return reply.send(resultat);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/audit/consultations",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = paginationSchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Paramètres invalides." });
      }
      const { limit, offset } = parsed.data;
      try {
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM consultations_sensibles WHERE church_id = $1`,
          [req.session.churchId],
        );
        const { rows } = await db.query(
          `SELECT c.id, c.church_id, c.user_id, u.full_name AS user_nom, c.ressource,
                  c.ressource_id, m.full_name AS ressource_nom, c.action, c.created_at
             FROM consultations_sensibles c
             LEFT JOIN users u ON u.id = c.user_id
             LEFT JOIN members m ON m.id = c.ressource_id AND c.ressource = 'membre'
            WHERE c.church_id = $1 ORDER BY c.created_at DESC
            LIMIT $2 OFFSET $3`,
          [req.session.churchId, limit, offset],
        );
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Paramètres de confiance ---------------------------------------------------
  app.get(
    "/confiance/parametres",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        return reply.send(await lireParametres(db, req.session.churchId));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/confiance/parametres",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = z
        .object({
          sauvegarde_frequence: z.enum(["jamais", "quotidienne", "hebdomadaire"]).optional(),
          sauvegarde_heure: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
          notification_fournisseur: z.string().max(60).nullable().optional(),
          notification_cle: z.string().min(8).max(500).optional(),
          notification_plafond_mensuel: z.number().int().min(0).max(1_000_000).optional(),
          notifications_actives: z.boolean().optional(),
        })
        .safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Paramètres invalides." });
      }
      const data = parsed.data;
      try {
        await assurerParametres(db, req.session.churchId);
        const sets: string[] = [];
        const valeurs: unknown[] = [req.session.churchId];
        if (data.sauvegarde_frequence !== undefined) {
          valeurs.push(data.sauvegarde_frequence);
          sets.push(`sauvegarde_frequence = $${valeurs.length}`);
        }
        if (data.sauvegarde_heure !== undefined) {
          valeurs.push(data.sauvegarde_heure);
          sets.push(`sauvegarde_heure = $${valeurs.length}`);
        }
        if (data.notification_fournisseur !== undefined) {
          valeurs.push(data.notification_fournisseur);
          sets.push(`notification_fournisseur = $${valeurs.length}`);
        }
        if (data.notification_cle !== undefined) {
          const chiffre = encryptSecret(data.notification_cle);
          valeurs.push(chiffre.valeur_chiffree, chiffre.iv, chiffre.tag);
          sets.push(
            `notification_cle_chiffree = $${valeurs.length - 2}`,
            `notification_cle_iv = $${valeurs.length - 1}`,
            `notification_cle_tag = $${valeurs.length}`,
          );
        }
        if (data.notification_plafond_mensuel !== undefined) {
          valeurs.push(data.notification_plafond_mensuel);
          sets.push(`notification_plafond_mensuel = $${valeurs.length}`);
        }
        if (data.notifications_actives !== undefined) {
          valeurs.push(data.notifications_actives);
          sets.push(`notifications_actives = $${valeurs.length}`);
        }
        if (sets.length === 0) {
          return reply.code(400).send({ error: "invalid_input", message: "Rien à modifier." });
        }
        await db.query(
          `UPDATE eglise_parametres SET ${sets.join(", ")}, updated_at = now() WHERE church_id = $1`,
          valeurs,
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "confiance.parametres_modifies",
          details: { champs: Object.keys(data) },
        });
        return reply.send(await lireParametres(db, req.session.churchId));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Sauvegardes ---------------------------------------------------------------
  app.post(
    "/sauvegardes",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        const svg = await creerSauvegarde(db, req.session.churchId, req.session.userId);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "sauvegarde.creee",
          details: { sauvegarde_id: svg.id, taille_octets: svg.taille_octets },
        });
        return reply.code(201).send(svg);
      } catch (e) {
        if (e instanceof ErreurMetier) {
          return reply.code(e.statut).send({ error: e.code, message: e.message });
        }
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/sauvegardes",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = paginationSchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Paramètres invalides." });
      }
      const { limit, offset } = parsed.data;
      try {
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM sauvegardes WHERE church_id = $1`,
          [req.session.churchId],
        );
        const { rows } = await db.query(
          `SELECT id, church_id, cree_par, taille_octets, empreinte, nb_tables,
                  tables, statut, created_at
             FROM sauvegardes WHERE church_id = $1 ORDER BY created_at DESC
            LIMIT $2 OFFSET $3`,
          [req.session.churchId, limit, offset],
        );
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/sauvegardes/:id/telecharger",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, contenu_chiffre, iv, tag, empreinte, tables, created_at
             FROM sauvegardes WHERE id = $1 AND church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Sauvegarde introuvable." });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/sauvegardes/restaurer",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = z.object({ sauvegarde_id: uuid }).safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Sauvegarde requise." });
      }
      try {
        const resultat = await restaurerSauvegarde(db, req.session.churchId, parsed.data.sauvegarde_id);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "sauvegarde.restauree",
          details: { sauvegarde_id: parsed.data.sauvegarde_id, ...resultat },
        });
        return reply.send({ ok: true, ...resultat });
      } catch (e) {
        if (e instanceof ErreurMetier) {
          return reply.code(e.statut).send({ error: e.code, message: e.message });
        }
        return dbError(reply, e);
      }
    },
  );

  // -- Notifications (boîte d'envoi) ----------------------------------------------
  app.get(
    "/notifications",
    { preHandler: [requireAuth(db), requireRole(...EQUIPE)] },
    async (req, reply) => {
      const parsed = paginationSchema
        .extend({
          statut: z.string().max(30).optional(),
          canal: z.enum(["push", "sms"]).optional(),
        })
        .safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Paramètres invalides." });
      }
      const { limit, offset, statut, canal } = parsed.data;
      try {
        const conditions = [`church_id = $1`];
        const valeurs: unknown[] = [req.session.churchId];
        if (statut) {
          valeurs.push(statut);
          conditions.push(`statut = $${valeurs.length}`);
        }
        if (canal) {
          valeurs.push(canal);
          conditions.push(`canal = $${valeurs.length}`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM notifications ${where}`,
          valeurs,
        );
        const { rows } = await db.query(
          `SELECT id, church_id, user_id, canal, titre, message, statut, erreur, created_at, envoyee_at
             FROM notifications ${where} ORDER BY created_at DESC
            LIMIT $${valeurs.length + 1} OFFSET $${valeurs.length + 2}`,
          [...valeurs, limit, offset],
        );
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/notifications",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = z
        .object({
          canal: z.enum(["push", "sms"]).default("push"),
          titre: z.string().min(2).max(200),
          message: z.string().min(2).max(1000),
          user_id: uuid.optional(),
        })
        .safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Notification invalide." });
      }
      const data = parsed.data;
      try {
        if (data.user_id) {
          const membre = await db.query(
            `SELECT 1 FROM church_users WHERE user_id = $1 AND church_id = $2`,
            [data.user_id, req.session.churchId],
          );
          if (membre.rowCount === 0) {
            return reply.code(400).send({ error: "invalid_reference", message: "Destinataire hors de votre église." });
          }
        }
        const { rows } = await db.query(
          `INSERT INTO notifications (church_id, user_id, canal, titre, message)
           VALUES ($1, $2, $3, $4, $5) RETURNING *`,
          [req.session.churchId, data.user_id ?? null, data.canal, data.titre, data.message],
        );
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/notifications/:id/envoyer",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, statut FROM notifications WHERE id = $1 AND church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Notification introuvable." });
        }
        if (rows[0].statut === "envoyee") {
          return reply.code(409).send({ error: "deja_envoyee", message: "Notification déjà envoyée." });
        }
        // Aucun fournisseur n'est branché (choix d'Axel en attente) :
        // l'envoi échoue proprement, rien ne part, la notification
        // reste en file avec la raison.
        const params = await lireParametres(db, req.session.churchId);
        const raison = !params.notification_fournisseur
          ? "Fournisseur de notifications non configuré."
          : `Fournisseur « ${params.notification_fournisseur} » sans adaptateur pour le moment.`;
        await db.query(
          `UPDATE notifications SET statut = 'non_configurée', erreur = $2 WHERE id = $1`,
          [rows[0].id, raison],
        );
        return reply.code(409).send({ error: "fournisseur_non_configure", message: raison });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- File d'actions hors ligne ----------------------------------------------------
  app.post(
    "/actions-hors-ligne",
    { preHandler: [requireAuth(db), requireRole(...EQUIPE)] },
    async (req, reply) => {
      const parsed = z
        .object({
          type_action: z.enum(["presence.pointer", "contribution.creer"]),
          charge: z.record(z.string(), z.unknown()),
          cle_client: z.string().min(8).max(120),
        })
        .safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Action hors ligne invalide." });
      }
      const data = parsed.data;
      try {
        const { rows } = await db.query(
          `INSERT INTO actions_hors_ligne (church_id, user_id, type_action, charge, cle_client)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (church_id, cle_client) DO NOTHING RETURNING *`,
          [req.session.churchId, req.session.userId, data.type_action, JSON.stringify(data.charge), data.cle_client],
        );
        if (rows.length > 0) {
          return reply.code(201).send(rows[0]);
        }
        const existant = await db.query(
          `SELECT * FROM actions_hors_ligne WHERE church_id = $1 AND cle_client = $2`,
          [req.session.churchId, data.cle_client],
        );
        return reply.send({ ...existant.rows[0], deja_enregistree: true });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/actions-hors-ligne",
    { preHandler: [requireAuth(db), requireRole(...EQUIPE)] },
    async (req, reply) => {
      const parsed = paginationSchema
        .extend({ statut: z.string().max(30).optional() })
        .safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "Paramètres invalides." });
      }
      const { limit, offset, statut } = parsed.data;
      try {
        const conditions = [`church_id = $1`];
        const valeurs: unknown[] = [req.session.churchId];
        // Seul l'admin voit la file de toute l'église ; les autres ne
        // voient que leurs propres actions.
        if (req.session.role !== "admin_eglise") {
          valeurs.push(req.session.userId);
          conditions.push(`user_id = $${valeurs.length}`);
        }
        if (statut) {
          valeurs.push(statut);
          conditions.push(`statut = $${valeurs.length}`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM actions_hors_ligne ${where}`,
          valeurs,
        );
        const { rows } = await db.query(
          `SELECT * FROM actions_hors_ligne ${where} ORDER BY created_at ASC
           LIMIT $${valeurs.length + 1} OFFSET $${valeurs.length + 2}`,
          [...valeurs, limit, offset],
        );
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/actions-hors-ligne/rejouer-tout",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT * FROM actions_hors_ligne
            WHERE church_id = $1 AND statut IN ('en_attente', 'echouee')
            ORDER BY created_at ASC`,
          [req.session.churchId],
        );
        const details: { id: string; ok: boolean; erreur?: string }[] = [];
        for (const action of rows) {
          const resultat = await rejouerAction(db, action);
          details.push({ id: action.id as string, ...resultat });
        }
        const rejouees = details.filter((d) => d.ok).length;
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "actions_hors_ligne.rejouees",
          details: { rejouees, echouees: details.length - rejouees },
        });
        return reply.send({ rejouees, echouees: details.length - rejouees, details });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/actions-hors-ligne/:id/rejouer",
    { preHandler: [requireAuth(db), requireRole(...EQUIPE)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT * FROM actions_hors_ligne WHERE id = $1 AND church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Action introuvable." });
        }
        const action = rows[0];
        if (req.session.role !== "admin_eglise" && action.user_id !== req.session.userId) {
          return reply.code(403).send({ error: "forbidden", message: "Cette action appartient à un autre utilisateur." });
        }
        const resultat = await rejouerAction(db, action);
        return reply.send({ id: action.id, ...resultat });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
