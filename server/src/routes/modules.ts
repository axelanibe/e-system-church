import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { invalidInput } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import {
  MODULES_ACTIVABLES,
  MODULES_NOYAU,
  estModuleActivable,
  libelleModule,
  type ModuleInfo,
} from "../modules.js";

/**
 * US1 — Modules activables par église.
 *
 * GET   /modules            — modules de l'église de la session (noyau
 *                             toujours actif + activables avec leur état).
 * PATCH /modules/:code      — active ou désactive un module (admin_eglise
 *                             seulement, journalisé dans audit_logs).
 * Chaque église décide seule pour elle-même ; la mère ne force pas ses
 * antennes. Désactiver ne supprime aucune donnée : réactiver restaure
 * l'accès à l'identique.
 */

const moduleSchema = z.object({
  actif: z.boolean(),
});

export function registerModulesRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/modules",
    { preHandler: [requireAuth(db)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query<{ module: string; actif: boolean }>(
          `SELECT module, actif FROM eglise_modules WHERE church_id = $1`,
          [req.session.churchId],
        );
        const etats = new Map(rows.map((r) => [r.module, r.actif]));
        const modules: (ModuleInfo & { actif: boolean })[] = [
          ...MODULES_NOYAU.map((m) => ({ ...m, actif: true })),
          ...MODULES_ACTIVABLES.map((m) => ({
            ...m,
            actif: etats.get(m.code) ?? false,
          })),
        ];
        return reply.send({ modules });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/modules/:code",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const code = (req.params as { code: string }).code;
      if (!estModuleActivable(code)) {
        return reply.code(400).send({
          error: "invalid_value",
          message: `Module « ${code} » inconnu ou non désactivable.`,
        });
      }
      const parsed = moduleSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const { rows } = await db.query<{ module: string; actif: boolean }>(
          `INSERT INTO eglise_modules (church_id, module, actif)
           VALUES ($1, $2, $3)
           ON CONFLICT (church_id, module)
           DO UPDATE SET actif = EXCLUDED.actif, updated_at = now()
           RETURNING module, actif`,
          [req.session.churchId, code, parsed.data.actif],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "modules.modifie",
          details: { module: code, actif: parsed.data.actif },
        });
        return reply.send({
          code: rows[0].module,
          label: libelleModule(code),
          noyau: false,
          actif: rows[0].actif,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
