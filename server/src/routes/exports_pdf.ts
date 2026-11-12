import type { FastifyInstance, FastifyReply } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { READ_ALL, WRITE_FINANCES, invalidInput } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import {
  formaterMontant,
  genererRapportPdf,
  type SectionRapport,
} from "../pdf.js";

/**
 * Tranche C — Exports PDF (finances, cultes, rapports consolidés).
 *
 * Nouveau fichier : ne touche ni à finances.ts ni à rapports.ts (tranche 1
 * RBAC de Phoenix en cours sur ces fichiers). Chaque route reprend les
 * mêmes requêtes et les mêmes contrôles de rôle que la route GET
 * correspondante, et le PDF est généré par le générateur multipage de
 * pdf.ts (aucune librairie PDF ajoutée, ni serveur ni Flutter).
 *
 * - GET /exports/finances/detail — contributions et dépenses confirmées
 *   d'une période (mêmes filtres from/to que GET /finances/rapport),
 *   admin_eglise et tresorier seulement.
 * - GET /exports/finances/resume — mêmes totaux que GET /finances/rapport
 *   (par mois, par poste, par branche), pour une période ou une année,
 *   admin_eglise et tresorier seulement.
 * - GET /exports/cultes — liste des cultes avec présences (mêmes droits
 *   de lecture que GET /cultes : tous les rôles de l'église).
 * - GET /exports/rapports/consolide — mêmes agrégats que GET
 *   /rapports/consolide (admin_eglise seulement), agrégats seulement,
 *   jamais de détail nominatif d'une antenne.
 *
 * Écart connu avec GET /finances/rapport sur main : ce dernier exige
 * WRITE_STD (admin_eglise, responsable_culte) alors que les exports
 * finances exigent ici WRITE_FINANCES (admin_eglise, tresorier), comme
 * demandé pour la tranche C. Si la tranche 1 RBAC aligne le rapport JSON
 * sur admin + trésorier, les deux seront cohérents ; sinon le responsable
 * de culte voit le rapport JSON mais pas son export PDF, et le trésorier
 * voit l'export PDF mais pas le rapport JSON.
 */

const dateRe = /^\d{4}-\d{2}-\d{2}$/;

const periodeQuerySchema = z.object({
  from: z.string().regex(dateRe).optional(),
  to: z.string().regex(dateRe).optional(),
});

const resumeQuerySchema = z.object({
  from: z.string().regex(dateRe).optional(),
  to: z.string().regex(dateRe).optional(),
  annee: z.coerce.number().int().min(2000).max(2100).optional(),
});

const TYPES_CONTRIBUTION: Record<string, string> = {
  dime: "Dîme",
  offrande: "Offrande",
  don: "Don",
  depense: "Dépense",
};

function dateJour(iso: string): string {
  const [a, m, j] = iso.split("-");
  return `${j}/${m}/${a}`;
}

function dateValeur(v: unknown): string {
  const d = v instanceof Date ? v : new Date(String(v));
  return dateJour(d.toISOString().slice(0, 10));
}

function aujourdhui(): string {
  return dateJour(new Date().toISOString().slice(0, 10));
}

function libellePeriode(from?: string, to?: string, annee?: number): string {
  if (from && to) return `Période : du ${dateJour(from)} au ${dateJour(to)}`;
  if (from) return `Période : à partir du ${dateJour(from)}`;
  if (to) return `Période : jusqu'au ${dateJour(to)}`;
  if (annee) return `Année ${annee}`;
  return "Toute période";
}

function nomFichier(base: string): string {
  return `${base}-${new Date().toISOString().slice(0, 10)}.pdf`;
}

function envoyerPdf(
  reply: FastifyReply,
  pdf: Buffer,
  fichier: string,
): void {
  reply
    .type("application/pdf")
    .header("Content-Disposition", `attachment; filename="${fichier}"`)
    .send(pdf);
}

