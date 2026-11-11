import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { invalidInput } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Module 11 — Rapports et statistiques : tableau de bord par église
 * (vue v_stats_eglise), consolidation mère (totaux par antenne),
 * export CSV des membres.
 */

const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte"];

export function registerStatsRoutes(app: FastifyInstance, db: Pool) {
  // -- Statistiques globales de mon église (+ réseau si je suis une mère). --
  app.get(
    "/stats/globales",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT * FROM v_stats_eglise WHERE eglise_id = $1`,
          [req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        }
        const { rows: reseau } = await db.query(
          `SELECT eglise_id, eglise_nom, membres_actifs, nombre_contributions, total_fcfa
             FROM v_rapports_consolides
            WHERE eglise_mere_id = $1
            ORDER BY eglise_nom ASC`,
          [req.session.churchId],
        );
        return reply.send({ eglise: rows[0], reseau });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Export CSV : membres de mon église (matricule, nom, contacts,
  //    département, cellule, statut) ou contributions confirmées. ----------
  const exportQuerySchema = z.object({
    type: z.enum(["membres", "contributions"]).default("membres"),
  });
  app.get(
    "/stats/export",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      const parsed = exportQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const csvCell = (value: unknown): string => {
          const text = value === null || value === undefined ? "" : String(value);
          return `"${text.replace(/"/g, '""')}"`;
        };
        if (parsed.data.type === "contributions") {
          const { rows } = await db.query(
            `SELECT c.created_at, c.type, c.amount_fcfa, c.payment_method,
                    c.payment_ref, c.status, m.full_name AS membre_nom, m.matricule
               FROM contributions c
               LEFT JOIN members m ON m.id = c.member_id
              WHERE c.church_id = $1
              ORDER BY c.created_at DESC`,
            [req.session.churchId],
          );
          const lines = ["date;type;montant_fcfa;moyen_paiement;reference;statut;membre;matricule"];
          for (const r of rows) {
            lines.push(
              [
                (r.created_at as Date).toISOString().slice(0, 10),
                r.type,
                r.amount_fcfa,
                r.payment_method,
                r.payment_ref,
                r.status,
                r.membre_nom,
                r.matricule,
              ]
                .map(csvCell)
                .join(";"),
            );
          }
          return reply.type("text/csv; charset=utf-8").send(lines.join("\n"));
        }
        const { rows } = await db.query(
          `SELECT matricule, full_name, phone, email, birth_date,
                  department, cell_group, status
             FROM members WHERE church_id = $1 ORDER BY full_name ASC`,
          [req.session.churchId],
        );
        const lines = ["matricule;nom;telephone;email;naissance;departement;cellule;statut"];
        for (const r of rows) {
          lines.push(
            [
              r.matricule,
              r.full_name,
              r.phone,
              r.email,
              r.birth_date,
              r.department,
              r.cell_group,
              r.status,
            ]
              .map(csvCell)
              .join(";"),
          );
        }
        return reply.type("text/csv; charset=utf-8").send(lines.join("\n"));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
