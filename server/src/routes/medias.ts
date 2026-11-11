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
 * Module 9 — Médias et enseignements : prédications (audio / vidéo),
 * plans de lecture, bibliothèque (livres et prêts).
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

export function registerMediasRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/predications",
    module: "medias",
    table: "predications",
    columns: ["titre", "orateur", "date_predication", "culte_id", "serie", "url_audio", "url_video", "duree_minutes"],
    createSchema: z.object({
      titre: z.string().min(2).max(300),
      orateur: z.string().max(200).optional(),
      date_predication: z.string().regex(dateRe, "Date au format AAAA-MM-JJ."),
      culte_id: uuid.optional(),
      serie: z.string().max(200).optional(),
      url_audio: z.string().url().max(500).optional(),
      url_video: z.string().url().max(500).optional(),
      duree_minutes: z.number().int().positive().max(600).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "predication",
    searchColumn: "titre",
    orderBy: "date_predication DESC",
    validate: async (db2, churchId, data) => {
      if (data.culte_id && !(await existsInChurch(db2, "cultes", churchId, data.culte_id as string))) {
        return "Culte introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/plans-lecture",
    module: "medias",
    table: "plans_lecture",
    columns: ["nom", "description", "duree_jours", "actif"],
    createSchema: z.object({
      nom: z.string().min(2).max(200),
      description: z.string().max(1000).optional(),
      duree_jours: z.number().int().positive().max(1500).optional(),
      actif: z.boolean().default(true),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "plan_lecture",
    searchColumn: "nom",
  });

  registerCrud(app, db, {
    base: "/livres",
    module: "medias",
    table: "livres",
    columns: ["titre", "auteur", "categorie", "isbn", "exemplaires"],
    createSchema: z.object({
      titre: z.string().min(2).max(300),
      auteur: z.string().max(200).optional(),
      categorie: z.string().max(120).optional(),
      isbn: z.string().max(30).optional(),
      exemplaires: z.number().int().min(0).max(1000).default(1),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "livre",
    searchColumn: "titre",
  });

  registerCrud(app, db, {
    base: "/prets-livres",
    module: "medias",
    table: "prets_livres",
    columns: ["livre_id", "member_id", "date_pret", "date_retour_prevue", "date_retour", "statut"],
    createSchema: z.object({
      livre_id: uuid,
      member_id: uuid,
      date_pret: z.string().regex(dateRe, "Date au format AAAA-MM-JJ.").optional(),
      date_retour_prevue: z.string().regex(dateRe, "Date au format AAAA-MM-JJ.").optional(),
      date_retour: z.string().regex(dateRe, "Date au format AAAA-MM-JJ.").optional(),
      statut: z.enum(["en_cours", "rendu", "en_retard"]).default("en_cours"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "pret_livre",
    filters: { livre_id: "livre_id", member_id: "member_id", statut: "statut" },
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "livres", churchId, data.livre_id as string))) {
        return "Livre introuvable dans votre église.";
      }
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  // -- Retour d'un livre : statut 'rendu', date de retour = aujourd'hui. ----
  app.post(
    "/prets-livres/:id/rendre",
    { preHandler: [requireAuth(db), requireModule(db, "medias"), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `UPDATE prets_livres SET statut = 'rendu', date_retour = CURRENT_DATE
            WHERE id = $1 AND church_id = $2 AND statut <> 'rendu'
            RETURNING *`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(409).send({ error: "conflict", message: "Prêt introuvable, ou déjà rendu." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "pret_livre.rendu",
          details: { pret_id: rows[0].id },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
