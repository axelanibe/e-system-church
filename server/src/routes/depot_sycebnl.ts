import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import {
  invalidInput,
  registerCrud,
  WRITE_ADMIN,
  WRITE_FINANCES,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Dépôt SYCEBNL (tranche dépôt SYCEBNL, migration 043).
 *
 * Quatre registres qui rendent les états SYCEBNL complets
 * (immobilisations, dettes, créances, notes annexes), le seuil et
 * l'échéance du dépôt, et le suivi du dépôt par église et par exercice.
 *
 * Il n'existe pas d'API DGI : le dépôt se fait par l'église sur
 * e-impots.gouv.ci avec son NCC. L'application prépare, exporte et
 * suit, elle ne dépose pas elle-même, et chaque écran le dit. Le
 * statut « déposé » ne se met que par un geste explicite de l'admin,
 * jamais automatiquement.
 *
 * Ressources annuelles de l'exercice civil : contributions confirmées
 * (dîmes, offrandes, dons, cotisations). Seuil de dépôt : 50 000 000
 * FCFA. Échéance : 30 mai de l'année suivante ; premier dépôt le
 * 30 mai 2027 pour l'exercice 2026. En dessous du seuil, aucun dépôt
 * fiscal SYCEBNL n'est imposé.
 */

export const SEUIL_DEPOT_SYCEBNL = 50000000;

const dateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.");

export function registerDepotSycebnlRoutes(app: FastifyInstance, db: Pool) {
  // Écriture réservée à l'admin de l'église ; lecture admin et
  // trésorier, comme les états SYCEBNL. Les membres ne voient pas ces
  // registres financiers.
  registerCrud(app, db, {
    base: "/immobilisations",
    table: "immobilisations",
    columns: [
      "libelle",
      "date_acquisition",
      "valeur_acquisition",
      "amortissement_cumule",
    ],
    createSchema: z.object({
      libelle: z.string().min(2).max(200),
      date_acquisition: dateSchema,
      valeur_acquisition: z.number().int().positive().max(10000000000),
      amortissement_cumule: z.number().int().min(0).default(0),
    }),
    readRoles: WRITE_FINANCES,
    writeRoles: WRITE_ADMIN,
    audit: "immobilisation",
    searchColumn: "libelle",
    orderBy: "date_acquisition DESC, created_at DESC",
    validate: async (_db2, _churchId, data) => {
      const valeur = data.valeur_acquisition as number | undefined;
      const amortissement = data.amortissement_cumule as number | undefined;
      if (
        valeur !== undefined &&
        amortissement !== undefined &&
        amortissement > valeur
      ) {
        return "L’amortissement cumulé ne peut pas dépasser la valeur d’acquisition.";
      }
      return null;
    },
    validateUpdate: async (_db2, _churchId, id, data) => {
      const { rows } = await _db2.query(
        `SELECT valeur_acquisition, amortissement_cumule
           FROM immobilisations WHERE id = $1 AND church_id = $2`,
        [id, _churchId],
      );
      if (rows.length === 0) return null;
      const valeur =
        (data.valeur_acquisition as number | undefined) ??
        Number(rows[0].valeur_acquisition);
      const amortissement =
        (data.amortissement_cumule as number | undefined) ??
        Number(rows[0].amortissement_cumule);
      if (amortissement > valeur) {
        return "L’amortissement cumulé ne peut pas dépasser la valeur d’acquisition.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/dettes",
    table: "dettes",
    columns: ["libelle", "montant", "echeance", "statut"],
    createSchema: z.object({
      libelle: z.string().min(2).max(200),
      montant: z.number().int().positive().max(10000000000),
      echeance: dateSchema.optional(),
      statut: z.enum(["en_cours", "soldee"]).default("en_cours"),
    }),
    readRoles: WRITE_FINANCES,
    writeRoles: WRITE_ADMIN,
    audit: "dette",
    filters: { statut: "statut" },
    searchColumn: "libelle",
    orderBy: "echeance ASC NULLS LAST, created_at DESC",
  });

  registerCrud(app, db, {
    base: "/creances",
    table: "creances",
    columns: ["libelle", "montant", "echeance", "statut"],
    createSchema: z.object({
      libelle: z.string().min(2).max(200),
      montant: z.number().int().positive().max(10000000000),
      echeance: dateSchema.optional(),
      statut: z.enum(["en_cours", "soldee"]).default("en_cours"),
    }),
    readRoles: WRITE_FINANCES,
    writeRoles: WRITE_ADMIN,
    audit: "creance",
    filters: { statut: "statut" },
    searchColumn: "libelle",
    orderBy: "echeance ASC NULLS LAST, created_at DESC",
  });

  registerCrud(app, db, {
    base: "/notes-annexes",
    table: "notes_annexes",
    columns: ["titre", "contenu", "exercice"],
    createSchema: z.object({
      titre: z.string().min(2).max(200),
      contenu: z.string().min(1).max(5000),
      exercice: z.number().int().min(2000).max(2100),
    }),
    readRoles: WRITE_FINANCES,
    writeRoles: WRITE_ADMIN,
    audit: "note_annexe",
    filters: { exercice: "exercice" },
    searchColumn: "titre",
    orderBy: "exercice DESC, created_at DESC",
  });

  const depotQuerySchema = z.object({
    annee: z.coerce.number().int().min(2000).max(2100).optional(),
  });

  // -- Dépôt : ressources, seuil, échéance, suivi --------------------------
  app.get(
    "/sycebnl/depot",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = depotQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const year = parsed.data.annee ?? new Date().getFullYear();
      try {
        const { rows: ressourcesRows } = await db.query(
          `SELECT coalesce(sum(amount_fcfa), 0)::int AS total
             FROM contributions
            WHERE church_id = $1 AND status = 'confirme'
              AND type IN ('dime', 'offrande', 'don', 'cotisation')
              AND created_at >= $2::date
              AND created_at < ($2::date + interval '1 year')`,
          [req.session.churchId, `${year}-01-01`],
        );
        const ressources = Number(ressourcesRows[0]?.total ?? 0);
        const { rows: suiviRows } = await db.query(
          `SELECT exercice, statut,
                  to_char(date_depot, 'YYYY-MM-DD') AS date_depot,
                  reference
             FROM depots_sycebnl
            WHERE church_id = $1 AND exercice = $2`,
          [req.session.churchId, year],
        );
        return reply.send({
          annee: year,
          ressources,
          seuil: SEUIL_DEPOT_SYCEBNL,
          requis: ressources >= SEUIL_DEPOT_SYCEBNL,
          echeance: `${year + 1}-05-30`,
          suivi: suiviRows[0] ?? null,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  const depotSuiviSchema = z.object({
    annee: z.number().int().min(2000).max(2100),
    statut: z.enum(["a_preparer", "pret", "depose"]),
    date_depot: dateSchema.optional(),
    reference: z.string().max(100).optional(),
  });

  app.patch(
    "/sycebnl/depot",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ADMIN)] },
    async (req, reply) => {
      const parsed = depotSuiviSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { annee, statut, date_depot, reference } = parsed.data;
      if (statut === "depose" && !date_depot) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Indiquez la date du dépôt pour marquer l’exercice comme déposé.",
        });
      }
      try {
        const { rows } = await db.query(
          `INSERT INTO depots_sycebnl
               (church_id, exercice, statut, date_depot, reference)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (church_id, exercice) DO UPDATE SET
               statut = EXCLUDED.statut,
               date_depot = COALESCE(EXCLUDED.date_depot, depots_sycebnl.date_depot),
               reference = COALESCE(EXCLUDED.reference, depots_sycebnl.reference)
             RETURNING exercice, statut,
               to_char(date_depot, 'YYYY-MM-DD') AS date_depot, reference`,
          [
            req.session.churchId,
            annee,
            statut,
            date_depot ?? null,
            reference ?? null,
          ],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "depot.sycebnl.maj",
          details: { exercice: annee, statut },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
