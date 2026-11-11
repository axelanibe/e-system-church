import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import {
  MODULES_ACTIVABLES,
  MODULES_NOYAU,
  type ModuleInfo,
} from "../modules.js";

/**
 * Mes annexes : la mère voit directement ce qui se passe dans ses
 * églises sous tutelle, sans changer d'église.
 *
 * GET /annexes     — mes descendantes (tous niveaux, récursif), avec
 *                     nom, code, ville, statut, niveau, membres actifs,
 *                     contributions confirmées et total des entrées.
 *                     Recherche `?q=` sur le nom, le code ou la ville.
 * GET /annexes/:id — détail d'une annexe : mêmes chiffres, dépenses
 *                     confirmées, cultes, présences, annonces, et état
 *                     de ses modules.
 *
 * Admin de la mère seulement. L'annexe doit être une descendante de
 * l'église de la session, sinon 403. Que des agrégats, jamais de
 * données nominatives (membres, transactions) : la promesse de
 * `db/schema.sql` (agrégats seulement pour la mère) est respectée.
 */

async function estDescendante(
  db: Pool,
  racineId: string,
  egliseId: string,
): Promise<boolean> {
  if (racineId === egliseId) return false;
  const { rows } = await db.query(
    `WITH RECURSIVE descendants AS (
       SELECT id FROM churches WHERE id = $1
       UNION ALL
       SELECT c.id FROM churches c JOIN descendants d ON c.parent_church_id = d.id
     )
     SELECT 1 FROM descendants WHERE id = $2`,
    [racineId, egliseId],
  );
  return (rows.length ?? 0) > 0;
}

export function registerAnnexesRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/annexes",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const q = ((req.query as { q?: string }).q ?? "").trim();
        const params: unknown[] = [req.session.churchId];
        let filtre = "";
        if (q) {
          params.push(`%${q}%`);
          filtre = ` AND (c.name ILIKE $2 OR c.code ILIKE $2 OR c.city ILIKE $2)`;
        }
        const { rows } = await db.query(
          `SELECT v.eglise_id, v.eglise_nom, v.niveau,
                  v.membres_actifs, v.nombre_contributions, v.total_fcfa,
                  c.code AS eglise_code, c.city AS eglise_ville,
                  c.status AS eglise_statut
             FROM v_rapports_consolides v
             JOIN churches c ON c.id = v.eglise_id
            WHERE v.eglise_mere_id = $1${filtre}
            ORDER BY v.niveau ASC, v.eglise_nom ASC`,
          params,
        );
        return reply.send({
          annexes: rows.map((r) => ({
            eglise_id: r.eglise_id,
            eglise_nom: r.eglise_nom,
            eglise_code: r.eglise_code,
            eglise_ville: r.eglise_ville,
            eglise_statut: r.eglise_statut,
            niveau: Number(r.niveau),
            membres_actifs: Number(r.membres_actifs),
            nombre_contributions: Number(r.nombre_contributions),
            total_fcfa: Number(r.total_fcfa),
          })),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/annexes/:id",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const id = (req.params as { id: string }).id;
        const { rows: eglises } = await db.query(
          `SELECT id, code, name, city, status, parent_church_id
             FROM churches WHERE id = $1`,
          [id],
        );
        const eglise = eglises[0];
        if (!eglise) {
          return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        }
        if (!(await estDescendante(db, req.session.churchId, id))) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Cette église n'est pas une de vos annexes.",
          });
        }
        const { rows: chiffres } = await db.query(
          `SELECT
             (SELECT count(*)::int FROM members m WHERE m.church_id = $1 AND m.status = 'actif') AS membres_actifs,
             (SELECT count(*)::int FROM contributions co
               WHERE co.church_id = $1 AND co.type IN ('dime','offrande','don') AND co.status = 'confirme') AS nombre_contributions,
             (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions co
               WHERE co.church_id = $1 AND co.type IN ('dime','offrande','don') AND co.status = 'confirme') AS total_fcfa,
             (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions co
               WHERE co.church_id = $1 AND co.type = 'depense' AND co.status = 'confirme') AS depenses_fcfa,
             (SELECT count(*)::int FROM cultes cu WHERE cu.church_id = $1) AS cultes,
             (SELECT count(*)::int FROM presences p WHERE p.church_id = $1) AS presences,
             (SELECT count(*)::int FROM announcements a WHERE a.church_id = $1) AS annonces`,
          [id],
        );
        const { rows: modulesRows } = await db.query<{ module: string; actif: boolean }>(
          `SELECT module, actif FROM eglise_modules WHERE church_id = $1`,
          [id],
        );
        const etats = new Map(modulesRows.map((r) => [r.module, r.actif]));
        const modules: (ModuleInfo & { actif: boolean })[] = [
          ...MODULES_NOYAU.map((m) => ({ ...m, actif: true })),
          ...MODULES_ACTIVABLES.map((m) => ({
            ...m,
            actif: etats.get(m.code) ?? false,
          })),
        ];
        const c = chiffres[0];
        return reply.send({
          eglise: {
            id: eglise.id,
            code: eglise.code,
            name: eglise.name,
            city: eglise.city,
            status: eglise.status,
            parent_church_id: eglise.parent_church_id,
          },
          membres_actifs: Number(c.membres_actifs),
          nombre_contributions: Number(c.nombre_contributions),
          total_fcfa: Number(c.total_fcfa),
          depenses_fcfa: Number(c.depenses_fcfa),
          cultes: Number(c.cultes),
          presences: Number(c.presences),
          annonces: Number(c.annonces),
          modules,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
