import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { existsInChurch, READ_ALL, WRITE_FINANCES, invalidInput } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import {
  formaterMontant,
  genererRapportPdf,
  type SectionRapport,
} from "../pdf.js";

/**
 * Tranche dépenses prévisibles — plan comptable des dépenses (Lot A).
 *
 * Nouveau fichier : ne touche ni à finances.ts ni à contributions.ts
 * (Lot B). Les tables sont créées par la migration 031.
 *
 * - GET  /categories-depenses — les dix catégories globales, par code.
 * - POST /plan-comptable/postes — crée un poste avec catégorie comptable
 *        et marqueur récurrente ou ponctuelle.
 * - PATCH /plan-comptable/postes/:id — change la catégorie et le marqueur.
 * - GET  /budgets-mensuels — budgets mensuels (année, mois, poste).
 * - POST /budgets-mensuels — crée ou remplace le budget mensuel d'un poste.
 * - DELETE /budgets-mensuels/:id — supprime un budget mensuel.
 * - POST /plan-comptable/depenses — crée une dépense avec tous les champs
 *        du plan (référence auto DEP-AAAA-NNNN, département, mode de
 *        paiement, fournisseur, responsables, devise). Le statut et la
 *        validation en deux temps restent sur /depenses (Lot B).
 * - GET  /plan-comptable/suivi-mensuel — prévu mensuel contre réel, par
 *        catégorie et par poste, mois en cours, avec dépassement.
 * - GET  /plan-comptable/rapport — mêmes chiffres, mensuel (mois donné)
 *        ou annuel (mois absent), avec le détail des dépenses.
 * - GET  /plan-comptable/rapport/pdf — le même rapport en PDF.
 *
 * Règles : le réel compte les dépenses hors refusées (comme le tableau
 * de bord) ; un dépassement est signalé quand le réel dépasse un prévu
 * mensuel défini ; sans budget mensuel, le prévu vaut 0 et le poste est
 * marqué sans budget mensuel. La référence est fixée à la création et
 * ne change plus, même si la date est modifiée ensuite.
 */

const dateRe = /^\d{4}-\d{2}-\d{2}$/;

const MODES_PAIEMENT = [
  "especes",
  "wave",
  "orange_money",
  "mtn_money",
  "virement",
  "cheque",
] as const;

const anneeMoisQuerySchema = z.object({
  annee: z.coerce.number().int().min(2000).max(2100).optional(),
  mois: z.coerce.number().int().min(1).max(12).optional(),
});

const budgetsMensuelsQuerySchema = z.object({
  annee: z.coerce.number().int().min(2000).max(2100).optional(),
  mois: z.coerce.number().int().min(1).max(12).optional(),
  poste_id: z.string().uuid().optional(),
});

const creerPosteSchema = z.object({
  nom: z.string().min(2).max(120),
  categorie: z.enum(["recette", "depense"]),
  description: z.string().max(500).optional(),
  categorie_id: z.string().uuid().optional(),
  est_recurrente: z.boolean().optional(),
});

const modifierPosteSchema = z.object({
  categorie_id: z.string().uuid().nullable().optional(),
  est_recurrente: z.boolean().optional(),
});

const creerBudgetMensuelSchema = z.object({
  poste_id: z.string().uuid(),
  annee: z.number().int().min(2000).max(2100),
  mois: z.number().int().min(1).max(12),
  montant_prevu: z.number().int().min(0).max(100_000_000),
});

const creerDepenseCompleteSchema = z.object({
  poste_id: z.string().uuid().optional(),
  montant_fcfa: z.number().int().positive().max(100_000_000),
  motif: z.string().min(2).max(500),
  justificatif_ref: z.string().max(120).optional(),
  date_depense: z.string().regex(dateRe, "Date au format AAAA-MM-JJ.").optional(),
  departement_id: z.string().uuid().optional(),
  mode_paiement: z.enum(MODES_PAIEMENT).optional(),
  fournisseur_beneficiaire: z.string().max(200).optional(),
  responsable_depense: z.string().max(200).optional(),
  responsable_autorisation: z.string().max(200).optional(),
  devise: z.string().min(2).max(10).optional(),
});

