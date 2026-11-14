import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { invalidInput } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Module 12 — Administration : paramètres de l'église (coordonnées, logo,
 * comptes de paiement Wave / Orange / MTN), gestion des rôles par église,
 * lecture du journal d'audit.
 */

const ADMIN = ["admin_eglise"];
const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte"];

const parametresSchema = z.object({
  adresse: z.string().max(300).optional(),
  ville: z.string().max(120).optional(),
  telephone: z.string().min(8).max(30).optional(),
  email: z.string().email().max(254).optional(),
  logo_url: z.string().url().max(500).optional(),
  wave_numero: z.string().max(30).optional(),
  orange_numero: z.string().max(30).optional(),
  mtn_numero: z.string().max(30).optional(),
  devise: z.string().min(2).max(10).optional(),
  fuseau_horaire: z.string().max(60).optional(),
  // T10 : signataires configurables, vides par défaut. La règle de
  // signature (pasteur seul, conseil…) n'est pas tranchée : aucun
  // signataire n'est inventé, l'admin les renseigne ou les laisse vides.
  signataire_nominations: z.string().max(200).optional(),
  signataire_proces_verbaux: z.string().max(200).optional(),
  // T12 (US8, US11, US14) : dîme suggérée (vide = désactivée, jamais
  // imposée), transparence visible par les membres (désactivée par
  // défaut), seuils d'alerte pour l'église mère.
  montant_dime_suggere: z.number().int().min(0).max(100_000_000).nullable().optional(),
  transparence_visible_membres: z.boolean().optional(),
  seuil_inactivite_semaines: z.number().int().min(1).max(52).optional(),
  seuil_baisse_contributions_pct: z.number().int().min(0).max(100).optional(),
});

const roleSchema = z.object({
  role: z.enum(["admin_eglise", "tresorier", "responsable_culte", "membre"]),
});

export function registerParametresRoutes(app: FastifyInstance, db: Pool) {
  // -- Paramètres de mon église (une ligne par église, créée à la demande). --
  app.get(
    "/parametres",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT p.*, c.name AS eglise_nom, c.code AS eglise_code, c.city AS eglise_ville
             FROM eglise_parametres p
             JOIN churches c ON c.id = p.church_id
            WHERE p.church_id = $1`,
          [req.session.churchId],
        );
        if (rows.length === 0) {
          const { rows: churchRows } = await db.query(
            `SELECT name AS eglise_nom, code AS eglise_code, city AS eglise_ville
               FROM churches WHERE id = $1`,
            [req.session.churchId],
          );
          return reply.send({ ...(churchRows[0] ?? {}), devise: "FCFA", fuseau_horaire: "Africa/Abidjan" });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/parametres",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = parametresSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      const keys = Object.keys(data) as (keyof typeof data)[];
      if (keys.length === 0) {
        return reply.code(400).send({ error: "invalid_input", message: "Rien à modifier." });
      }
      try {
        const cols = ["church_id", ...keys];
        const insertPlaceholders = cols.map((_, i) => `$${i + 1}`).join(", ");
        const updates = keys.map((k, i) => `${k} = EXCLUDED.${k}`).join(", ");
        const values: unknown[] = [req.session.churchId, ...keys.map((k) => data[k] ?? null)];
        const { rows } = await db.query(
          `INSERT INTO eglise_parametres (${cols.join(", ")})
           VALUES (${insertPlaceholders})
           ON CONFLICT (church_id) DO UPDATE SET ${updates}, updated_at = now()
           RETURNING *`,
          values,
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "parametres.modifies",
          details: { champs: keys },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rôles : qui fait quoi dans mon église. --------------------------------
  app.get(
    "/parametres/roles",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT cu.user_id, cu.role, u.full_name, u.email
             FROM church_users cu
             JOIN users u ON u.id = cu.user_id
            WHERE cu.church_id = $1
            ORDER BY u.full_name ASC`,
          [req.session.churchId],
        );
        return reply.send({ roles: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/parametres/roles/:userId",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const parsed = roleSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const userId = (req.params as { userId: string }).userId;
      if (userId === req.session.userId) {
        return reply.code(400).send({ error: "invalid_input", message: "On ne change pas son propre rôle." });
      }
      try {
        const { rows } = await db.query(
          `UPDATE church_users SET role = $3
            WHERE user_id = $1 AND church_id = $2
            RETURNING user_id, role`,
          [userId, req.session.churchId, parsed.data.role],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Utilisateur introuvable dans votre église." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "role.modifie",
          details: { user_id: userId, role: parsed.data.role },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Journal d'audit de mon église (lecture seule, admin). -----------------
  app.get(
    "/parametres/audit",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      const limit = Math.min(Math.max(Number((req.query as { limit?: string }).limit ?? 50) || 50, 1), 100);
      const offset = Math.max(Number((req.query as { offset?: string }).offset ?? 0) || 0, 0);
      try {
        const { rows } = await db.query(
          `SELECT a.id, a.action, a.details, a.created_at, u.full_name AS utilisateur
             FROM audit_logs a
             LEFT JOIN users u ON u.id = a.user_id
            WHERE a.church_id = $1
            ORDER BY a.created_at DESC
            LIMIT $2 OFFSET $3`,
          [req.session.churchId, limit, offset],
        );
        return reply.send({ items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
