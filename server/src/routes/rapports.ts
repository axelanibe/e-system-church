import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Rapports consolidés — admin de l'église mère seulement.
 * GET /rapports/consolide — chiffres de mon église + agrégats de chaque
 * descendant (vue v_rapports_consolides, récursive : totaux uniquement,
 * jamais le détail nominatif d'une antenne).
 * GET /rapports/consolide/detail — même périmètre (mon église + tous ses
 * descendants, petites-filles comprises, avec leur niveau), mais en détail :
 * total consolidé et détail par branche, par période (mois, trimestre,
 * année) et par type, avec chaque transaction confirmée. La vue agrégée
 * reste pour le tableau de bord ; le détail s'ajoute à côté, il ne la
 * remplace pas.
 */

const TYPES = ["dime", "offrande", "don", "depense"] as const;

const detailQuerySchema = z.object({
  periode: z.enum(["mois", "trimestre", "annee"]).default("mois"),
  mois: z
    .string()
    .regex(/^\d{4}-(0[1-9]|1[0-2])$/, "Mois au format AAAA-MM.")
    .optional(),
});

const NOMS_MOIS = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];

/** Bornes [début, fin[ d'une période, ancrée sur le mois AAAA-MM. */
export function bornesPeriode(
  periode: "mois" | "trimestre" | "annee",
  moisAncre: string,
): { debut: string; fin: string; label: string } {
  const annee = Number(moisAncre.slice(0, 4));
  const mois = Number(moisAncre.slice(5, 7));
  const iso = (a: number, m: number) =>
    `${a}-${String(m).padStart(2, "0")}-01`;
  const plusMois = (a: number, m: number, n: number) => {
    const total = a * 12 + (m - 1) + n;
    return { a: Math.floor(total / 12), m: (total % 12) + 1 };
  };
  if (periode === "annee") {
    return { debut: iso(annee, 1), fin: iso(annee + 1, 1), label: `Année ${annee}` };
  }
  if (periode === "trimestre") {
    const trimestre = Math.floor((mois - 1) / 3) + 1;
    const debutMois = (trimestre - 1) * 3 + 1;
    const fin = plusMois(annee, debutMois, 3);
    return {
      debut: iso(annee, debutMois),
      fin: iso(fin.a, fin.m),
      label: `${trimestre === 1 ? "1er" : `${trimestre}e`} trimestre ${annee}`,
    };
  }
  const fin = plusMois(annee, mois, 1);
  const nomMois = NOMS_MOIS[mois - 1];
  return {
    debut: iso(annee, mois),
    fin: iso(fin.a, fin.m),
    label: `${nomMois[0].toUpperCase()}${nomMois.slice(1)} ${annee}`,
  };
}