/** Prochain numéro de référence DEP-AAAA-NNNN pour une église et une année. */
async function prochaineReferenceDepense(
  client: Pool | PoolClient,
  churchId: string,
  annee: number,
): Promise<string> {
  const { rows } = await client.query(
    `SELECT coalesce(max(CAST(substr(reference, 10) AS int)), 0)::int AS n
       FROM depenses WHERE church_id = $1 AND reference LIKE $2`,
    [churchId, `DEP-${annee}-%`],
  );
  return `DEP-${annee}-${String(rows[0].n + 1).padStart(4, "0")}`;
}

function bornesPeriode(
  annee: number,
  mois?: number,
): { debut: string; fin: string } {
  if (mois !== undefined) {
    const debut = `${annee}-${String(mois).padStart(2, "0")}-01`;
    const finMois = mois === 12 ? 1 : mois + 1;
    const finAnnee = mois === 12 ? annee + 1 : annee;
    const fin = `${finAnnee}-${String(finMois).padStart(2, "0")}-01`;
    return { debut, fin };
  }
  return { debut: `${annee}-01-01`, fin: `${annee + 1}-01-01` };
}

interface LigneSuivi {
  poste_id: string | null;
  poste: string | null;
  categorie_code: string | null;
  categorie_nom: string | null;
  recurrente: boolean | null;
  prevu_fcfa: number;
  reel_fcfa: number;
  budget_defini: boolean;
}

interface DonneesRapport {
  annee: number;
  mois: number | null;
  par_categories: LigneSuivi[];
  par_postes: LigneSuivi[];
  depenses: Record<string, unknown>[];
  total_prevu_fcfa: number;
  total_reel_fcfa: number;
}

/** Données du rapport mensuel ou annuel : mêmes chiffres pour le JSON,
 *  le PDF et l'Excel côté application. */