async function nomEglise(db: Pool, churchId: string): Promise<string> {
  const { rows } = await db.query(
    `SELECT name, code FROM churches WHERE id = $1`,
    [churchId],
  );
  if (rows.length === 0) return "Église";
  return `${rows[0].name} (${rows[0].code})`;
}

export function registerExportsPdfRoutes(app: FastifyInstance, db: Pool) {
  // -- Détail finances : contributions et dépenses confirmées. -------------
  app.get(
    "/exports/finances/detail",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = periodeQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { from, to } = parsed.data;
      try {
        const egliseNom = await nomEglise(db, req.session.churchId);
        const conditions = [`c.church_id = $1`, `c.status = 'confirme'`];
        const values: unknown[] = [req.session.churchId];
        if (from) {
          values.push(from);
          conditions.push(`c.created_at >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(
            `c.created_at < ($${values.length}::date + interval '1 day')`,
          );
        }
        const { rows: contributions } = await db.query(
          `SELECT c.created_at, c.type, c.amount_fcfa, c.payment_method,
                  c.payment_ref, m.full_name AS membre_nom, m.matricule
             FROM contributions c
             LEFT JOIN members m ON m.id = c.member_id
            WHERE ${conditions.join(" AND ")}
            ORDER BY c.created_at DESC, c.id DESC`,
          values,
        );
        const condDep = [`d.church_id = $1`, `d.statut IN ('validee_pasteur', 'payee')`];
        const valDep: unknown[] = [req.session.churchId];
        if (from) {
          valDep.push(from);
          condDep.push(`d.date_depense >= $${valDep.length}::date`);
        }
        if (to) {
          valDep.push(to);
          condDep.push(`d.date_depense < ($${valDep.length}::date + interval '1 day')`);
        }
        const { rows: depenses } = await db.query(
          `SELECT d.date_depense, d.motif, d.montant_fcfa, d.statut,
                  d.justificatif_ref, p.nom AS poste
             FROM depenses d
             LEFT JOIN postes_budgetaires p ON p.id = d.poste_id
            WHERE ${condDep.join(" AND ")}
            ORDER BY d.date_depense DESC, d.created_at DESC`,
          valDep,
        );
        const totalEntrees = contributions.reduce(
          (s: number, r: { amount_fcfa: number }) => s + r.amount_fcfa,
          0,
        );
        const totalDepenses = depenses.reduce(
          (s: number, r: { montant_fcfa: number }) => s + r.montant_fcfa,
          0,
        );
        const sections: SectionRapport[] = [
          {
            titre: "Contributions confirmées",
            colonnes: [
              { titre: "Date", largeur: 70 },
              { titre: "Type", largeur: 70 },
              { titre: "Membre", largeur: 165 },
              { titre: "Moyen", largeur: 75 },
              { titre: "Montant", largeur: 115, alignerDroite: true },
            ],
            lignes: contributions.map((r) => [
              dateValeur(r.created_at),
              TYPES_CONTRIBUTION[r.type as string] ?? String(r.type),
              r.membre_nom
                ? `${r.membre_nom}${r.matricule ? ` (${r.matricule})` : ""}`
                : "Anonyme",
              String(r.payment_method ?? ""),
              formaterMontant(r.amount_fcfa),
            ]),
            total: [
              "Total",
              "",
              `${contributions.length} contribution${contributions.length > 1 ? "s" : ""}`,
              "",
              formaterMontant(totalEntrees),
            ],
            messageVide: "Aucune donnée sur cette période.",
          },
          {
            titre: "Dépenses validées et payées",
            colonnes: [
              { titre: "Date", largeur: 70 },
              { titre: "Poste", largeur: 105 },
              { titre: "Motif", largeur: 165 },
              { titre: "Statut", largeur: 60 },
              { titre: "Montant", largeur: 95, alignerDroite: true },
            ],
            lignes: depenses.map((r) => [
              dateValeur(r.date_depense),
              String(r.poste ?? "Sans poste"),
              String(r.motif),
              String(r.statut),
              formaterMontant(r.montant_fcfa),
            ]),
            total: [
              "Total",
              "",
              `${depenses.length} dépense${depenses.length > 1 ? "s" : ""}`,
              "",
              formaterMontant(totalDepenses),
            ],
            messageVide: "Aucune donnée sur cette période.",
          },
        ];
        const pdf = genererRapportPdf({
          titre: "Détail des finances",
          egliseNom,
          lignesMeta: [
            libellePeriode(from, to),
            `Émis le ${aujourdhui()}`,
            `Entrées : ${formaterMontant(totalEntrees)} · Dépenses : ${formaterMontant(totalDepenses)} · Solde : ${formaterMontant(totalEntrees - totalDepenses)}`,
          ],
          sections,
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "export.pdf.finances_detail",
          details: { from: from ?? null, to: to ?? null },
        });
        envoyerPdf(reply, pdf, nomFichier("finances-detail"));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Résumé finances : mêmes totaux que GET /finances/rapport. -----------
  app.get(
    "/exports/finances/resume",
    { preHandler: [requireAuth(db), requireRole(...WRITE_FINANCES)] },
    async (req, reply) => {
      const parsed = resumeQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { from, to, annee } = parsed.data;
      const year = annee ?? new Date().getFullYear();
      try {
        const egliseNom = await nomEglise(db, req.session.churchId);
        const conditions = [`c.church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (from) {
          values.push(from);
          conditions.push(`c.created_at >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(
            `c.created_at < ($${values.length}::date + interval '1 day')`,
          );
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
        const totalMois = parMois.reduce(
          (s: number, r: { total_fcfa: number }) => s + Number(r.total_fcfa),
          0,
        );
        const totalBudget = parPoste.reduce(
          (s: number, r: { budget_fcfa: number }) => s + Number(r.budget_fcfa),
          0,
        );
        const totalRealise = parPoste.reduce(
          (s: number, r: { realise_fcfa: number }) => s + Number(r.realise_fcfa),
          0,
        );
        const totalBranche = parBranche.reduce(
          (s: number, r: { total_fcfa: number }) => s + Number(r.total_fcfa),
          0,
        );
        const nbBranche = parBranche.reduce(
          (s: number, r: { nombre_contributions: number }) =>
            s + Number(r.nombre_contributions),
          0,
        );
        const pdf = genererRapportPdf({
          titre: "Résumé des finances",
          egliseNom,
          lignesMeta: [
            `${libellePeriode(from, to, annee)} · Budgets : année ${year}`,
            `Émis le ${aujourdhui()}`,
          ],
          sections: [
            {
              titre: "Par mois",
              colonnes: [
                { titre: "Mois", largeur: 90 },
                { titre: "Type", largeur: 120 },
                { titre: "Nombre", largeur: 90, alignerDroite: true },
                { titre: "Total", largeur: 195, alignerDroite: true },
              ],
              lignes: parMois.map((r) => [
                String(r.mois),
                TYPES_CONTRIBUTION[r.type as string] ?? String(r.type),
                String(r.nombre),
                formaterMontant(Number(r.total_fcfa)),
              ]),
              total: ["Total", "", "", formaterMontant(totalMois)],
              messageVide: "Aucune donnée sur cette période.",
            },
            {
              titre: "Par poste",
              colonnes: [
                { titre: "Poste", largeur: 165 },
                { titre: "Catégorie", largeur: 80 },
                { titre: "Budget", largeur: 125, alignerDroite: true },
                { titre: "Réalisé", largeur: 125, alignerDroite: true },
              ],
              lignes: parPoste.map((r) => [
                String(r.poste),
                String(r.categorie),
                formaterMontant(Number(r.budget_fcfa)),
                formaterMontant(Number(r.realise_fcfa)),
              ]),
              total: [
                "Total",
                "",
                formaterMontant(totalBudget),
                formaterMontant(totalRealise),
              ],
              messageVide: "Aucun poste budgétaire pour l'instant.",
            },
            {
              titre: "Par branche",
              colonnes: [
                { titre: "Église", largeur: 165 },
                { titre: "Membres actifs", largeur: 95, alignerDroite: true },
                { titre: "Contributions", largeur: 95, alignerDroite: true },
                { titre: "Total", largeur: 140, alignerDroite: true },
              ],
              lignes: parBranche.map((r) => [
                String(r.eglise_nom),
                String(Number(r.membres_actifs)),
                String(Number(r.nombre_contributions)),
                formaterMontant(Number(r.total_fcfa)),
              ]),
              total: [
                "Total",
                "",
                String(nbBranche),
                formaterMontant(totalBranche),
              ],
              messageVide: "Aucune sous-église rattachée pour l'instant.",
            },
          ],
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "export.pdf.finances_resume",
          details: { from: from ?? null, to: to ?? null, annee: year },
        });
        envoyerPdf(reply, pdf, nomFichier("finances-resume"));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Cultes : liste des cultes avec présences. ----------------------------
  app.get(
    "/exports/cultes",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = periodeQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { from, to } = parsed.data;
      try {
        const egliseNom = await nomEglise(db, req.session.churchId);
        const conditions = [`cu.church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (from) {
          values.push(from);
          conditions.push(`cu.date_heure >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(
            `cu.date_heure < ($${values.length}::date + interval '1 day')`,
          );
        }
        const { rows: cultes } = await db.query(
          `SELECT cu.titre, cu.date_heure, cu.lieu, cu.orateur, cu.theme,
                  ct.nom AS type_nom,
                  (SELECT count(*)::int FROM presences p WHERE p.culte_id = cu.id AND p.statut = 'present') AS presents,
                  (SELECT count(*)::int FROM presences p WHERE p.culte_id = cu.id AND p.statut = 'absent') AS absents,
                  (SELECT count(*)::int FROM presences p WHERE p.culte_id = cu.id AND p.statut = 'excuse') AS excuses,
                  (SELECT count(*)::int FROM presences p WHERE p.culte_id = cu.id) AS total
             FROM cultes cu
             LEFT JOIN culte_types ct ON ct.id = cu.culte_type_id
            WHERE ${conditions.join(" AND ")}
            ORDER BY cu.date_heure DESC`,
          values,
        );
        const totalPresents = cultes.reduce(
          (s: number, r: { presents: number }) => s + Number(r.presents),
          0,
        );
        const totalPointages = cultes.reduce(
          (s: number, r: { total: number }) => s + Number(r.total),
          0,
        );
        const pdf = genererRapportPdf({
          titre: "Cultes et présences",
          egliseNom,
          lignesMeta: [
            libellePeriode(from, to),
            `Émis le ${aujourdhui()}`,
          ],
          sections: [
            {
              titre: "Cultes",
              colonnes: [
                { titre: "Date", largeur: 95 },
                { titre: "Culte", largeur: 150 },
                { titre: "Type", largeur: 80 },
                { titre: "Orateur", largeur: 85 },
                { titre: "Présents", largeur: 45, alignerDroite: true },
                { titre: "Pointés", largeur: 40, alignerDroite: true },
              ],
              lignes: cultes.map((r) => [
                dateValeur(r.date_heure),
                String(r.titre),
                String(r.type_nom ?? ""),
                String(r.orateur ?? ""),
                String(Number(r.presents)),
                String(Number(r.total)),
              ]),
              total: [
                "Total",
                `${cultes.length} culte${cultes.length > 1 ? "s" : ""}`,
                "",
                "",
                String(totalPresents),
                String(totalPointages),
              ],
              messageVide: "Aucune donnée sur cette période.",
            },
          ],
          pied: "Présences comptées sur les pointages enregistrés (présent, absent, excusé).",
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "export.pdf.cultes",
          details: { from: from ?? null, to: to ?? null },
        });
        envoyerPdf(reply, pdf, nomFichier("cultes"));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rapport consolidé : agrégats seulement, jamais de détail nominatif. --
  app.get(
    "/exports/rapports/consolide",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows: churchRows } = await db.query(
          `SELECT id, code, name, city FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const church = churchRows[0];
        if (!church) {
          return reply
            .code(404)
            .send({ error: "not_found", message: "Église introuvable." });
        }
        const { rows: propresRows } = await db.query(
          `SELECT
             (SELECT count(*)::int FROM members m WHERE m.church_id = $1 AND m.status = 'actif') AS membres_actifs,
             (SELECT count(*)::int FROM contributions co
               WHERE co.church_id = $1 AND co.type IN ('dime','offrande','don') AND co.status = 'confirme') AS nombre_contributions,
             (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions co
               WHERE co.church_id = $1 AND co.type IN ('dime','offrande','don') AND co.status = 'confirme') AS total_fcfa`,
          [req.session.churchId],
        );
        const propres = propresRows[0];
        const { rows: sousEglises } = await db.query(
          `SELECT eglise_id, eglise_nom, niveau, membres_actifs, nombre_contributions, total_fcfa
             FROM v_rapports_consolides
            WHERE eglise_mere_id = $1
            ORDER BY niveau ASC, eglise_nom ASC`,
          [req.session.churchId],
        );
        const sousNorm = sousEglises.map((r) => ({
          eglise_nom: String(r.eglise_nom),
          niveau: Number(r.niveau),
          membres_actifs: Number(r.membres_actifs),
          nombre_contributions: Number(r.nombre_contributions),
          total_fcfa: Number(r.total_fcfa),
        }));
        const totauxReseau = {
          membres_actifs:
            Number(propres.membres_actifs) +
            sousNorm.reduce((s, r) => s + r.membres_actifs, 0),
          nombre_contributions:
            Number(propres.nombre_contributions) +
            sousNorm.reduce((s, r) => s + r.nombre_contributions, 0),
          total_fcfa:
            Number(propres.total_fcfa) +
            sousNorm.reduce((s, r) => s + r.total_fcfa, 0),
        };
        const pdf = genererRapportPdf({
          titre: "Rapport consolidé",
          egliseNom: `${church.name} (${church.code})`,
          lignesMeta: [`Émis le ${aujourdhui()}`],
          sections: [
            {
              titre: "Mon église",
              colonnes: [
                { titre: "Indicateur", largeur: 200 },
                { titre: "Valeur", largeur: 295, alignerDroite: true },
              ],
              lignes: [
                ["Membres actifs", String(Number(propres.membres_actifs))],
                [
                  "Contributions confirmées",
                  String(Number(propres.nombre_contributions)),
                ],
                [
                  "Total des contributions",
                  formaterMontant(Number(propres.total_fcfa)),
                ],
              ],
            },
            {
              titre: "Sous-églises (agrégats)",
              colonnes: [
                { titre: "Église", largeur: 200 },
                { titre: "Niveau", largeur: 55, alignerDroite: true },
                { titre: "Membres actifs", largeur: 80, alignerDroite: true },
                { titre: "Contributions", largeur: 70, alignerDroite: true },
                { titre: "Total", largeur: 90, alignerDroite: true },
              ],
              lignes: sousNorm.map((r) => [
                r.eglise_nom,
                String(r.niveau),
                String(r.membres_actifs),
                String(r.nombre_contributions),
                formaterMontant(r.total_fcfa),
              ]),
              total: [
                "Total réseau",
                "",
                String(totauxReseau.membres_actifs),
                String(totauxReseau.nombre_contributions),
                formaterMontant(totauxReseau.total_fcfa),
              ],
              messageVide: "Aucune sous-église rattachée pour l'instant.",
            },
          ],
          pied: "Agrégats seulement : aucun détail nominatif d'une antenne ne figure dans cet export.",
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "export.pdf.rapport_consolide",
          details: {},
        });
        envoyerPdf(reply, pdf, nomFichier("rapport-consolide"));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
