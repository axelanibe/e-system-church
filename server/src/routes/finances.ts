import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import {
  READ_ALL,
  WRITE_FINANCES,
  WRITE_STD,
  existsInChurch,
  invalidInput,
  registerCrud,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { requireModule } from "../modules.js";

/**
 * Module 4 — Finances (compléter) : postes budgétaires, budgets annuels,
 * dépenses avec validation en deux temps (trésorier puis pasteur),
 * mouvements de caisse, rapports financiers détaillés (par poste, par mois,
 * par branche pour la mère).
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

/** Transitions autorisées pour une dépense (rôle requis). */
const DEPENSE_TRANSITIONS: Record<string, { from: string; roles: string[] }> = {
  validee_tresorier: { from: "soumise", roles: ["tresorier", "admin_eglise"] },
  validee_pasteur: { from: "validee_tresorier", roles: ["admin_eglise"] },
  payee: { from: "validee_pasteur", roles: ["tresorier", "admin_eglise"] },
  refusee: { from: "soumise", roles: ["tresorier", "admin_eglise"] },
};

export function registerFinancesRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/postes-budgetaires",
    module: "budget",
    table: "postes_budgetaires",
    columns: ["nom", "categorie", "description"],
    createSchema: z.object({
      nom: z.string().min(2).max(120),
      categorie: z.enum(["recette", "depense"]),
      description: z.string().max(500).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_FINANCES,
    audit: "poste_budgetaire",
    filters: { categorie: "categorie" },
    searchColumn: "nom",
  });

  registerCrud(app, db, {
    base: "/budgets",
    module: "budget",
    table: "budgets",
    columns: ["poste_id", "annee", "montant_prevu"],
    createSchema: z.object({
      poste_id: uuid,
      annee: z.number().int().min(2000).max(2100),
      montant_prevu: z.number().int().min(0).max(100_000_000),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_FINANCES,
    audit: "budget",
    filters: { poste_id: "poste_id", annee: "annee" },
    orderBy: "annee DESC",
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "postes_budgetaires", churchId, data.poste_id as string))) {
        return "Poste budgétaire introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/depenses",
    module: "budget",
    table: "depenses",
    columns: ["poste_id", "montant_fcfa", "motif", "justificatif_ref", "statut", "date_depense"],
    createSchema: z.object({
      poste_id: uuid.optional(),
      montant_fcfa: z.number().int().positive().max(100_000_000),
      motif: z.string().min(2).max(500),
      justificatif_ref: z.string().max(120).optional(),
      statut: z.enum(["soumise", "validee_tresorier", "validee_pasteur", "payee", "refusee"]).default("soumise"),
      date_depense: z.string().regex(dateRe, "Date au format AAAA-MM-JJ.").optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_FINANCES,
    audit: "depense",
    filters: { poste_id: "poste_id", statut: "statut" },
    orderBy: "date_depense DESC, created_at DESC",
    validate: async (db2, churchId, data) => {
      if (data.poste_id && !(await existsInChurch(db2, "postes_budgetaires", churchId, data.poste_id as string))) {
        return "Poste budgétaire introuvable dans votre église.";
      }
      return null;
    },
  });

  // -- Validation d'une dépense en deux temps. -------------------------------
  const statutSchema = z.object({
    statut: z.enum(["validee_tresorier", "validee_pasteur", "payee", "refusee"]),
  });
  app.patch(
    "/depenses/:id/statut",
    { preHandler: [requireAuth(db), requireModule(db, "budget"), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = statutSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const cible = parsed.data.statut;
      const regle = DEPENSE_TRANSITIONS[cible];
      if (!regle.roles.includes(req.session.role)) {
        return reply.code(403).send({
          error: "forbidden",
          message: `Cette étape exige le rôle ${regle.roles.join(" ou ")}.`,
        });
      }
      try {
        const { rows } = await db.query(
          `UPDATE depenses SET statut = $3, valide_par = $4
            WHERE id = $1 AND church_id = $2 AND statut = $5
            RETURNING id, montant_fcfa, statut`,
          [
            (req.params as { id: string }).id,
            req.session.churchId,
            cible,
            req.session.userId,
            regle.from,
          ],
        );
        if (rows.length === 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Dépense introuvable, ou étape précédente non validée.",
          });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: `depense.${cible}`,
          details: { depense_id: rows[0].id, montant_fcfa: rows[0].montant_fcfa },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  registerCrud(app, db, {
    base: "/caisse-mouvements",
    module: "budget",
    table: "caisse_mouvements",
    columns: ["type", "montant_fcfa", "motif", "reference"],
    createSchema: z.object({
      type: z.enum(["entree", "sortie"]),
      montant_fcfa: z.number().int().positive().max(100_000_000),
      motif: z.string().min(2).max(500),
      reference: z.string().max(120).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_FINANCES,
    audit: "caisse",
    filters: { type: "type" },
  });

  // -- Solde de caisse : entrées − sorties. ----------------------------------
  app.get(
    "/finances/caisse",
    { preHandler: [requireAuth(db), requireModule(db, "budget"), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT coalesce(sum(CASE WHEN type = 'entree' THEN montant_fcfa ELSE 0 END), 0)::int AS entrees,
                  coalesce(sum(CASE WHEN type = 'sortie' THEN montant_fcfa ELSE 0 END), 0)::int AS sorties,
                  coalesce(sum(CASE WHEN type = 'entree' THEN montant_fcfa ELSE -montant_fcfa END), 0)::int AS solde,
                  count(*)::int AS mouvements
             FROM caisse_mouvements WHERE church_id = $1`,
          [req.session.churchId],
        );
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rapport financier détaillé : par mois, par poste (budget vs réalisé),
  //    et pour la mère, par branche (totaux de chaque sous-église directe). --
  const rapportQuerySchema = z.object({
    from: z.string().regex(dateRe).optional(),
    to: z.string().regex(dateRe).optional(),
    annee: z.coerce.number().int().min(2000).max(2100).optional(),
  });
  app.get(
    "/finances/rapport",
    { preHandler: [requireAuth(db), requireModule(db, "budget"), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      const parsed = rapportQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { from, to, annee } = parsed.data;
      const year = annee ?? new Date().getFullYear();
      try {
        const conditions = [`c.church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (from) {
          values.push(from);
          conditions.push(`c.created_at >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(`c.created_at < ($${values.length}::date + interval '1 day')`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const { rows: parMois } = await db.query(
          `SELECT to_char(c.created_at, 'YYYY-MM') AS mois,
                  c.type,
                  coalesce(sum(c.amount_fcfa), 0)::int AS total_fcfa,
                  count(*)::int AS nombre
             FROM contributions c ${where} AND c.status = 'confirme'
            GROUP BY mois, c.type
            ORDER BY mois ASC, c.type ASC`,
          values,
        );
        const { rows: parPoste } = await db.query(
          `SELECT p.nom AS poste, p.categorie,
                  coalesce(b.montant_prevu, 0)::int AS budget_fcfa,
                  coalesce(sum(d.montant_fcfa) FILTER (WHERE d.statut IN ('validee_pasteur','payee')), 0)::int AS realise_fcfa
             FROM postes_budgetaires p
             LEFT JOIN budgets b ON b.poste_id = p.id AND b.annee = $2
             LEFT JOIN depenses d ON d.poste_id = p.id
            WHERE p.church_id = $1
            GROUP BY p.nom, p.categorie, b.montant_prevu
            ORDER BY p.categorie ASC, p.nom ASC`,
          [req.session.churchId, year],
        );
        const { rows: parBranche } = await db.query(
          `SELECT eglise_id, eglise_nom, membres_actifs, nombre_contributions, total_fcfa
             FROM v_rapports_consolides
            WHERE eglise_mere_id = $1
            ORDER BY eglise_nom ASC`,
          [req.session.churchId],
        );
        return reply.send({ par_mois: parMois, par_poste: parPoste, par_branche: parBranche });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