async function chargerRapport(
  db: Pool,
  churchId: string,
  annee: number,
  mois?: number,
): Promise<DonneesRapport> {
  const { debut, fin } = bornesPeriode(annee, mois);
  const { rows: parPostes } = await db.query(
    `SELECT p.id AS poste_id, p.nom AS poste, p.est_recurrente AS recurrente,
            cat.code AS categorie_code, cat.nom AS categorie_nom,
            coalesce((
              SELECT sum(bm.montant_prevu) FROM budgets_mensuels bm
               WHERE bm.poste_id = p.id AND bm.annee = $2
                 AND ($3::int IS NULL OR bm.mois = $3)
            ), 0)::int AS prevu_fcfa,
            coalesce(sum(d.montant_fcfa) FILTER (WHERE d.statut <> 'refusee'), 0)::int AS reel_fcfa,
            EXISTS (
              SELECT 1 FROM budgets_mensuels bm
               WHERE bm.poste_id = p.id AND bm.annee = $2
                 AND ($3::int IS NULL OR bm.mois = $3)
            ) AS budget_defini
       FROM postes_budgetaires p
       LEFT JOIN categories_depenses cat ON cat.id = p.categorie_id
       LEFT JOIN depenses d ON d.poste_id = p.id
         AND d.date_depense >= $4::date AND d.date_depense < $5::date
      WHERE p.church_id = $1 AND p.categorie = 'depense'
      GROUP BY p.id, p.nom, p.est_recurrente, cat.code, cat.nom
      ORDER BY cat.code NULLS LAST, p.nom ASC`,
    [churchId, annee, mois ?? null, debut, fin],
  );
  const lignes: LigneSuivi[] = parPostes.map((r) => ({
    poste_id: r.poste_id as string,
    poste: r.poste as string,
    categorie_code: r.categorie_code as string | null,
    categorie_nom: r.categorie_nom as string | null,
    recurrente: r.recurrente as boolean | null,
    prevu_fcfa: Number(r.prevu_fcfa),
    reel_fcfa: Number(r.reel_fcfa),
    budget_defini: Boolean(r.budget_defini),
  }));
  const parCategoriesMap = new Map<string, LigneSuivi>();
  for (const ligne of lignes) {
    const cle = ligne.categorie_code ?? "sans";
    const existante = parCategoriesMap.get(cle);
    if (existante) {
      existante.prevu_fcfa += ligne.prevu_fcfa;
      existante.reel_fcfa += ligne.reel_fcfa;
      existante.budget_defini = existante.budget_defini || ligne.budget_defini;
    } else {
      parCategoriesMap.set(cle, {
        poste_id: null,
        poste: null,
        categorie_code: ligne.categorie_code,
        categorie_nom: ligne.categorie_nom ?? "Sans catégorie",
        recurrente: null,
        prevu_fcfa: ligne.prevu_fcfa,
        reel_fcfa: ligne.reel_fcfa,
        budget_defini: ligne.budget_defini,
      });
    }
  }
  const { rows: depenses } = await db.query(
    `SELECT d.reference, d.date_depense, d.motif, d.montant_fcfa, d.statut,
            d.mode_paiement, d.fournisseur_beneficiaire, d.devise,
            p.nom AS poste, cat.nom AS categorie_nom,
            dep.nom AS departement_nom
       FROM depenses d
       LEFT JOIN postes_budgetaires p ON p.id = d.poste_id
       LEFT JOIN categories_depenses cat ON cat.id = p.categorie_id
       LEFT JOIN departements dep ON dep.id = d.departement_id
      WHERE d.church_id = $1
        AND d.date_depense >= $2::date AND d.date_depense < $3::date
      ORDER BY d.date_depense DESC, d.created_at DESC`,
    [churchId, debut, fin],
  );
  return {
    annee,
    mois: mois ?? null,
    par_categories: [...parCategoriesMap.values()],
    par_postes: lignes,
    depenses,
    total_prevu_fcfa: lignes.reduce((s, l) => s + l.prevu_fcfa, 0),
    total_reel_fcfa: lignes.reduce((s, l) => s + l.reel_fcfa, 0),
  };
}

function libellePeriode(annee: number, mois?: number | null): string {
  const noms = [
    "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
    "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre",
  ];
  if (mois !== undefined && mois !== null) return `${noms[mois - 1]} ${annee}`;
  return `Année ${annee}`;
}

function dateJour(iso: string): string {
  const [a, m, j] = iso.split("-");
  return `${j}/${m}/${a}`;
}

function dateValeur(v: unknown): string {
  const d = v instanceof Date ? v : new Date(String(v));
  return dateJour(d.toISOString().slice(0, 10));
}

function nomEglise(db: Pool, churchId: string): Promise<string> {
  return db
    .query(`SELECT name, code FROM churches WHERE id = $1`, [churchId])
    .then(({ rows }) =>
      rows.length === 0 ? "Église" : `${rows[0].name} (${rows[0].code})`,
    );
}

