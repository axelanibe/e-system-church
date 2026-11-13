import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import {
  READ_ALL,
  WRITE_FINANCES,
  existsInChurch,
  invalidInput,
  registerCrud,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Module 4 — Finances (compléter) : postes budgétaires, budgets annuels,
 * dépenses avec validation en deux temps (trésorier puis pasteur),
 * mouvements de caisse, rapports financiers détaillés (par poste, par mois,
 * par branche pour la mère).
 *
 * Tranche T7 (Lot B) — une seule source de vérité pour la caisse :
 * caisse_mouvements (manuelle + automatique). La caisse est écrite
 * automatiquement à chaque contribution confirmée (contributions.ts) et
 * à chaque dépense payée (ci-dessous) ; le solde n'est que la somme de
 * cette table. Comptes bancaires par église, rapprochement par canal,
 * clôture de caisse verrouillée (un mois clôturé ne se modifie plus).
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

/** Canaux de paiement / de caisse (même vocabulaire partout). */
const CANAUX = ["wave", "orange_money", "mtn_momo", "especes", "virement", "cheque"] as const;

/** Rôles qui lisent les données financières détaillées. */
const LECTURE_FINANCES = ["admin_eglise", "tresorier", "responsable_culte"];

/** Vrai si le mois du mouvement de caisse est clôturé pour cette église. */
async function mouvementEnPeriodeCloturee(
  db2: Pool,
  churchId: string,
  mouvementId: string,
): Promise<boolean> {
  const { rows } = await db2.query(
    `SELECT 1 FROM caisse_mouvements cm
      JOIN clotures_caisse cc
        ON cc.church_id = cm.church_id
       AND cc.periode = to_char(cm.created_at, 'YYYY-MM')
     WHERE cm.id = $1 AND cm.church_id = $2`,
    [mouvementId, churchId],
  );
  return rows.length > 0;
}

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
    // Lot B, tranche 1 : le statut ne se change QUE par la route de
    // validation en deux temps (PATCH /depenses/:id/statut). Le PATCH
    // générique ne peut plus passer une dépense directement à « payee »
    // sans passer par la machine à états.
    validateUpdate: async (_db2, _churchId, _id, data) => {
      if (data.statut !== undefined) {
        return "Le statut d'une dépense se change uniquement par la route de validation en deux temps (PATCH /depenses/:id/statut).";
      }
      return null;
    },
  });

  // -- Validation d'une dépense en deux temps. -------------------------------
  //    Tranche T7 : quand la dépense devient « payee », la caisse est écrite
  //    automatiquement (sortie) dans la même transaction que le changement
  //    de statut — tout ou rien. Le canal reprend le mode de paiement
  //    ('mtn_money' devient 'mtn_momo', comme les contributions).
  const statutSchema = z.object({
    statut: z.enum(["validee_tresorier", "validee_pasteur", "payee", "refusee"]),
  });
  app.patch(
    "/depenses/:id/statut",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
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
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        const { rows } = await client.query(
          `UPDATE depenses SET statut = $3, valide_par = $4
            WHERE id = $1 AND church_id = $2 AND statut = $5
            RETURNING id, montant_fcfa, statut, motif, reference, mode_paiement`,
          [
            (req.params as { id: string }).id,
            req.session.churchId,
            cible,
            req.session.userId,
            regle.from,
          ],
        );
        if (rows.length === 0) {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "conflict",
            message: "Dépense introuvable, ou étape précédente non validée.",
          });
        }
        const depense = rows[0];
        if (cible === "payee") {
          const canal =
            depense.mode_paiement === "mtn_money"
              ? "mtn_momo"
              : (depense.mode_paiement as string | null);
          await client.query(
            `INSERT INTO caisse_mouvements
               (church_id, type, montant_fcfa, motif, reference, source, source_id, canal)
             VALUES ($1, 'sortie', $2, $3, $4, 'depense', $5, $6)`,
            [
              req.session.churchId,
              depense.montant_fcfa,
              `Dépense payée — ${depense.motif}${depense.reference ? ` (${depense.reference})` : ""}`,
              depense.reference ?? null,
              depense.id,
              canal,
            ],
          );
        }
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: `depense.${cible}`,
          details: { depense_id: depense.id, montant_fcfa: depense.montant_fcfa },
        });
        await client.query("COMMIT");
        return reply.send({
          id: depense.id,
          montant_fcfa: depense.montant_fcfa,
          statut: depense.statut,
        });
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  registerCrud(app, db, {
    base: "/caisse-mouvements",
    table: "caisse_mouvements",
    // 'source' et 'source_id' ne sont PAS dans les colonnes : une saisie
    // manuelle reste 'manuelle' (défaut base) ; seules les écritures
    // automatiques (contribution confirmée, dépense payée) portent une
    // source. Le canal, lui, peut être renseigné à la saisie.
    columns: ["type", "montant_fcfa", "motif", "reference", "canal"],
    createSchema: z.object({
      type: z.enum(["entree", "sortie"]),
      montant_fcfa: z.number().int().positive().max(100_000_000),
      motif: z.string().min(2).max(500),
      reference: z.string().max(120).optional(),
      canal: z.enum(CANAUX).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_FINANCES,
    audit: "caisse",
    filters: { type: "type", canal: "canal", source: "source" },
    // Tranche T7 : un mois clôturé est verrouillé — ses mouvements ne se
    // modifient ni ne se suppriment plus (l'erreur se corrige par une
    // écriture dans la période en cours).
    validateUpdate: async (db2, churchId, id) => {
      if (await mouvementEnPeriodeCloturee(db2, churchId, id)) {
        return "Ce mouvement est dans un mois clôturé : il ne se modifie plus.";
      }
      return null;
    },
    beforeDelete: async (db2, churchId, id) => {
      if (await mouvementEnPeriodeCloturee(db2, churchId, id)) {
        return "Ce mouvement est dans un mois clôturé : il ne se supprime plus.";
      }
      return null;
    },
  });

  // -- Comptes bancaires par église (tranche T7) : virements. Les numéros
  //    Wave / Orange / MTN restent dans les paramètres de l'église. -------
  registerCrud(app, db, {
    base: "/comptes-bancaires",
    table: "comptes_bancaires",
    columns: ["banque", "titulaire", "numero_compte", "type", "devise", "actif"],
    createSchema: z.object({
      banque: z.string().min(2).max(120),
      titulaire: z.string().max(200).optional(),
      numero_compte: z.string().max(60).optional(),
      type: z.enum(["banque", "mobile_money"]).default("banque"),
      devise: z.string().min(2).max(10).default("FCFA"),
      actif: z.boolean().default(true),
    }),
    readRoles: LECTURE_FINANCES,
    writeRoles: WRITE_FINANCES,
    audit: "compte_bancaire",
    searchColumn: "banque",
    filters: { type: "type", actif: "actif" },
  });

  // -- Solde de caisse : entrées − sorties. ----------------------------------
  app.get(
    "/finances/caisse",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
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

  // -- Rapprochement bancaire par canal (tranche T7). -------------------------
  //    Pour chaque canal (Wave, Orange Money, MTN, espèces, virement,
  //    chèque) : ce qui aurait dû entrer / sortir (contributions confirmées
  //    et dépenses payées du mois) contre ce qui est comptabilisé en caisse
  //    (écritures automatiques + manuelles du mois). L'écart signale les
  //    écritures manuelles et les périodes antérieures à la T7 (sans
  //    écriture automatique). Les mouvements sans canal sont regroupés en
  //    « non ventilé » : rien n'est caché.
  const rapprochementQuerySchema = z.object({
    annee: z.coerce.number().int().min(2000).max(2100).optional(),
    mois: z.coerce.number().int().min(1).max(12).optional(),
  });
  app.get(
    "/finances/rapprochement",
    { preHandler: [requireAuth(db), requireRole(...LECTURE_FINANCES)] },
    async (req, reply) => {
      const parsed = rapprochementQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const maintenant = new Date();
      const annee = parsed.data.annee ?? maintenant.getFullYear();
      const mois = parsed.data.mois ?? maintenant.getMonth() + 1;
      const debut = `${annee}-${String(mois).padStart(2, "0")}-01`;
      const fin = mois === 12 ? `${annee + 1}-01-01` : `${annee}-${String(mois + 1).padStart(2, "0")}-01`;
      try {
        const { rows: entreesRows } = await db.query(
          `SELECT payment_method AS canal, coalesce(sum(amount_fcfa), 0)::int AS entrees
             FROM contributions
            WHERE church_id = $1 AND status = 'confirme'
              AND created_at >= $2::date AND created_at < $3::date
            GROUP BY payment_method`,
          [req.session.churchId, debut, fin],
        );
        const { rows: sortiesRows } = await db.query(
          `SELECT CASE WHEN mode_paiement = 'mtn_money' THEN 'mtn_momo'
                       ELSE mode_paiement END AS canal,
                  coalesce(sum(montant_fcfa), 0)::int AS sorties
             FROM depenses
            WHERE church_id = $1 AND statut = 'payee' AND mode_paiement IS NOT NULL
              AND date_depense >= $2::date AND date_depense < $3::date
            GROUP BY 1`,
          [req.session.churchId, debut, fin],
        );
        const { rows: caisseRows } = await db.query(
          `SELECT canal,
                  coalesce(sum(montant_fcfa) FILTER (WHERE type = 'entree'), 0)::int AS caisse_entrees,
                  coalesce(sum(montant_fcfa) FILTER (WHERE type = 'sortie'), 0)::int AS caisse_sorties
             FROM caisse_mouvements
            WHERE church_id = $1 AND created_at >= $2::date AND created_at < $3::date
            GROUP BY canal`,
          [req.session.churchId, debut, fin],
        );
        const entrees = new Map<string, number>(
          entreesRows.map((r): [string, number] => [r.canal as string, Number(r.entrees)]),
        );
        const sorties = new Map<string, number>(
          sortiesRows.map((r): [string, number] => [r.canal as string, Number(r.sorties)]),
        );
        const caisse = new Map<string, { entrees: number; sorties: number }>(
          caisseRows.map((r): [string, { entrees: number; sorties: number }] => [
            (r.canal as string | null) ?? "non_ventile",
            { entrees: Number(r.caisse_entrees), sorties: Number(r.caisse_sorties) },
          ]),
        );
        interface LigneRapprochement {
          canal: string;
          entrees_confirmees_fcfa: number;
          sorties_payees_fcfa: number;
          attendu_fcfa: number;
          caisse_entrees_fcfa: number;
          caisse_sorties_fcfa: number;
          caisse_net_fcfa: number;
          ecart_fcfa: number;
          alerte: boolean;
        }
        const ligne = (canal: string): LigneRapprochement => {
          const entreesCanal = entrees.get(canal) ?? 0;
          const sortiesCanal = sorties.get(canal) ?? 0;
          const caisseCanal = caisse.get(canal) ?? { entrees: 0, sorties: 0 };
          const attendu = entreesCanal - sortiesCanal;
          const caisseNet = caisseCanal.entrees - caisseCanal.sorties;
          return {
            canal,
            entrees_confirmees_fcfa: entreesCanal,
            sorties_payees_fcfa: sortiesCanal,
            attendu_fcfa: attendu,
            caisse_entrees_fcfa: caisseCanal.entrees,
            caisse_sorties_fcfa: caisseCanal.sorties,
            caisse_net_fcfa: caisseNet,
            ecart_fcfa: attendu - caisseNet,
            alerte: attendu - caisseNet !== 0,
          };
        };
        const canaux = CANAUX.map(ligne);
        const nonVentile = ligne("non_ventile");
        type CleNumerique =
          | "entrees_confirmees_fcfa"
          | "sorties_payees_fcfa"
          | "attendu_fcfa"
          | "caisse_net_fcfa"
          | "ecart_fcfa";
        const total = (cle: CleNumerique) =>
          [...canaux, nonVentile].reduce((s, l) => s + l[cle], 0);
        return reply.send({
          annee,
          mois,
          periode: `${annee}-${String(mois).padStart(2, "0")}`,
          canaux,
          non_ventile: nonVentile,
          totaux: {
            entrees_confirmees_fcfa: total("entrees_confirmees_fcfa"),
            sorties_payees_fcfa: total("sorties_payees_fcfa"),
            attendu_fcfa: total("attendu_fcfa"),
            caisse_net_fcfa: total("caisse_net_fcfa"),
            ecart_fcfa: total("ecart_fcfa"),
          },
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Clôture de caisse verrouillée (tranche T7). ----------------------------
  //    On ne clôture qu'un mois TERMINÉ (jamais le mois en cours, jamais
  //    un mois futur). La clôture fige le solde calculé et, si le trésorier
  //    a compté la caisse, le solde compté et l'écart. Une clôture ne se
  //    rouvre ni ne se supprime (pas de route) ; une erreur se corrige par
  //    une écriture dans la période en cours. Les mouvements du mois
  //    clôturé ne se modifient ni ne se suppriment plus (garde CRUD).
  const cloturerSchema = z.object({
    periode: z.string().regex(/^\d{4}-\d{2}$/, "Période au format AAAA-MM."),
    solde_compte_fcfa: z.number().int().min(0).max(100_000_000).optional(),
    commentaire: z.string().max(500).optional(),
  });
  app.post(
    "/finances/caisse/cloturer",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = cloturerSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { periode, solde_compte_fcfa, commentaire } = parsed.data;
      const mois = Number(periode.slice(5, 7));
      if (mois < 1 || mois > 12) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Mois invalide (01 à 12).",
        });
      }
      const maintenant = new Date();
      const moisCourant = `${maintenant.getFullYear()}-${String(maintenant.getMonth() + 1).padStart(2, "0")}`;
      if (periode >= moisCourant) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "On ne clôture qu'un mois terminé.",
        });
      }
      const annee = Number(periode.slice(0, 4));
      const debut = `${periode}-01`;
      const fin = mois === 12 ? `${annee + 1}-01-01` : `${annee}-${String(mois + 1).padStart(2, "0")}-01`;
      try {
        const { rows: soldes } = await db.query(
          `SELECT coalesce(sum(CASE WHEN type = 'entree' THEN montant_fcfa ELSE -montant_fcfa END), 0)::int AS solde
             FROM caisse_mouvements
            WHERE church_id = $1 AND created_at >= $2::date AND created_at < $3::date`,
          [req.session.churchId, debut, fin],
        );
        const soldeCalcule = Number(soldes[0].solde);
        const soldeCompte = solde_compte_fcfa ?? soldeCalcule;
        const { rows } = await db.query(
          `INSERT INTO clotures_caisse
             (church_id, periode, solde_calcule_fcfa, solde_compte_fcfa, ecart_fcfa, commentaire, cloture_par)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           ON CONFLICT (church_id, periode) DO NOTHING
           RETURNING *`,
          [
            req.session.churchId,
            periode,
            soldeCalcule,
            soldeCompte,
            soldeCompte - soldeCalcule,
            commentaire ?? null,
            req.session.userId,
          ],
        );
        if (rows.length === 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Cette période est déjà clôturée.",
          });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "caisse.cloturee",
          details: {
            periode,
            solde_calcule_fcfa: soldeCalcule,
            solde_compte_fcfa: soldeCompte,
            ecart_fcfa: soldeCompte - soldeCalcule,
          },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/finances/caisse/clotures",
    { preHandler: [requireAuth(db), requireRole(...LECTURE_FINANCES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, periode, solde_calcule_fcfa, solde_compte_fcfa, ecart_fcfa,
                  commentaire, cloture_par, created_at
             FROM clotures_caisse WHERE church_id = $1 ORDER BY periode DESC`,
          [req.session.churchId],
        );
        return reply.send(rows);
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
    // Lot B, tranche 1 : le trésorier est autorisé sur son rapport
    // financier (il en était exclu : la route exigeait WRITE_STD).
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "tresorier", "responsable_culte")] },
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
