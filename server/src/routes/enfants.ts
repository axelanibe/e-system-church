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
import { requireModule } from "../modules.js";

/**
 * Module 8 — Enfants et jeunesse : école du dimanche (classes par âge,
 * enseignants), autorisations parentales de sortie, activités jeunesse.
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

export function registerEnfantsRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/classes-enfants",
    module: "enfants",
    table: "classes_enfants",
    columns: ["nom", "age_min", "age_max", "salle"],
    createSchema: z.object({
      nom: z.string().min(2).max(120),
      age_min: z.number().int().min(0).max(18).optional(),
      age_max: z.number().int().min(0).max(18).optional(),
      salle: z.string().max(120).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "classe_enfant",
    searchColumn: "nom",
  });

  registerCrud(app, db, {
    base: "/enseignants-classes",
    module: "enfants",
    table: "enseignants_classes",
    columns: ["classe_id", "member_id", "role"],
    createSchema: z.object({
      classe_id: uuid,
      member_id: uuid,
      role: z.enum(["enseignant", "assistant"]).default("enseignant"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "enseignant_classe",
    filters: { classe_id: "classe_id", member_id: "member_id" },
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "classes_enfants", churchId, data.classe_id as string))) {
        return "Classe introuvable dans votre église.";
      }
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/autorisations-sorties",
    module: "enfants",
    table: "autorisations_sorties",
    columns: ["enfant_member_id", "parent_member_id", "activite", "date_sortie", "statut"],
    createSchema: z.object({
      enfant_member_id: uuid,
      parent_member_id: uuid.optional(),
      activite: z.string().min(2).max(300),
      date_sortie: z.string().regex(dateRe, "Date au format AAAA-MM-JJ."),
      statut: z.enum(["en_attente", "autorisee", "refusee"]).default("en_attente"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "autorisation_sortie",
    filters: { enfant_member_id: "enfant_member_id", statut: "statut" },
    orderBy: "date_sortie ASC",
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.enfant_member_id as string))) {
        return "Cet enfant n'appartient pas à votre église.";
      }
      if (data.parent_member_id && !(await memberInChurch(db2, churchId, data.parent_member_id as string))) {
        return "Le parent n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/activites-jeunesse",
    module: "enfants",
    table: "activites_jeunesse",
    columns: ["titre", "description", "date_activite", "lieu", "responsable_member_id"],
    createSchema: z.object({
      titre: z.string().min(2).max(200),
      description: z.string().max(1000).optional(),
      date_activite: z.string().min(10).max(40),
      lieu: z.string().max(200).optional(),
      responsable_member_id: uuid.optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "activite_jeunesse",
    searchColumn: "titre",
    orderBy: "date_activite ASC",
    validate: async (db2, churchId, data) => {
      if (data.responsable_member_id && !(await memberInChurch(db2, churchId, data.responsable_member_id as string))) {
        return "Le responsable n'appartient pas à votre église.";
      }
      return null;
    },
  });

  // -- Check-ins enfants, double QR ECODIM ------------------------------------
  // Arrivée jumelée : QR parent (matricule) + QR enfant (code #KIDS-XXXX).
  // Le lien parent-enfant doit être validé dans `liens_parent_enfant`.
  // Sortie sécurisée : même code enfant, présenté par le même parent.
  // Alerte silencieuse : enregistrement en base seulement, pas de SMS ni
  // de notification push (canal SMS = Lot B).
  const lecture = [requireAuth(db), requireModule(db, "enfants"), requireRole(...READ_ALL)];
  const ecriture = [requireAuth(db), requireModule(db, "enfants"), requireRole(...WRITE_STD)];
  const codeEnfantRe = /^KIDS-[A-Z0-9]{4}$/;

  /** Matricule parent depuis un QR de bracelet : `CODE_EGLISE:MATRICULE` ou matricule seul. */
  function matriculeParent(codeParent: string): string {
    const brut = codeParent.trim().toUpperCase();
    const deuxPoints = brut.indexOf(":");
    return (deuxPoints < 0 ? brut : brut.slice(deuxPoints + 1).trim());
  }

  const checkinSchema = z.object({
    enfant_member_id: uuid,
    parent_member_id: uuid,
    code_parent: z.string().min(1).max(120),
    code_enfant: z.string().regex(codeEnfantRe, "Code enfant au format KIDS-XXXX."),
    salle: z.string().max(120).optional(),
    allergie: z.string().max(500).optional(),
  });

  app.post("/checkins-enfants/checkin", { preHandler: ecriture }, async (req, reply) => {
    const parsed = checkinSchema.safeParse(req.body);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const { enfant_member_id, parent_member_id, code_parent, code_enfant, salle, allergie } = parsed.data;
    const churchId = req.session.churchId;
    try {
      if (!(await memberInChurch(db, churchId, enfant_member_id))) {
        return reply.code(403).send({ error: "forbidden", message: "Cet enfant n'appartient pas à votre église." });
      }
      if (!(await memberInChurch(db, churchId, parent_member_id))) {
        return reply.code(403).send({ error: "forbidden", message: "Ce parent n'appartient pas à votre église." });
      }
      const parent = await db.query(
        `SELECT matricule FROM members WHERE id = $1 AND church_id = $2`,
        [parent_member_id, churchId],
      );
      if (parent.rows[0].matricule !== matriculeParent(code_parent)) {
        return reply.code(403).send({ error: "forbidden", message: "Le code parent ne correspond pas à ce parent." });
      }
      const lien = await db.query(
        `SELECT 1 FROM liens_parent_enfant
          WHERE church_id = $1 AND parent_member_id = $2 AND enfant_member_id = $3 AND statut = 'valide'`,
        [churchId, parent_member_id, enfant_member_id],
      );
      if ((lien.rowCount ?? 0) === 0) {
        return reply.code(403).send({ error: "forbidden", message: "Aucun lien parent-enfant validé pour cet enfant." });
      }
      const { rows } = await db.query(
        `INSERT INTO checkins_enfants
           (church_id, enfant_member_id, parent_member_id, salle, code_enfant, allergie)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
        [churchId, enfant_member_id, parent_member_id, salle ?? null, code_enfant, allergie ?? null],
      );
      await auditLog(db, {
        churchId,
        userId: req.session.userId,
        action: "checkin_enfant.cree",
        details: { id: rows[0].id, enfant_member_id, salle: salle ?? null },
      });
      return reply.code(201).send(rows[0]);
    } catch (e) {
      return dbError(reply, e);
    }
  });

  const sortieSchema = z.object({
    code_enfant: z.string().regex(codeEnfantRe, "Code enfant au format KIDS-XXXX."),
    code_parent: z.string().min(1).max(120),
  });

  app.post("/checkins-enfants/:id/sortie", { preHandler: ecriture }, async (req, reply) => {
    const parsed = sortieSchema.safeParse(req.body);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const id = (req.params as { id: string }).id;
    const churchId = req.session.churchId;
    try {
      const { rows } = await db.query(
        `SELECT c.*, m.matricule AS parent_matricule FROM checkins_enfants c
           JOIN members m ON m.id = c.parent_member_id
          WHERE c.id = $1 AND c.church_id = $2`,
        [id, churchId],
      );
      if (rows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Check-in introuvable." });
      }
      const checkin = rows[0];
      if (checkin.statut === "CHECKED_OUT") {
        return reply.code(409).send({ error: "already_checked_out", message: "Cet enfant est déjà sorti." });
      }
      if (
        checkin.code_enfant !== parsed.data.code_enfant ||
        checkin.parent_matricule !== matriculeParent(parsed.data.code_parent)
      ) {
        return reply.code(403).send({ error: "forbidden", message: "Code enfant ou code parent incorrect." });
      }
      const sortis = await db.query(
        `UPDATE checkins_enfants
            SET statut = 'CHECKED_OUT', checked_out_at = now()
          WHERE id = $1 AND church_id = $2 AND statut = 'IN_CLASS'
          RETURNING *`,
        [id, churchId],
      );
      if (sortis.rows.length === 0) {
        return reply.code(409).send({ error: "already_checked_out", message: "Cet enfant est déjà sorti." });
      }
      await auditLog(db, {
        churchId,
        userId: req.session.userId,
        action: "checkin_enfant.sortie",
        details: { id },
      });
      return reply.send(sortis.rows[0]);
    } catch (e) {
      return dbError(reply, e);
    }
  });

  const alerteSchema = z.object({
    message: z.string().min(1).max(500),
  });

  app.post("/checkins-enfants/:id/alerte", { preHandler: ecriture }, async (req, reply) => {
    const parsed = alerteSchema.safeParse(req.body);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const id = (req.params as { id: string }).id;
    const churchId = req.session.churchId;
    try {
      const { rows } = await db.query(
        `UPDATE checkins_enfants
            SET alerte = TRUE, alerte_message = $3, alerte_at = now()
          WHERE id = $1 AND church_id = $2 AND statut = 'IN_CLASS'
          RETURNING *`,
        [id, churchId, parsed.data.message],
      );
      if (rows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Check-in introuvable ou enfant déjà sorti." });
      }
      await auditLog(db, {
        churchId,
        userId: req.session.userId,
        action: "checkin_enfant.alerte",
        details: { id },
      });
      return reply.send(rows[0]);
    } catch (e) {
      return dbError(reply, e);
    }
  });

  const jourSchema = z.object({
    date: z.string().regex(dateRe, "Date au format AAAA-MM-JJ.").optional(),
    salle: z.string().max(120).optional(),
  });

  app.get("/checkins-enfants/jour", { preHandler: lecture }, async (req, reply) => {
    const parsed = jourSchema.safeParse(req.query);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const churchId = req.session.churchId;
    try {
      const { rows } = await db.query(
        `SELECT c.*, e.full_name AS enfant_nom, p.full_name AS parent_nom
           FROM checkins_enfants c
           JOIN members e ON e.id = c.enfant_member_id
           JOIN members p ON p.id = c.parent_member_id
          WHERE c.church_id = $1
            AND c.date_checkin = COALESCE($2, CURRENT_DATE)
            AND ($3::text IS NULL OR c.salle = $3)
          ORDER BY c.checked_in_at ASC`,
        [churchId, parsed.data.date ?? null, parsed.data.salle ?? null],
      );
      return reply.send({ total: rows.length, items: rows });
    } catch (e) {
      return dbError(reply, e);
    }
  });
}