export function registerPlanComptableRoutes(app: FastifyInstance, db: Pool) {
  // -- Catégories comptables : les dix catégories globales. -----------------
  app.get(
    "/categories-depenses",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, code, nom, description FROM categories_depenses ORDER BY code ASC`,
        );
        return reply.send(rows);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Postes : création avec catégorie comptable et marqueur récurrente. ---
  app.post(
    "/plan-comptable/postes",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = creerPosteSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { nom, categorie, description, categorie_id, est_recurrente } =
        parsed.data;
      try {
        if (categorie_id !== undefined) {
          if (categorie !== "depense") {
            return reply.code(400).send({
              error: "invalid_input",
              message: "Une catégorie comptable ne se rattache qu'à un poste de dépense.",
            });
          }
          const { rows } = await db.query(
            `SELECT 1 FROM categories_depenses WHERE id = $1`,
            [categorie_id],
          );
          if (rows.length === 0) {
            return reply.code(400).send({
              error: "invalid_reference",
              message: "Catégorie comptable introuvable.",
            });
          }
        }
        const { rows } = await db.query(
          `INSERT INTO postes_budgetaires (church_id, nom, categorie, description, categorie_id, est_recurrente)
           VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
          [
            req.session.churchId,
            nom,
            categorie,
            categorie_id ?? null,
            est_recurrente ?? false,
          ],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "poste_budgetaire.plan_comptable_cree",
          details: { poste_id: rows[0].id, nom },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Postes : changement de catégorie et de marqueur récurrente. ----------
  app.patch(
    "/plan-comptable/postes/:id",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = modifierPosteSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { id } = req.params as { id: string };
      try {
        const { rows: existants } = await db.query(
          `SELECT * FROM postes_budgetaires WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (existants.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Poste budgétaire introuvable.",
          });
        }
        const poste = existants[0];
        if (parsed.data.categorie_id !== undefined && parsed.data.categorie_id !== null) {
          if (poste.categorie !== "depense") {
            return reply.code(400).send({
              error: "invalid_input",
              message: "Une catégorie comptable ne se rattache qu'à un poste de dépense.",
            });
          }
          const { rows } = await db.query(
            `SELECT 1 FROM categories_depenses WHERE id = $1`,
            [parsed.data.categorie_id],
          );
          if (rows.length === 0) {
            return reply.code(400).send({
              error: "invalid_reference",
              message: "Catégorie comptable introuvable.",
            });
          }
        }
        const champs: string[] = [];
        const valeurs: unknown[] = [];
        if (parsed.data.categorie_id !== undefined) {
          valeurs.push(parsed.data.categorie_id);
          champs.push(`categorie_id = $${valeurs.length}`);
        }
        if (parsed.data.est_recurrente !== undefined) {
          valeurs.push(parsed.data.est_recurrente);
          champs.push(`est_recurrente = $${valeurs.length}`);
        }
        if (champs.length === 0) return reply.send(poste);
        valeurs.push(id, req.session.churchId);
        const { rows } = await db.query(
          `UPDATE postes_budgetaires SET ${champs.join(", ")}
            WHERE id = $${valeurs.length - 1} AND church_id = $${valeurs.length}
            RETURNING *`,
          valeurs,
        );
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Budgets mensuels : lecture. -------------------------------------------
  app.get(
    "/budgets-mensuels",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = budgetsMensuelsQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { annee, mois, poste_id } = parsed.data;
      try {
        const conditions = [`church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (annee !== undefined) {
          values.push(annee);
          conditions.push(`annee = $${values.length}`);
        }
        if (mois !== undefined) {
          values.push(mois);
          conditions.push(`mois = $${values.length}`);
        }
        if (poste_id !== undefined) {
          values.push(poste_id);
          conditions.push(`poste_id = $${values.length}`);
        }
        const { rows } = await db.query(
          `SELECT * FROM budgets_mensuels WHERE ${conditions.join(" AND ")}
           ORDER BY annee DESC, mois DESC, poste_id ASC`,
          values,
        );
        return reply.send(rows);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Budgets mensuels : création ou remplacement. ---------------------------
  app.post(
    "/budgets-mensuels",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = creerBudgetMensuelSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { poste_id, annee, mois, montant_prevu } = parsed.data;
      try {
        if (
          !(await existsInChurch(db, "postes_budgetaires", req.session.churchId, poste_id))
        ) {
          return reply.code(400).send({
            error: "invalid_reference",
            message: "Poste budgétaire introuvable dans votre église.",
          });
        }
        const { rows } = await db.query(
          `INSERT INTO budgets_mensuels (church_id, poste_id, annee, mois, montant_prevu)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (church_id, poste_id, annee, mois)
           DO UPDATE SET montant_prevu = EXCLUDED.montant_prevu
           RETURNING *`,
          [req.session.churchId, poste_id, annee, mois, montant_prevu],
        );
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Budgets mensuels : suppression. ----------------------------------------
  app.delete(
    "/budgets-mensuels/:id",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const { id } = req.params as { id: string };
      try {
        const { rowCount } = await db.query(
          `DELETE FROM budgets_mensuels WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (rowCount === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Budget mensuel introuvable.",
          });
        }
        return reply.code(204).send();
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Dépenses : création complète, référence auto DEP-AAAA-NNNN. -----------
  app.post(
    "/plan-comptable/depenses",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = creerDepenseCompleteSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      const dateDepense =
        data.date_depense ?? new Date().toISOString().slice(0, 10);
      const annee = Number(dateDepense.slice(0, 4));
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        if (data.poste_id !== undefined) {
          const { rows } = await client.query(
            `SELECT 1 FROM postes_budgetaires WHERE id = $1 AND church_id = $2`,
            [data.poste_id, req.session.churchId],
          );
          if (rows.length === 0) {
            await client.query("ROLLBACK");
            return reply.code(400).send({
              error: "invalid_reference",
              message: "Poste budgétaire introuvable dans votre église.",
            });
          }
        }
        if (data.departement_id !== undefined) {
          const { rows } = await client.query(
            `SELECT 1 FROM departements WHERE id = $1 AND church_id = $2`,
            [data.departement_id, req.session.churchId],
          );
          if (rows.length === 0) {
            await client.query("ROLLBACK");
            return reply.code(400).send({
              error: "invalid_reference",
              message: "Département introuvable dans votre église.",
            });
          }
        }
        const reference = await prochaineReferenceDepense(
          client,
          req.session.churchId,
          annee,
        );
        const { rows } = await client.query(
          `INSERT INTO depenses (church_id, poste_id, montant_fcfa, motif,
              justificatif_ref, statut, demande_par, date_depense, reference,
              departement_id, mode_paiement, fournisseur_beneficiaire,
              responsable_depense, responsable_autorisation, devise)
           VALUES ($1, $2, $3, $4, $5, 'soumise', $6, $7, $8, $9, $10, $11, $12, $13, $14)
           RETURNING *`,
          [
            req.session.churchId,
            data.poste_id ?? null,
            data.montant_fcfa,
            data.motif,
            data.justificatif_ref ?? null,
            req.session.userId,
            dateDepense,
            reference,
            data.departement_id ?? null,
            data.mode_paiement ?? null,
            data.fournisseur_beneficiaire ?? null,
            data.responsable_depense ?? null,
            data.responsable_autorisation ?? null,
            data.devise ?? "FCFA",
          ],
        );
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "depense.plan_comptable_creee",
          details: { depense_id: rows[0].id, reference },
        });
        await client.query("COMMIT");
        return reply.code(201).send(rows[0]);
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  // -- Suivi mensuel : prévu contre réel, par catégorie et par poste. --------
  app.get(
    "/plan-comptable/suivi-mensuel",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = anneeMoisQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const maintenant = new Date();
      const annee = parsed.data.annee ?? maintenant.getFullYear();
      const mois = parsed.data.mois ?? maintenant.getMonth() + 1;
      try {
        const rapport = await chargerRapport(db, req.session.churchId, annee, mois);
        return reply.send({
          annee: rapport.annee,
          mois: rapport.mois,
          par_categories: rapport.par_categories,
          par_postes: rapport.par_postes,
          total_prevu_fcfa: rapport.total_prevu_fcfa,
          total_reel_fcfa: rapport.total_reel_fcfa,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rapport mensuel ou annuel (JSON) : mêmes chiffres que le PDF. ---------
  app.get(
    "/plan-comptable/rapport",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = anneeMoisQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const annee = parsed.data.annee ?? new Date().getFullYear();
      try {
        const rapport = await chargerRapport(
          db,
          req.session.churchId,
          annee,
          parsed.data.mois,
        );
        return reply.send(rapport);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rapport mensuel ou annuel (PDF). ---------------------------------------
  app.get(
    "/plan-comptable/rapport/pdf",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = anneeMoisQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const annee = parsed.data.annee ?? new Date().getFullYear();
      const mois = parsed.data.mois;
      try {
        const egliseNom = await nomEglise(db, req.session.churchId);
        const rapport = await chargerRapport(db, req.session.churchId, annee, mois);
        const sections: SectionRapport[] = [
          {
            titre: "Par catégorie",
            colonnes: [
              { titre: "Catégorie", largeur: 200 },
              { titre: "Prévu", largeur: 145, alignerDroite: true },
              { titre: "Réel", largeur: 150, alignerDroite: true },
            ],
            lignes: rapport.par_categories.map((l) => [
              `${l.categorie_code ?? "—"} ${l.categorie_nom ?? ""}`.trim(),
              formaterMontant(l.prevu_fcfa),
              formaterMontant(l.reel_fcfa),
            ]),
            total: [
              "Total",
              formaterMontant(rapport.total_prevu_fcfa),
              formaterMontant(rapport.total_reel_fcfa),
            ],
            messageVide: "Aucun poste de dépense pour l'instant.",
          },
          {
            titre: "Par poste",
            colonnes: [
              { titre: "Poste", largeur: 165 },
              { titre: "Catégorie", largeur: 80 },
              { titre: "Prévu", largeur: 125, alignerDroite: true },
              { titre: "Réel", largeur: 125, alignerDroite: true },
            ],
            lignes: rapport.par_postes.map((l) => [
              String(l.poste ?? "—"),
              String(l.categorie_code ?? "—"),
              formaterMontant(l.prevu_fcfa),
              formaterMontant(l.reel_fcfa),
            ]),
            total: [
              "Total",
              "",
              formaterMontant(rapport.total_prevu_fcfa),
              formaterMontant(rapport.total_reel_fcfa),
            ],
            messageVide: "Aucun poste de dépense pour l'instant.",
          },
          {
            titre: "Dépenses",
            colonnes: [
              { titre: "Référence", largeur: 95 },
              { titre: "Date", largeur: 70 },
              { titre: "Poste", largeur: 100 },
              { titre: "Motif", largeur: 130 },
              { titre: "Montant", largeur: 100, alignerDroite: true },
            ],
            lignes: rapport.depenses.map((d) => [
              String((d as { reference?: unknown }).reference ?? "—"),
              dateValeur((d as { date_depense?: unknown }).date_depense),
              String((d as { poste?: unknown }).poste ?? "Sans poste"),
              String((d as { motif?: unknown }).motif ?? ""),
              formaterMontant(
                Number((d as { montant_fcfa?: unknown }).montant_fcfa ?? 0),
              ),
            ]),
            total: [
              "Total",
              "",
              "",
              `${rapport.depenses.length} dépense${rapport.depenses.length > 1 ? "s" : ""}`,
              formaterMontant(rapport.total_reel_fcfa),
            ],
            messageVide: "Aucune dépense sur cette période.",
          },
        ];
        const pdf = genererRapportPdf({
          titre: `Rapport des dépenses — ${libellePeriode(annee, mois)}`,
          egliseNom,
          lignesMeta: [
            libellePeriode(annee, mois),
            `Émis le ${dateJour(new Date().toISOString().slice(0, 10))}`,
            `Prévu : ${formaterMontant(rapport.total_prevu_fcfa)} · Réel : ${formaterMontant(rapport.total_reel_fcfa)}`,
          ],
          sections,
          pied: "Le réel compte les dépenses hors refusées. Un dépassement est signalé quand le réel dépasse un budget mensuel défini.",
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "export.pdf.rapport_depenses",
          details: { annee, mois: mois ?? null },
        });
        const fichier = mois !== undefined
          ? `rapport-depenses-${annee}-${String(mois).padStart(2, "0")}.pdf`
          : `rapport-depenses-${annee}.pdf`;
        reply
          .type("application/pdf")
          .header("Content-Disposition", `attachment; filename="${fichier}"`)
          .send(pdf);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
