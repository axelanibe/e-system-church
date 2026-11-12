import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Annonces.
 * POST /annonces — admin de l'église. broadcast=true : l'annonce est
 *                  diffusée à tout le réseau (visible par les sous-églises).
 * GET  /annonces — mes annonces + celles diffusées par mes églises mères
 *                  (ancêtres dans l'arborescence).
 */

const createSchema = z.object({
  title: z.string().min(2).max(200),
  body: z.string().min(2).max(5000),
  broadcast: z.boolean().default(false),
});

export function registerAnnoncesRoutes(app: FastifyInstance, db: Pool) {
  app.post(
    "/annonces",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = createSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données de l'annonce invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { title, body, broadcast } = parsed.data;
      try {
        const { rows } = await db.query(
          `INSERT INTO announcements (church_id, title, body, broadcast, created_by)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, church_id, title, body, broadcast, created_at`,
          [req.session.churchId, title, body, broadcast, req.session.userId],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "annonce.publiee",
          details: { annonce_id: rows[0].id, broadcast },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get("/annonces", { preHandler: [requireAuth(db)] }, async (req, reply) => {
    try {
      // Ma propre église + toutes ses mères (ancêtres) : leurs annonces
      // diffusées (broadcast=true) me parviennent ; les autres restent locales.
      const { rows } = await db.query(
        `WITH RECURSIVE ancetres AS (
           SELECT id, parent_church_id FROM churches WHERE id = $1
           UNION ALL
           SELECT c.id, c.parent_church_id
             FROM churches c
             JOIN ancetres a ON c.id = a.parent_church_id
         )
         SELECT an.id, an.title, an.body, an.broadcast, an.created_at,
                an.church_id, ch.name AS eglise_nom
           FROM announcements an
           JOIN churches ch ON ch.id = an.church_id
          WHERE an.church_id = $1
             OR (an.church_id IN (SELECT id FROM ancetres) AND an.broadcast = TRUE)
          ORDER BY an.created_at DESC
          LIMIT 100`,
        [req.session.churchId],
      );
      return reply.send({ annonces: rows });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Suppression d'une annonce (admin de l'église propriétaire). ----------
  app.delete(
    "/annonces/:id",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `DELETE FROM announcements WHERE id = $1 AND church_id = $2 RETURNING id`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Annonce introuvable." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "annonce.supprimee",
          details: { annonce_id: rows[0].id },
        });
        return reply.send({ ok: true, id: rows[0].id });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
