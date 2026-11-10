import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Rapports consolidés — admin de l'église mère seulement.
 * GET /rapports/consolide — chiffres de mon église + agrégats de chaque
 * sous-église (vue v_rapports_consolides : totaux uniquement, jamais le
 * détail nominatif d'une antenne).
 */
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

        // Agrégats de mes sous-églises directes (la vue ne couvre que les
        // églises qui ont une mère ; on ne remonte qu'un niveau ici).
        const { rows: sousEglises } = await db.query(
          `SELECT eglise_id, eglise_nom, membres_actifs, nombre_contributions, total_fcfa
             FROM v_rapports_consolides
            WHERE eglise_mere_id = $1
            ORDER BY eglise_nom ASC`,
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
}
