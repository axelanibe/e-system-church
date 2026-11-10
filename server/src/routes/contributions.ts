import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Finances de l'église de la session (dons sur le compte de CHAQUE église,
 * jamais centralisés — décision de Bouf). Enregistrement manuel avec
 * référence Mobile Money en MVP (pas de webhook Wave / Orange / MTN).
 * GET   /contributions      — liste + filtres + totaux par type (confirmées).
 * GET   /contributions/:id  — une contribution = son reçu simple.
 * POST  /contributions      — enregistrer (admin_eglise, tresorier).
 * PATCH /contributions/:id/statut — confirmer / annuler (admin_eglise, tresorier).
 * Le rôle « membre » simple n'a PAS accès aux finances (403).
 */

const createSchema = z.object({
  type: z.enum(["dime", "offrande", "don", "depense"]),
  amount_fcfa: z.number().int().positive().max(100_000_000),
  payment_method: z.enum(["wave", "orange_money", "mtn_momo", "especes", "virement"]),
  payment_ref: z.string().min(1).max(120).optional(),
  member_id: z.string().uuid().optional(),
  note: z.string().max(500).optional(),
});

const statutSchema = z.object({
  status: z.enum(["confirme", "annule"]),
});

const listQuerySchema = z.object({
  type: z.enum(["dime", "offrande", "don", "depense"]).optional(),
  status: z.enum(["en_attente", "confirme", "annule"]).optional(),
  member_id: z.string().uuid().optional(),
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte"];
const WRITE_ROLES = ["admin_eglise", "tresorier"];

export function registerContributionsRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/contributions",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      const parsed = listQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Paramètres de recherche invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { type, status, member_id, from, to, limit, offset } = parsed.data;
      try {
        const conditions = [`c.church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (type) {
          values.push(type);
          conditions.push(`c.type = $${values.length}`);
        }
        if (status) {
          values.push(status);
          conditions.push(`c.status = $${values.length}`);
        }
        if (member_id) {
          values.push(member_id);
          conditions.push(`c.member_id = $${values.length}`);
        }
        if (from) {
          values.push(from);
          conditions.push(`c.created_at >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(`c.created_at < ($${values.length}::date + interval '1 day')`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;

        const { rows } = await db.query(
          `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.payment_ref,
                  c.status, c.note, c.created_at,
                  c.member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule
             FROM contributions c
             LEFT JOIN members m ON m.id = c.member_id
             ${where}
            ORDER BY c.created_at DESC
            LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
          [...values, limit, offset],
        );
        // Totaux par type, contributions confirmées uniquement.
        const { rows: totauxRows } = await db.query(
          `SELECT c.type, coalesce(sum(c.amount_fcfa), 0)::int AS total_fcfa,
                  count(*)::int AS nombre
             FROM contributions c ${where} AND c.status = 'confirme'
            GROUP BY c.type`,
          values,
        );
        const totaux: Record<string, { total_fcfa: number; nombre: number }> = {};
        for (const t of totauxRows) totaux[t.type as string] = { total_fcfa: t.total_fcfa, nombre: t.nombre };
        return reply.send({ contributions: rows, totaux });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/contributions/:id",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT c.id, c.type, c.amount_fcfa, c.payment_method, c.payment_ref,
                  c.status, c.note, c.created_at,
                  c.member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule,
                  ch.name AS eglise_nom, ch.code AS eglise_code
             FROM contributions c
             LEFT JOIN members m ON m.id = c.member_id
             JOIN churches ch ON ch.id = c.church_id
            WHERE c.id = $1 AND c.church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Contribution introuvable." });
        }
        // Reçu simple : la contribution elle-même fait office de reçu.
        return reply.send({ recu: rows[0] });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/contributions",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = createSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données de la contribution invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const data = parsed.data;
      try {
        // Le membre éventuel doit appartenir à mon église.
        if (data.member_id) {
          const member = await db.query(
            `SELECT id FROM members WHERE id = $1 AND church_id = $2`,
            [data.member_id, req.session.churchId],
          );
          if (member.rowCount === 0) {
            return reply.code(400).send({
              error: "invalid_reference",
              message: "Ce membre n'appartient pas à votre église.",
            });
          }
        }
        const { rows } = await db.query(
          `INSERT INTO contributions
             (church_id, member_id, type, amount_fcfa, payment_method, payment_ref, status, received_by, note)
           VALUES ($1, $2, $3, $4, $5, $6, 'en_attente', $7, $8)
           RETURNING id, church_id, member_id, type, amount_fcfa, payment_method,
                     payment_ref, status, note, created_at`,
          [
            req.session.churchId,
            data.member_id ?? null,
            data.type,
            data.amount_fcfa,
            data.payment_method,
            data.payment_ref ?? null,
            req.session.userId,
            data.note ?? null,
          ],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "contribution.enregistree",
          details: { contribution_id: rows[0].id, type: data.type, amount_fcfa: data.amount_fcfa },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/contributions/:id/statut",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = statutSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Statut invalide (confirme ou annule).",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const { rows } = await db.query(
          `UPDATE contributions SET status = $3
            WHERE id = $1 AND church_id = $2 AND status = 'en_attente'
            RETURNING id, type, amount_fcfa, status`,
          [(req.params as { id: string }).id, req.session.churchId, parsed.data.status],
        );
        if (rows.length === 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Contribution introuvable, ou déjà confirmée / annulée.",
          });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: `contribution.${parsed.data.status === "confirme" ? "confirmee" : "annulee"}`,
          details: { contribution_id: rows[0].id, type: rows[0].type, amount_fcfa: rows[0].amount_fcfa },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
