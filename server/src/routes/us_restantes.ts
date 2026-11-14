import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import {
  READ_ALL,
  WRITE_ADMIN,
  WRITE_FINANCES,
  WRITE_STD,
  existsInChurch,
  memberInChurch,
  registerCrud,
  invalidInput,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Tranche T12 — US4 à US17 restantes.
 *
 * Promesses de don avec échéancier (US4), dons en nature (US5), fiche
 * visiteur (US6), rappels d'événements de vie (US7), transparence
 * financière agrégée côté membre (US8), carte dans le portefeuille
 * (US9, export sans compte Wallet branché), WhatsApp avec consentement
 * (US10, aucun envoi réel : aucun fournisseur choisi), alertes pour
 * l'église mère (US11), listes configurables (US12, US13), seuils et
 * montants suggérés (US14), langue et mode économique côté application
 * (US15, US16, réglages locaux), confidentialité par défaut (US17 :
 * lectures sensibles journalisées, masquage côté application).
 *
 * Aucune donnée inventée : les montants, seuils et listes sont
 * configurés par l'église ou vides par défaut.
 */

const uuid = z.string().uuid();
const dateSeule = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.");

/** Statuts riches par défaut (membre_statuts). */
export const STATUTS_RICHES_DEFAUT = [
  "membre",
  "sympathisant",
  "nouveau_converti",
  "en_formation",
  "suspendu",
  "parti",
  "ancien",
] as const;

/** Statuts riches effectifs d'une église : défauts + libellés configurés. */
export async function statutsRichesAutorises(
  db: Pool,
  churchId: string,
): Promise<string[]> {
  const { rows } = await db.query<{ libelle: string; archive: boolean }>(
    `SELECT libelle, archive FROM listes_configurables
      WHERE church_id = $1 AND type = 'statut_membre'`,
    [churchId],
  );
  const actives = new Set<string>(STATUTS_RICHES_DEFAUT);
  for (const r of rows) {
    if (r.archive) actives.delete(r.libelle);
    else actives.add(r.libelle);
  }
  return [...actives];
}

/** Fiche membre liée au compte, ou null. */
async function membreLie(db: Pool, userId: string): Promise<string | null> {
  const { rows } = await db.query<{ member_id: string | null }>(
    `SELECT member_id FROM users WHERE id = $1`,
    [userId],
  );
  return rows[0]?.member_id ?? null;
}

const TYPES_EVENEMENT_VIE = ["anniversaire", "mariage", "conversion", "bapteme"] as const;

export function registerUsRestantesRoutes(app: FastifyInstance, db: Pool) {
  // -- Promesses de don (US4) : création explicite, l'échéancier est
  //    généré à la création (montant réparti, reste sur la dernière
  //    échéance). Un versement reçu est une contribution confirmée
  //    rattachée à la promesse ; l'annulation ne touche jamais aux
  //    versements déjà reçus. -------------------------------------------
  app.get(
    "/promesses",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const limit = Math.min(Math.max(Number((req.query as { limit?: string }).limit ?? 50) || 50, 1), 100);
        const offset = Math.max(Number((req.query as { offset?: string }).offset ?? 0) || 0, 0);
        const memberId = (req.query as { member_id?: string }).member_id;
        const conditions = ["p.church_id = $1"];
        const values: unknown[] = [req.session.churchId];
        if (req.session.role === "membre") {
          const mien = await membreLie(db, req.session.userId);
          conditions.push(`p.member_id = $${values.length + 1}`);
          values.push(mien);
        } else if (memberId) {
          conditions.push(`p.member_id = $${values.length + 1}`);
          values.push(memberId);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM promesses p ${where}`,
          values,
        );
        const { rows } = await db.query(
          `SELECT p.*, m.full_name AS membre_nom,
                  (SELECT coalesce(sum(e.montant_fcfa), 0)::int FROM echeances_promesses e
                    WHERE e.promesse_id = p.id AND e.statut = 'recu') AS recu_fcfa,
                  (SELECT coalesce(sum(e.montant_fcfa), 0)::int FROM echeances_promesses e
                    WHERE e.promesse_id = p.id AND e.statut = 'en_attente') AS reste_fcfa
             FROM promesses p LEFT JOIN members m ON m.id = p.member_id ${where}
            ORDER BY p.created_at DESC
            LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
          [...values, limit, offset],
        );
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/promesses/:id",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const id = (req.params as { id: string }).id;
        const { rows } = await db.query(
          `SELECT p.*, m.full_name AS membre_nom,
                  (SELECT coalesce(sum(e.montant_fcfa), 0)::int FROM echeances_promesses e
                    WHERE e.promesse_id = p.id AND e.statut = 'recu') AS recu_fcfa,
                  (SELECT coalesce(sum(e.montant_fcfa), 0)::int FROM echeances_promesses e
                    WHERE e.promesse_id = p.id AND e.statut = 'en_attente') AS reste_fcfa
             FROM promesses p LEFT JOIN members m ON m.id = p.member_id
            WHERE p.id = $1 AND p.church_id = $2`,
          [id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Promesse introuvable." });
        }
        if (req.session.role === "membre") {
          const mien = await membreLie(db, req.session.userId);
          if (rows[0].member_id !== mien) {
            return reply.code(403).send({ error: "forbidden", message: "Cette promesse n'est pas la vôtre." });
          }
        }
        const echeances = await db.query(
          `SELECT * FROM echeances_promesses WHERE promesse_id = $1 ORDER BY date_echeance ASC`,
          [id],
        );
        return reply.send({ ...rows[0], echeances: echeances.rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  const promesseSchema = z.object({
    member_id: uuid,
    montant_total_fcfa: z.number().int().positive().max(100_000_000),
    date_debut: dateSeule.optional(),
    nb_versements: z.number().int().min(1).max(120).default(1),
  });
  app.post(
    "/promesses",
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "tresorier", "membre")] },
    async (req, reply) => {
      const parsed = promesseSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      try {
        if (!(await memberInChurch(db, req.session.churchId, data.member_id))) {
          return reply.code(400).send({ error: "invalid_reference", message: "Le membre n'appartient pas à votre église." });
        }
        if (req.session.role === "membre") {
          const mien = await membreLie(db, req.session.userId);
          if (data.member_id !== mien) {
            return reply.code(403).send({ error: "forbidden", message: "Un membre ne s'engage que pour lui-même." });
          }
        }
        const debut = data.date_debut ?? new Date().toISOString().slice(0, 10);
        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows } = await client.query(
            `INSERT INTO promesses (church_id, member_id, montant_total_fcfa, date_debut, nb_versements)
             VALUES ($1, $2, $3, $4, $5) RETURNING *`,
            [req.session.churchId, data.member_id, data.montant_total_fcfa, debut, data.nb_versements],
          );
          const promesse = rows[0];
          const part = Math.floor(data.montant_total_fcfa / data.nb_versements);
          const reste = data.montant_total_fcfa - part * (data.nb_versements - 1);
          const [a, m, j] = debut.split("-").map(Number);
          for (let i = 0; i < data.nb_versements; i++) {
            const d = new Date(Date.UTC(a, m - 1 + i, j));
            const iso = d.toISOString().slice(0, 10);
            const montant = i === data.nb_versements - 1 ? reste : part;
            await client.query(
              `INSERT INTO echeances_promesses (promesse_id, date_echeance, montant_fcfa)
               VALUES ($1, $2, $3)`,
              [promesse.id, iso, montant],
            );
          }
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "promesse.creee",
            details: { promesse_id: promesse.id, montant_total_fcfa: data.montant_total_fcfa },
          });
          await client.query("COMMIT");
          return reply.code(201).send(promesse);
        } catch (e) {
          await client.query("ROLLBACK").catch(() => undefined);
          throw e;
        } finally {
          client.release();
        }
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/promesses/:id",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = z.object({ statut: z.enum(["annulee"]) }).safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const id = (req.params as { id: string }).id;
        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows } = await client.query(
            `UPDATE promesses SET statut = 'annulee'
              WHERE id = $1 AND church_id = $2 AND statut = 'en_cours' RETURNING *`,
            [id, req.session.churchId],
          );
          if (rows.length === 0) {
            await client.query("ROLLBACK");
            return reply.code(404).send({ error: "not_found", message: "Promesse introuvable ou déjà clôturée." });
          }
          // Les versements déjà reçus restent ; seules les échéances en
          // attente sont annulées.
          await client.query(
            `UPDATE echeances_promesses SET statut = 'annulee'
              WHERE promesse_id = $1 AND statut = 'en_attente'`,
            [id],
          );
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "promesse.annulee",
            details: { promesse_id: id },
          });
          await client.query("COMMIT");
          return reply.send(rows[0]);
        } catch (e) {
          await client.query("ROLLBACK").catch(() => undefined);
          throw e;
        } finally {
          client.release();
        }
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Versement sur une échéance : contribution en attente, rattachée
  //    à la promesse. La confirmation (flux existant) marque l'échéance
  //    reçue ; voir contributions.ts, confirmerContribution. -----------
  const versementSchema = z.object({
    echeance_id: uuid,
    amount_fcfa: z.number().int().positive().max(100_000_000),
    payment_method: z.enum(["wave", "orange_money", "mtn_momo", "especes", "virement"]),
    payment_ref: z.string().min(1).max(120).optional(),
    note: z.string().max(500).optional(),
  });
  app.post(
    "/promesses/:id/versements",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = versementSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      try {
        const id = (req.params as { id: string }).id;
        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows: promesses } = await client.query(
            `SELECT * FROM promesses WHERE id = $1 AND church_id = $2 AND statut = 'en_cours' FOR UPDATE`,
            [id, req.session.churchId],
          );
          if (promesses.length === 0) {
            await client.query("ROLLBACK");
            return reply.code(404).send({ error: "not_found", message: "Promesse introuvable ou clôturée." });
          }
          const { rows: echeances } = await client.query(
            `SELECT * FROM echeances_promesses WHERE id = $1 AND promesse_id = $2 AND statut = 'en_attente' FOR UPDATE`,
            [data.echeance_id, id],
          );
          if (echeances.length === 0) {
            await client.query("ROLLBACK");
            return reply.code(404).send({ error: "not_found", message: "Échéance introuvable ou déjà réglée." });
          }
          if (data.amount_fcfa !== echeances[0].montant_fcfa) {
            await client.query("ROLLBACK");
            return reply.code(400).send({ error: "invalid_input", message: "Le versement doit égaler le montant de l'échéance." });
          }
          const { rows } = await client.query(
            `INSERT INTO contributions
               (church_id, member_id, type, amount_fcfa, payment_method, payment_ref, status, received_by, note, promesse_id)
             VALUES ($1, $2, 'don', $3, $4, $5, 'en_attente', $6, $7, $8) RETURNING *`,
            [
              req.session.churchId,
              promesses[0].member_id,
              data.amount_fcfa,
              data.payment_method,
              data.payment_ref ?? null,
              req.session.userId,
              data.note ?? null,
              id,
            ],
          );
          await client.query(
            `UPDATE echeances_promesses SET contribution_id = $2 WHERE id = $1`,
            [data.echeance_id, rows[0].id],
          );
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "promesse.versement_enregistre",
            details: { promesse_id: id, contribution_id: rows[0].id, amount_fcfa: data.amount_fcfa },
          });
          await client.query("COMMIT");
          return reply.code(201).send(rows[0]);
        } catch (e) {
          await client.query("ROLLBACK").catch(() => undefined);
          throw e;
        } finally {
          client.release();
        }
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Dons en nature (US5) : séparés des contributions en argent, ils
  //    n'entrent jamais dans les totaux financiers ni dans le solde. ----
  registerCrud(app, db, {
    base: "/dons-nature",
    table: "dons_nature",
    columns: ["member_id", "description", "quantite", "unite", "type_don", "heures", "date_don", "anonyme"],
    createSchema: z.object({
      member_id: uuid.optional(),
      description: z.string().min(2).max(500),
      quantite: z.number().int().min(0).max(1_000_000).default(1),
      unite: z.string().max(40).optional(),
      type_don: z.enum(["materiel", "nourriture", "temps"]).default("materiel"),
      heures: z.number().min(0).max(10000).optional(),
      date_don: dateSeule.optional(),
      anonyme: z.boolean().default(false),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_FINANCES,
    audit: "don_nature",
    filters: { type_don: "type_don", member_id: "member_id" },
    orderBy: "date_don DESC",
    searchColumn: "description",
    readScope: async (db2, session) => {
      if (session.role !== "membre") return null;
      const mien = await membreLie(db2, session.userId);
      return { condition: "member_id = $1", values: [mien] };
    },
    validate: async (db2, churchId, data) => {
      if (data.member_id && !(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Le membre n'appartient pas à votre église.";
      }
      if (data.anonyme && data.member_id) {
        return "Un don anonyme ne porte pas de membre.";
      }
      return null;
    },
  });

  // -- Fiche visiteur (US6) : nom et date de venue seuls obligatoires.
  //    Un visiteur n'apparaît ni dans les membres ni dans les finances
  //    tant qu'il n'est pas devenu membre. ------------------------------
  registerCrud(app, db, {
    base: "/visiteurs",
    table: "visiteurs",
    columns: ["nom", "date_venue", "telephone", "email", "moyen_contact", "statut", "member_id"],
    createSchema: z.object({
      nom: z.string().min(2).max(200),
      date_venue: dateSeule.optional(),
      telephone: z.string().max(30).optional(),
      email: z.string().email().max(254).optional(),
      moyen_contact: z.string().max(200).optional(),
      statut: z.enum(["nouveau", "recontacte", "devenu_membre"]).default("nouveau"),
      member_id: uuid.optional(),
    }),
    readRoles: ["admin_eglise", "tresorier", "responsable_culte"],
    writeRoles: WRITE_STD,
    audit: "visiteur",
    filters: { statut: "statut" },
    orderBy: "date_venue DESC",
    searchColumn: "nom",
    validate: async (db2, churchId, data) => {
      if (data.member_id && !(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Le membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  app.post(
    "/visiteurs/:id/devenir-membre",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      const parsed = z.object({ member_id: uuid }).safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const id = (req.params as { id: string }).id;
        if (!(await memberInChurch(db, req.session.churchId, parsed.data.member_id))) {
          return reply.code(400).send({ error: "invalid_reference", message: "Le membre n'appartient pas à votre église." });
        }
        const { rows } = await db.query(
          `UPDATE visiteurs SET statut = 'devenu_membre', member_id = $3
            WHERE id = $1 AND church_id = $2 AND statut <> 'devenu_membre' RETURNING *`,
          [id, req.session.churchId, parsed.data.member_id],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Visiteur introuvable ou déjà membre." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "visiteur.devenu_membre",
          details: { visiteur_id: id, member_id: parsed.data.member_id },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Alertes pour l'église mère (US11) : une alerte par antenne et
  //    par type tant qu'elle n'est pas traitée ; une antenne ne voit
  //    jamais les alertes d'une autre antenne. --------------------------
  registerCrud(app, db, {
    base: "/alertes-mere",
    table: "alertes_mere",
    columns: ["annexe_id", "type", "periode", "statut"],
    createSchema: z.object({
      annexe_id: uuid,
      type: z.enum(["inactive", "baisse_contributions", "rapport_manquant"]),
      periode: z.string().regex(/^\d{4}-\d{2}$/, "Période au format AAAA-MM."),
      statut: z.enum(["ouverte", "traitee"]).default("ouverte"),
    }),
    readRoles: WRITE_ADMIN,
    writeRoles: WRITE_ADMIN,
    audit: "alerte_mere",
    filters: { statut: "statut", type: "type", annexe_id: "annexe_id" },
    orderBy: "created_at DESC",
  });

  app.post(
    "/alertes-mere/detecter",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ADMIN)] },
    async (req, reply) => {
      try {
        const { rows: egliseRows } = await db.query<{ parent_church_id: string | null }>(
          `SELECT parent_church_id FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        if (egliseRows.length === 0 || egliseRows[0].parent_church_id) {
          return reply.code(403).send({ error: "forbidden", message: "La détection des alertes est réservée à l'église mère." });
        }
        const { rows: params } = await db.query(
          `SELECT seuil_inactivite_semaines, seuil_baisse_contributions_pct
             FROM eglise_parametres WHERE church_id = $1`,
          [req.session.churchId],
        );
        const inactiviteSemaines = params[0]?.seuil_inactivite_semaines ?? 4;
        const seuilBaisse = params[0]?.seuil_baisse_contributions_pct ?? 30;
        const periode = new Date().toISOString().slice(0, 7);
        const { rows: annexes } = await db.query<{ id: string }>(
          `SELECT id FROM churches WHERE parent_church_id = $1`,
          [req.session.churchId],
        );
        let creees = 0;
        for (const annexe of annexes) {
          const aId = annexe.id;
          // Antenne inactive : aucune contribution confirmée ni aucun
          // culte depuis le seuil d'inactivité.
          const { rows: activite } = await db.query<{ n: string }>(
            `SELECT (
               (SELECT count(*) FROM contributions WHERE church_id = $1 AND status = 'confirme'
                 AND created_at >= now() - ($2 || ' weeks')::interval)
               + (SELECT count(*) FROM cultes WHERE church_id = $1
                 AND date_heure >= now() - ($2 || ' weeks')::interval)
             )::text AS n`,
            [aId, String(inactiviteSemaines)],
          );
          if (Number(activite[0]?.n ?? 0) === 0) {
            const r = await db.query(
              `INSERT INTO alertes_mere (church_id, annexe_id, type, periode)
               VALUES ($1, $2, 'inactive', $3)
               ON CONFLICT (church_id, annexe_id, type) WHERE statut = 'ouverte' DO NOTHING
               RETURNING id`,
              [req.session.churchId, aId, periode],
            );
            creees += r.rowCount ?? 0;
          }
          // Contributions en baisse : mois en cours contre mois dernier.
          const { rows: baisse } = await db.query<{ actuel: string; precedent: string }>(
            `SELECT
               (SELECT coalesce(sum(amount_fcfa), 0)::text FROM contributions
                 WHERE church_id = $1 AND status = 'confirme' AND type <> 'depense'
                 AND date_trunc('month', created_at) = date_trunc('month', now())) AS actuel,
               (SELECT coalesce(sum(amount_fcfa), 0)::text FROM contributions
                 WHERE church_id = $1 AND status = 'confirme' AND type <> 'depense'
                 AND date_trunc('month', created_at) = date_trunc('month', now() - interval '1 month')) AS precedent`,
            [aId],
          );
          const actuel = Number(baisse[0]?.actuel ?? 0);
          const precedent = Number(baisse[0]?.precedent ?? 0);
          if (precedent > 0 && actuel < precedent * (1 - seuilBaisse / 100)) {
            const r = await db.query(
              `INSERT INTO alertes_mere (church_id, annexe_id, type, periode)
               VALUES ($1, $2, 'baisse_contributions', $3)
               ON CONFLICT (church_id, annexe_id, type) WHERE statut = 'ouverte' DO NOTHING
               RETURNING id`,
              [req.session.churchId, aId, periode],
            );
            creees += r.rowCount ?? 0;
          }
          // Rapport non soumis : aucun rapport d'annexe depuis 30 jours.
          const { rows: rapport } = await db.query<{ n: string }>(
            `SELECT count(*)::text AS n FROM rapports_annexe
              WHERE eglise_id = $1 AND cree_le >= now() - interval '30 days'`,
            [aId],
          );
          if (Number(rapport[0]?.n ?? 0) === 0) {
            const r = await db.query(
              `INSERT INTO alertes_mere (church_id, annexe_id, type, periode)
               VALUES ($1, $2, 'rapport_manquant', $3)
               ON CONFLICT (church_id, annexe_id, type) WHERE statut = 'ouverte' DO NOTHING
               RETURNING id`,
              [req.session.churchId, aId, periode],
            );
            creees += r.rowCount ?? 0;
          }
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "alertes_mere.detectees",
          details: { creees, annexes: annexes.length },
        });
        return reply.send({ creees, annexes: annexes.length });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/alertes-mere/:id/traiter",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ADMIN)] },
    async (req, reply) => {
      try {
        const id = (req.params as { id: string }).id;
        const { rows } = await db.query(
          `UPDATE alertes_mere SET statut = 'traitee', traitee_par = $3, traitee_at = now()
            WHERE id = $1 AND church_id = $2 AND statut = 'ouverte' RETURNING *`,
          [id, req.session.churchId, req.session.userId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Alerte introuvable ou déjà traitée." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "alerte_mere.traitee",
          details: { alerte_id: id, type: rows[0].type },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Listes configurables (US12, US13) : rôles, catégories, statuts
  //    de membre, départements. Un libellé archivé ne supprime rien :
  //    les enregistrements gardent leur valeur. -------------------------
  registerCrud(app, db, {
    base: "/listes-configurables",
    table: "listes_configurables",
    columns: ["type", "libelle", "niveau", "archive"],
    createSchema: z.object({
      type: z.enum(["role", "categorie_depense", "categorie_recette", "statut_membre", "departement"]),
      libelle: z.string().min(2).max(120),
      niveau: z.enum(["admin_eglise", "tresorier", "responsable_culte", "membre"]).optional(),
      archive: z.boolean().default(false),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_ADMIN,
    audit: "liste_configurable",
    filters: { type: "type", archive: "archive" },
    orderBy: "type ASC, libelle ASC",
    validate: async (_db2, _churchId, data) => {
      if (data.type === "role" && !data.niveau) {
        return "Un rôle configuré doit indiquer son niveau de droits.";
      }
      return null;
    },
  });

  // Statuts de membre effectifs : défauts + libellés configurés non
  // archivés, défauts archivés retirés.
  app.get(
    "/listes-configurables/statuts-membre",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const statuts = await statutsRichesAutorises(db, req.session.churchId);
        return reply.send({ items: statuts });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rappels d'événements de vie (US7) : anniversaire, mariage,
  //    conversion, baptême. Les dates sont celles des fiches membres ;
  //    un membre masque les types qu'il ne veut pas voir rappelés. -----
  app.get(
    "/evenements-vie",
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "tresorier", "responsable_culte")] },
    async (req, reply) => {
      try {
        const jours = Math.min(Math.max(Number((req.query as { jours?: string }).jours ?? 30) || 30, 1), 365);
        const { rows: membres } = await db.query(
          `SELECT id, full_name, birth_date, date_mariage, date_conversion,
                  evenements_vie_masques FROM members WHERE church_id = $1`,
          [req.session.churchId],
        );
        const { rows: baptemes } = await db.query(
          `SELECT member_id, date_bapteme FROM baptemes WHERE church_id = $1`,
          [req.session.churchId],
        );
        const aujourdHui = new Date();
        aujourdHui.setUTCHours(0, 0, 0, 0);
        const limite = new Date(aujourdHui);
        limite.setUTCDate(limite.getUTCDate() + jours);
        const masque = (m: { evenements_vie_masques?: string[] | null }, type: string) =>
          (m.evenements_vie_masques ?? []).includes(type);
        const prochaine = (date: Date): { date: Date; joursRestants: number } => {
          const candidate = new Date(Date.UTC(aujourdHui.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
          if (candidate < aujourdHui) candidate.setUTCFullYear(candidate.getUTCFullYear() + 1);
          return { date: candidate, joursRestants: Math.round((candidate.getTime() - aujourdHui.getTime()) / 86400000) };
        };
        const resultats: { member_id: string; nom: string; type: string; date: string; jours_restants: number }[] = [];
        const ajouter = (m: { id: string; full_name: string; evenements_vie_masques?: string[] | null }, type: string, valeur: string | Date | null) => {
          if (!valeur || masque(m, type)) return;
          const d = valeur instanceof Date ? valeur : new Date(valeur);
          if (Number.isNaN(d.getTime())) return;
          const { date, joursRestants } = prochaine(d);
          if (date <= limite) {
            resultats.push({ member_id: m.id, nom: m.full_name, type, date: date.toISOString().slice(0, 10), jours_restants: joursRestants });
          }
        };
        for (const m of membres) {
          ajouter(m, "anniversaire", m.birth_date);
          ajouter(m, "mariage", m.date_mariage);
          ajouter(m, "conversion", m.date_conversion);
        }
        const parMembre = new Map<string, { id: string; full_name: string; evenements_vie_masques?: string[] | null }>(
          membres.map((m) => [m.id, m]),
        );
        for (const b of baptemes) {
          const m = parMembre.get(b.member_id);
          if (m) ajouter(m, "bapteme", b.date_bapteme);
        }
        resultats.sort((a, b) => a.jours_restants - b.jours_restants || a.date.localeCompare(b.date));
        return reply.send({ items: resultats });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // Masquer ses propres événements de vie (membre).
  app.patch(
    "/moi/evenements-vie-masques",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = z.object({ types: z.array(z.enum(TYPES_EVENEMENT_VIE)).max(4) }).safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const mien = await membreLie(db, req.session.userId);
        if (!mien) {
          return reply.code(404).send({ error: "not_found", message: "Aucune fiche membre n'est liée à ce compte." });
        }
        const { rows } = await db.query(
          `UPDATE members SET evenements_vie_masques = $2
            WHERE id = $1 AND church_id = $3 RETURNING id, evenements_vie_masques`,
          [mien, parsed.data.types, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Fiche membre introuvable." });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Consentements (US10 WhatsApp, US16 repli SMS) : explicites,
  //    révocables, jamais présumés. Aucun envoi réel ici : aucun
  //    fournisseur n'est choisi, l'envoi dépend d'une décision d'Axel.
  app.get(
    "/moi/consentements",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const mien = await membreLie(db, req.session.userId);
        if (!mien) {
          return reply.code(404).send({ error: "not_found", message: "Aucune fiche membre n'est liée à ce compte." });
        }
        const { rows } = await db.query(
          `SELECT whatsapp_consentement, sms_repli_consentement, evenements_vie_masques
             FROM members WHERE id = $1 AND church_id = $2`,
          [mien, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Fiche membre introuvable." });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/moi/consentements",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = z.object({
        whatsapp_consentement: z.boolean().optional(),
        sms_repli_consentement: z.boolean().optional(),
      }).safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const mien = await membreLie(db, req.session.userId);
        if (!mien) {
          return reply.code(404).send({ error: "not_found", message: "Aucune fiche membre n'est liée à ce compte." });
        }
        const { rows } = await db.query(
          `UPDATE members SET
             whatsapp_consentement = coalesce($2, whatsapp_consentement),
             sms_repli_consentement = coalesce($3, sms_repli_consentement)
            WHERE id = $1 AND church_id = $4
            RETURNING id, whatsapp_consentement, sms_repli_consentement`,
          [mien, parsed.data.whatsapp_consentement ?? null, parsed.data.sms_repli_consentement ?? null, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Fiche membre introuvable." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "consentements.mis_a_jour",
          details: { member_id: mien, ...parsed.data },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // Membres ayant consenti à WhatsApp, avec leur téléphone (admin et
  // responsable du culte seulement). Aucun message n'est envoyé ici.
  app.get(
    "/whatsapp/consentements",
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "responsable_culte")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, full_name, phone AS telephone FROM members
            WHERE church_id = $1 AND whatsapp_consentement = TRUE AND phone IS NOT NULL
            ORDER BY full_name ASC`,
          [req.session.churchId],
        );
        return reply.send({ items: rows, fournisseur: null, note: "Aucun fournisseur WhatsApp n'est branché : aucun envoi réel n'est possible tant qu'Axel n'a pas choisi le canal." });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Transparence financière agrégée côté membre (US8) : totaux par
  //    type et dépenses par poste, sans aucune ligne nominative. Une
  //    annexe voit les chiffres de sa mère ; la visibilité aux membres
  //    se règle par église (désactivée par défaut, bureau seulement). --
  app.get(
    "/moi/transparence",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const periode = (req.query as { periode?: string }).periode ?? new Date().toISOString().slice(0, 7);
        if (!/^\d{4}-\d{2}$/.test(periode)) {
          return reply.code(400).send({ error: "invalid_input", message: "Période au format AAAA-MM." });
        }
        const { rows: egliseRows } = await db.query<{ id: string; nom: string; parent_church_id: string | null }>(
          `SELECT id, name AS nom, parent_church_id FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        if (egliseRows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        }
        const referenceId = egliseRows[0].parent_church_id ?? egliseRows[0].id;
        const { rows: paramRows } = await db.query<{ transparence_visible_membres: boolean }>(
          `SELECT transparence_visible_membres FROM eglise_parametres WHERE church_id = $1`,
          [referenceId],
        );
        const visible = paramRows[0]?.transparence_visible_membres ?? false;
        const bureau = ["admin_eglise", "tresorier", "responsable_culte"].includes(req.session.role);
        if (!visible && !bureau) {
          return reply.code(403).send({ error: "forbidden", message: "La transparence financière n'est pas activée pour les membres de votre église." });
        }
        const { rows: nomRows } = await db.query<{ nom: string }>(
          `SELECT name AS nom FROM churches WHERE id = $1`,
          [referenceId],
        );
        const { rows: parType } = await db.query<{ type: string; total_fcfa: string; nombre: string }>(
          `SELECT type, coalesce(sum(amount_fcfa), 0)::text AS total_fcfa, count(*)::text AS nombre
             FROM contributions
            WHERE church_id = $1 AND status = 'confirme'
              AND to_char(created_at, 'YYYY-MM') = $2
            GROUP BY type ORDER BY type ASC`,
          [referenceId, periode],
        );
        const { rows: parPoste } = await db.query<{ poste: string; total_fcfa: string }>(
          `SELECT coalesce(pb.nom, 'Sans poste') AS poste, coalesce(sum(d.montant_fcfa), 0)::text AS total_fcfa
             FROM depenses d LEFT JOIN postes_budgetaires pb ON pb.id = d.poste_id
            WHERE d.church_id = $1 AND d.statut = 'payee'
              AND to_char(d.date_depense, 'YYYY-MM') = $2
            GROUP BY pb.nom ORDER BY total_fcfa DESC`,
          [referenceId, periode],
        );
        const totalRecettes = parType.filter((t) => t.type !== "depense").reduce((s, t) => s + Number(t.total_fcfa), 0);
        const totalDepenses = parType.filter((t) => t.type === "depense").reduce((s, t) => s + Number(t.total_fcfa), 0)
          + parPoste.reduce((s, p) => s + Number(p.total_fcfa), 0);
        return reply.send({
          eglise: nomRows[0]?.nom ?? "",
          periode,
          totaux_par_type: parType.map((t) => ({ type: t.type, total_fcfa: Number(t.total_fcfa), nombre: Number(t.nombre) })),
          depenses_par_poste: parPoste.map((p) => ({ poste: p.poste, total_fcfa: Number(p.total_fcfa) })),
          total_recettes_fcfa: totalRecettes,
          total_depenses_fcfa: totalDepenses,
          solde_fcfa: totalRecettes - totalDepenses,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Carte dans le portefeuille du téléphone (US9) : la carte
  //    (nom, matricule, code QR) en données exportables. Aucun compte
  //    Apple Wallet ni Google Wallet n'est branché : l'export est un
  //    fichier pass générique et l'écran indique le point ouvert. ------
  app.get(
    "/moi/carte/portefeuille",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const mien = await membreLie(db, req.session.userId);
        if (!mien) {
          return reply.code(404).send({ error: "not_found", message: "Aucune fiche membre n'est liée à ce compte." });
        }
        const { rows } = await db.query(
          `SELECT m.id, m.full_name, m.matricule, m.fonction, m.phone AS telephone,
                  c.name AS eglise_nom, c.code AS eglise_code
             FROM members m JOIN churches c ON c.id = m.church_id
            WHERE m.id = $1 AND m.church_id = $2`,
          [mien, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Carte introuvable." });
        }
        const m = rows[0];
        return reply.send({
          nom: m.full_name,
          matricule: m.matricule,
          fonction: m.fonction,
          telephone: m.telephone,
          eglise_nom: m.eglise_nom,
          eglise_code: m.eglise_code,
          qr_donnees: JSON.stringify({ type: "carte_membre", matricule: m.matricule, eglise: m.eglise_code }),
          compte_wallet: null,
          note: "Aucun compte Apple Wallet ni Google Wallet n'est branché : l'export est un fichier pass générique, sans coût engagé.",
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Lectures sensibles (US17) : toute lecture d'une donnée sensible
  //    passe par ici et est journalisée ; le membre voit qui a consulté
  //    sa fiche. ---------------------------------------------------------
  app.post(
    "/consultations-sensibles",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = z.object({
        ressource: z.string().min(2).max(80),
        ressource_id: uuid.optional(),
        action: z.string().max(40).default("lecture"),
      }).safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const { rows } = await db.query(
          `INSERT INTO consultations_sensibles (church_id, user_id, ressource, ressource_id, action)
           VALUES ($1, $2, $3, $4, $5) RETURNING *`,
          [req.session.churchId, req.session.userId, parsed.data.ressource, parsed.data.ressource_id ?? null, parsed.data.action],
        );
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/consultations-sensibles",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ADMIN)] },
    async (req, reply) => {
      try {
        const limit = Math.min(Math.max(Number((req.query as { limit?: string }).limit ?? 50) || 50, 1), 100);
        const offset = Math.max(Number((req.query as { offset?: string }).offset ?? 0) || 0, 0);
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM consultations_sensibles WHERE church_id = $1`,
          [req.session.churchId],
        );
        const { rows } = await db.query(
          `SELECT cs.*, u.full_name AS lecteur
             FROM consultations_sensibles cs LEFT JOIN users u ON u.id = cs.user_id
            WHERE cs.church_id = $1 ORDER BY cs.created_at DESC LIMIT $2 OFFSET $3`,
          [req.session.churchId, limit, offset],
        );
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/moi/consultations",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const mien = await membreLie(db, req.session.userId);
        const { rows } = await db.query(
          `SELECT cs.*, u.full_name AS lecteur
             FROM consultations_sensibles cs LEFT JOIN users u ON u.id = cs.user_id
            WHERE cs.church_id = $1 AND cs.ressource = 'membre' AND cs.ressource_id = $2
            ORDER BY cs.created_at DESC LIMIT 50`,
          [req.session.churchId, mien],
        );
        return reply.send({ items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
