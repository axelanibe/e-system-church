import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Plateforme — super_admin seulement (tranche symbiose, 10 novembre 2026).
 * GET /plateforme/chiffres — chiffres globaux seulement : nombre d'églises
 * mères, nombre total de branches, membres actifs au total, contributions
 * confirmées au total. Aucun détail nominatif, aucune liste de membres,
 * aucune gestion des membres au jour le jour : la plateforme ne voit que
 * les chiffres. Le rôle super_admin existe depuis la fondation, mais il
 * était hors périmètre MVP ; cette route est son premier écran.
 */
export function registerPlateformeRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/plateforme/chiffres",
    { preHandler: [requireAuth(db), requireRole("super_admin")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT
             (SELECT count(*)::int FROM churches WHERE parent_church_id IS NULL) AS eglises_meres,
             (SELECT count(*)::int FROM churches WHERE parent_church_id IS NOT NULL) AS branches,
             (SELECT count(*)::int FROM churches) AS eglises_total,
             (SELECT count(*)::int FROM members WHERE status = 'actif') AS membres_actifs,
             (SELECT count(*)::int FROM contributions
               WHERE type IN ('dime','offrande','don') AND status = 'confirme') AS nombre_contributions,
             (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions
               WHERE type IN ('dime','offrande','don') AND status = 'confirme') AS total_contributions_fcfa,
             (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions
               WHERE type = 'depense' AND status = 'confirme') AS depenses_fcfa`,
        );
        const chiffres = rows[0];

        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "plateforme.chiffres_consultes",
          details: {},
        });

        return reply.send({ chiffres });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