export function registerRapportsRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/rapports/consolide",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows: churchRows } = await db.query(
          `SELECT id, code, name, city FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const church = churchRows[0];
        if (!church) return reply.code(404).send({ error: "not_found", message: "Église introuvable." });

        // Mes propres chiffres (église de la session).
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

        // Agrégats de tous mes descendants (la vue est récursive : la
        // racine est l'église de la session, niveau 1 = sous-église
        // directe, niveau 2 = antenne d'une sous-église, …).
        const { rows: sousEglises } = await db.query(
          `SELECT eglise_id, eglise_nom, niveau, membres_actifs, nombre_contributions, total_fcfa
             FROM v_rapports_consolides
            WHERE eglise_mere_id = $1
            ORDER BY niveau ASC, eglise_nom ASC`,
          [req.session.churchId],
        );

        const totauxReseau = {
          membres_actifs:
            propres.membres_actifs +
            sousEglises.reduce((s, r) => s + Number(r.membres_actifs), 0),
          nombre_contributions:
            propres.nombre_contributions +
            sousEglises.reduce((s, r) => s + Number(r.nombre_contributions), 0),
          total_fcfa:
            propres.total_fcfa + sousEglises.reduce((s, r) => s + Number(r.total_fcfa), 0),
        };

        return reply.send({
          eglise: church,
          propre: propres,
          sous_eglises: sousEglises,
          totaux_reseau: totauxReseau,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/rapports/consolide/detail",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = detailQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Période invalide (mois, trimestre ou année).",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { periode } = parsed.data;
      const moisAncre =
        parsed.data.mois ?? new Date().toISOString().slice(0, 7);
      const { debut, fin, label } = bornesPeriode(periode, moisAncre);
      try {
        const { rows: churchRows } = await db.query(
          `SELECT id, code, name, city FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        const church = churchRows[0];
        if (!church) return reply.code(404).send({ error: "not_found", message: "Église introuvable." });

        // Périmètre strict : mon église + tous ses descendants, récursif
        // (petites-filles comprises). Jamais une autre mère, jamais une
        // autre branche du réseau. Le niveau est renvoyé avec chaque
        // branche : 0 = mon église, 1 = sous-église directe,
        // 2 = antenne d'une sous-église, …
        const { rows: branchesRows } = await db.query(
          `WITH RECURSIVE descendants AS (
             SELECT id, code, name, city, 0 AS niveau
               FROM churches WHERE id = $1
              UNION ALL
             SELECT c.id, c.code, c.name, c.city, d.niveau + 1
               FROM churches c
               JOIN descendants d ON c.parent_church_id = d.id
           )
           SELECT id, code, name, city, niveau FROM descendants
            ORDER BY niveau ASC, name ASC`,
          [req.session.churchId],
        );

        const branches = [];
        const totauxReseau: Record<string, { total_fcfa: number; nombre: number }> = {};
        for (const t of TYPES) totauxReseau[t] = { total_fcfa: 0, nombre: 0 };
        let membresActifsReseau = 0;

        for (const b of branchesRows) {
          const { rows: membresRows } = await db.query(
            `SELECT count(*)::int AS n FROM members
              WHERE church_id = $1 AND status = 'actif'`,
            [b.id],
          );
          const { rows: totauxRows } = await db.query(
            `SELECT type, coalesce(sum(amount_fcfa), 0)::int AS total_fcfa,
                    count(*)::int AS nombre
               FROM contributions
              WHERE church_id = $1 AND status = 'confirme'
                AND created_at >= $2::date AND created_at < $3::date
              GROUP BY type`,
            [b.id, debut, fin],
          );
          const totaux: Record<string, { total_fcfa: number; nombre: number }> = {};
          for (const t of TYPES) totaux[t] = { total_fcfa: 0, nombre: 0 };
          for (const t of totauxRows) {
            totaux[t.type as string] = { total_fcfa: t.total_fcfa, nombre: t.nombre };
            totauxReseau[t.type as string].total_fcfa += t.total_fcfa;
            totauxReseau[t.type as string].nombre += t.nombre;
          }
          const entrees =
            totaux.dime.total_fcfa + totaux.offrande.total_fcfa + totaux.don.total_fcfa;
          const depenses = totaux.depense.total_fcfa;
          membresActifsReseau += membresRows[0].n;
          // Chaque transaction confirmée de la période, la plus récente d'abord.
          const { rows: transactions } = await db.query(
            `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.payment_ref,
                    c.status, c.note, c.created_at,
                    c.member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule
               FROM contributions c
               LEFT JOIN members m ON m.id = c.member_id
              WHERE c.church_id = $1 AND c.status = 'confirme'
                AND c.created_at >= $2::date AND c.created_at < $3::date
              ORDER BY c.created_at DESC, c.id DESC
              LIMIT 100`,
            [b.id, debut, fin],
          );
          branches.push({
            eglise_id: b.id,
            eglise_code: b.code,
            eglise_nom: b.name,
            eglise_ville: b.city,
            niveau: b.niveau,
            membres_actifs: membresRows[0].n,
            totaux,
            entrees_fcfa: entrees,
            depenses_fcfa: depenses,
            solde_fcfa: entrees - depenses,
            transactions,
          });
        }

        const entreesReseau =
          totauxReseau.dime.total_fcfa +
          totauxReseau.offrande.total_fcfa +
          totauxReseau.don.total_fcfa;
        const depensesReseau = totauxReseau.depense.total_fcfa;

        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "rapport.detail_consulte",
          details: { periode, debut, fin, branches: branchesRows.map((b) => b.id) },
        });

        return reply.send({
          eglise: church,
          periode: { type: periode, debut, fin, label },
          branches,
          totaux_reseau: {
            totaux: totauxReseau,
            entrees_fcfa: entreesReseau,
            depenses_fcfa: depensesReseau,
            solde_fcfa: entreesReseau - depensesReseau,
            membres_actifs: membresActifsReseau,
          },
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
