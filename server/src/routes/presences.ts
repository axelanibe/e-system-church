import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import {
  READ_ALL,
  WRITE_STD,
  existsInChurch,
  invalidInput,
  memberInChurch,
  registerCrud,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Module 3 — Présences : pointage aux cultes et réunions (manuel, liste,
 * scan QR de la carte de membre), statistiques par culte et par période.
 * La table `presences` complète `attendances` (événements génériques).
 */

const uuid = z.string().uuid();

export function registerPresencesRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/presences",
    table: "presences",
    columns: ["event_id", "culte_id", "member_id", "statut", "mode"],
    createSchema: z.object({
      event_id: uuid.optional(),
      culte_id: uuid.optional(),
      member_id: uuid,
      statut: z.enum(["present", "absent", "excuse"]).default("present"),
      mode: z.enum(["manuel", "liste", "scan_qr"]).default("manuel"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "presence",
    filters: { event_id: "event_id", culte_id: "culte_id", member_id: "member_id", statut: "statut" },
    orderBy: "pointe_at DESC",
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      if (!data.event_id && !data.culte_id) {
        return "Indiquez un culte ou un événement.";
      }
      if (data.event_id && !(await existsInChurch(db2, "events", churchId, data.event_id as string))) {
        return "Événement introuvable dans votre église.";
      }
      if (data.culte_id && !(await existsInChurch(db2, "cultes", churchId, data.culte_id as string))) {
        return "Culte introuvable dans votre église.";
      }
      return null;
    },
  });

  // -- Pointage : par matricule (scan QR) ou member_id ; crée ou met à jour
  //    le pointage (un seul pointage par membre et par culte / événement). --
  const pointerSchema = z.object({
    matricule: z.string().min(1).max(30).optional(),
    member_id: uuid.optional(),
    event_id: uuid.optional(),
    culte_id: uuid.optional(),
    statut: z.enum(["present", "absent", "excuse"]).default("present"),
    mode: z.enum(["manuel", "liste", "scan_qr"]).default("scan_qr"),
  });
  app.post(
    "/presences/pointer",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      const parsed = pointerSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      if (!data.matricule && !data.member_id) {
        return reply.code(400).send({ error: "invalid_input", message: "Matricule ou membre requis." });
      }
      if (!data.event_id && !data.culte_id) {
        return reply.code(400).send({ error: "invalid_input", message: "Culte ou événement requis." });
      }
      try {
        let memberId = data.member_id ?? null;
        let membreNom: string | null = null;
        if (!memberId && data.matricule) {
          const { rows } = await db.query(
            `SELECT id, full_name FROM members WHERE matricule = $1 AND church_id = $2`,
            [data.matricule, req.session.churchId],
          );
          if (rows.length === 0) {
            return reply.code(404).send({ error: "not_found", message: "Aucun membre avec ce matricule." });
          }
          memberId = rows[0].id as string;
          membreNom = rows[0].full_name as string;
        } else if (memberId) {
          const { rows } = await db.query(
            `SELECT full_name FROM members WHERE id = $1 AND church_id = $2`,
            [memberId, req.session.churchId],
          );
          if (rows.length === 0) {
            return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
          }
          membreNom = rows[0].full_name as string;
        }
        const { rows } = await db.query(
          `INSERT INTO presences (church_id, event_id, culte_id, member_id, statut, mode, pointe_par)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           ON CONFLICT (member_id, event_id) WHERE event_id IS NOT NULL
             DO UPDATE SET statut = EXCLUDED.statut, mode = EXCLUDED.mode, pointe_at = now(), pointe_par = EXCLUDED.pointe_par
           RETURNING *`,
          [
            req.session.churchId,
            data.event_id ?? null,
            data.culte_id ?? null,
            memberId,
            data.statut,
            data.mode,
            req.session.userId,
          ],
        ).catch(async () => {
          // Conflit sur le culte (l'index partiel event_id ne s'applique pas).
          return db.query(
            `INSERT INTO presences (church_id, event_id, culte_id, member_id, statut, mode, pointe_par)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (member_id, culte_id) WHERE culte_id IS NOT NULL
               DO UPDATE SET statut = EXCLUDED.statut, mode = EXCLUDED.mode, pointe_at = now(), pointe_par = EXCLUDED.pointe_par
             RETURNING *`,
            [
              req.session.churchId,
              data.event_id ?? null,
              data.culte_id ?? null,
              memberId,
              data.statut,
              data.mode,
              req.session.userId,
            ],
          );
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "presence.pointee",
          details: { membre_id: memberId, statut: data.statut, mode: data.mode },
        });
        return reply.send({ ...rows[0], membre_nom: membreNom });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Statistiques : taux de présence par culte et par période. -----------
  const statsQuerySchema = z.object({
    from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  });
  app.get(
    "/presences/stats",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const parsed = statsQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { from, to } = parsed.data;
      try {
        const conditions = [`p.church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (from) {
          values.push(from);
          conditions.push(`p.pointe_at >= $${values.length}::date`);
        }
        if (to) {
          values.push(to);
          conditions.push(`p.pointe_at < ($${values.length}::date + interval '1 day')`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const { rows: global } = await db.query(
          `SELECT count(*)::int AS total,
                  count(*) FILTER (WHERE statut = 'present')::int AS presents,
                  count(*) FILTER (WHERE statut = 'absent')::int AS absents,
                  count(*) FILTER (WHERE statut = 'excuse')::int AS excuses
             FROM presences p ${where}`,
          values,
        );
        const { rows: parCulte } = await db.query(
          `SELECT p.culte_id, c.titre AS culte_titre, c.date_heure,
                  count(*)::int AS total,
                  count(*) FILTER (WHERE p.statut = 'present')::int AS presents
             FROM presences p
             LEFT JOIN cultes c ON c.id = p.culte_id
             ${where} AND p.culte_id IS NOT NULL
            GROUP BY p.culte_id, c.titre, c.date_heure
            ORDER BY c.date_heure DESC
            LIMIT 20`,
          values,
        );
        const { rows: parMembre } = await db.query(
          `SELECT p.member_id, m.full_name AS membre_nom, m.matricule AS membre_matricule,
                  count(*)::int AS total,
                  count(*) FILTER (WHERE p.statut = 'present')::int AS presents
             FROM presences p
             JOIN members m ON m.id = p.member_id
             ${where}
            GROUP BY p.member_id, m.full_name, m.matricule
            ORDER BY presents DESC
            LIMIT 20`,
          values,
        );
        return reply.send({ global: global[0], par_culte: parCulte, par_membre: parMembre });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
