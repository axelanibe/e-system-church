import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { dbError, requireAuth } from "../middleware.js";
import { gardeMessagerie } from "./messagerie.js";
import { ficheMembre } from "../messagerie_commun.js";

/**
 * Tranche Notifications push FCM — jetons d'appareil (table
 * device_tokens, migration 035). Un membre n'enregistre, ne liste et
 * ne retire que ses propres jetons, dans sa propre église : un membre
 * d'une autre église ne voit rien (liste vide, 404 au retrait).
 * Le jeton FCM complet n'est jamais renvoyé au client, seulement ses
 * 8 derniers caractères, pour reconnaître l'appareil.
 */

const enregistrerJetonSchema = z.object({
  token: z.string().min(10).max(4096),
  platform: z.enum(["web", "android"]),
});

const retirerJetonSchema = z.object({
  token: z.string().min(1).max(4096),
});

function suffixeJeton(token: string): string {
  return token.slice(-8);
}

export function registerNotificationsPushRoutes(app: FastifyInstance, db: Pool) {
  const auth = requireAuth(db);

  // -- POST /messagerie/jetons : enregistrer (ou réactiver) un jeton.
  // Un même jeton présenté par un autre membre lui est réattribué : un
  // jeton FCM désigne un appareil, pas un compte, et celui qui le
  // présente le détient. 201 à la création, 200 à la réactivation.
  app.post(
    "/messagerie/jetons",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const parsed = enregistrerJetonSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Jeton invalide : jeton de 10 à 4096 caractères et plateforme « web » ou « android ».",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) {
          return reply.code(403).send({
            error: "forbidden",
            message:
              "Votre compte n'est pas lié à une fiche membre : impossible d'enregistrer un jeton.",
          });
        }
        const { rows: membreRows } = await db.query<{ church_id: string }>(
          `SELECT church_id FROM members WHERE id = $1`,
          [memberId],
        );
        if (membreRows.length === 0 || membreRows[0].church_id !== req.session.churchId) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Votre fiche membre n'appartient pas à cette église.",
          });
        }
        const { rows } = await db.query(
          `INSERT INTO device_tokens (member_id, church_id, token, platform, last_used_at)
           VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (token) DO UPDATE SET
             member_id = EXCLUDED.member_id,
             church_id = EXCLUDED.church_id,
             platform = EXCLUDED.platform,
             is_active = true,
             last_used_at = NOW()
           RETURNING id, platform, created_at, last_used_at, is_active,
             (xmax = 0) AS cree`,
          [memberId, req.session.churchId, parsed.data.token, parsed.data.platform],
        );
        const ligne = rows[0];
        return reply.code(ligne.cree ? 201 : 200).send({
          id: ligne.id,
          platform: ligne.platform,
          created_at: ligne.created_at,
          last_used_at: ligne.last_used_at,
          is_active: ligne.is_active,
          token_suffix: suffixeJeton(parsed.data.token),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- GET /messagerie/jetons : jetons de l'appelant, dans son église.
  app.get(
    "/messagerie/jetons",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) return reply.send([]);
        const { rows } = await db.query(
          `SELECT id, platform, created_at, last_used_at, is_active,
                  RIGHT(token, 8) AS token_suffix
             FROM device_tokens
            WHERE church_id = $1 AND member_id = $2
            ORDER BY created_at DESC`,
          [req.session.churchId, memberId],
        );
        return reply.send(rows);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- DELETE /messagerie/jetons : retirer un de ses propres jetons.
  // 404 quand le jeton n'existe pas dans le périmètre de l'appelant,
  // sans révéler s'il existe ailleurs.
  app.delete(
    "/messagerie/jetons",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const parsed = retirerJetonSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Jeton invalide : jeton à retirer requis.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) {
          return reply.code(404).send({ error: "not_found", message: "Jeton introuvable." });
        }
        const { rowCount } = await db.query(
          `DELETE FROM device_tokens
            WHERE token = $1 AND church_id = $2 AND member_id = $3`,
          [parsed.data.token, req.session.churchId, memberId],
        );
        if (rowCount === 0) {
          return reply.code(404).send({ error: "not_found", message: "Jeton introuvable." });
        }
        return reply.code(204).send();
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
