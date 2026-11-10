import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog, generateMatricule } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Membres de l'église de la session (isolation stricte par church_id).
 * GET  /membres     — liste + recherche (nom / matricule) + filtres.
 * GET  /membres/:id — un membre (404 s'il appartient à une autre église).
 * POST /membres     — création (admin_eglise, responsable_culte).
 *                      Le trésorier ne peut PAS créer de membre ; le matricule
 *                      est généré automatiquement (M-0001…) sauf s'il est fourni.
 */

const createMembreSchema = z.object({
  full_name: z.string().min(2).max(200),
  phone: z.string().min(8).max(30).optional(),
  email: z.string().email().max(254).optional(),
  birth_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").optional(),
  department: z.string().min(2).max(120).optional(),
  cell_group: z.string().min(2).max(120).optional(),
  status: z.enum(["actif", "nouveau_converti", "inactif"]).default("actif"),
  matricule: z.string().min(1).max(30).optional(),
});

const listQuerySchema = z.object({
  q: z.string().max(200).optional(),
  department: z.string().max(120).optional(),
  status: z.enum(["actif", "nouveau_converti", "inactif"]).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte", "membre"];
const WRITE_ROLES = ["admin_eglise", "responsable_culte"];

export function registerMembresRoutes(app: FastifyInstance, db: Pool) {
  app.get("/membres", { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] }, async (req, reply) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Paramètres de recherche invalides.",
        details: parsed.error.issues.map((i) => i.message),
      });
    }
    const { q, department, status, limit, offset } = parsed.data;
    try {
      const conditions = [`church_id = $1`];
      const values: unknown[] = [req.session.churchId];
      if (q) {
        values.push(`%${q}%`);
        conditions.push(`(full_name ILIKE $${values.length} OR matricule ILIKE $${values.length})`);
      }
      if (department) {
        values.push(department);
        conditions.push(`department = $${values.length}`);
      }
      if (status) {
        values.push(status);
        conditions.push(`status = $${values.length}`);
      }
      const where = `WHERE ${conditions.join(" AND ")}`;
      const total = await db.query<{ n: string }>(
        `SELECT count(*)::text AS n FROM members ${where}`,
        values,
      );
      const { rows } = await db.query(
        `SELECT id, church_id, matricule, full_name, phone, email, birth_date,
                department, cell_group, status, created_at
           FROM members ${where}
          ORDER BY full_name ASC
          LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
        [...values, limit, offset],
      );
      return reply.send({ total: Number(total.rows[0]?.n ?? 0), membres: rows });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  app.get(
    "/membres/:id",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, church_id, matricule, full_name, phone, email, birth_date,
                  department, cell_group, status, created_at
             FROM members WHERE id = $1 AND church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post("/membres", { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] }, async (req, reply) => {
    const parsed = createMembreSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Données du membre invalides.",
        details: parsed.error.issues.map((i) => i.message),
      });
    }
    const data = parsed.data;
    try {
      // Matricule : fourni par le client ou généré (séquentiel par église).
      // Réessaie en cas de collision (contrainte UNIQUE church_id + matricule).
      let lastError: unknown = null;
      for (let attempt = 0; attempt < 3; attempt++) {
        const matricule = data.matricule ?? (await generateMatricule(db, req.session.churchId));
        try {
          const { rows } = await db.query(
            `INSERT INTO members
               (church_id, matricule, full_name, phone, email, birth_date, department, cell_group, status)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
             RETURNING id, church_id, matricule, full_name, phone, email, birth_date,
                       department, cell_group, status, created_at`,
            [
              req.session.churchId,
              matricule,
              data.full_name,
              data.phone ?? null,
              data.email ?? null,
              data.birth_date ?? null,
              data.department ?? null,
              data.cell_group ?? null,
              data.status,
            ],
          );
          await auditLog(db, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "membre.cree",
            details: { membre_id: rows[0].id, matricule, nom: data.full_name },
          });
          return reply.code(201).send(rows[0]);
        } catch (e) {
          const code = (e as { code?: string }).code;
          if (code === "23505" && !data.matricule) {
            lastError = e; // collision sur le matricule généré : on régénère.
            continue;
          }
          throw e;
        }
      }
      throw lastError ?? new Error("Création du membre impossible.");
    } catch (e) {
      return dbError(reply, e);
    }
  });
}
