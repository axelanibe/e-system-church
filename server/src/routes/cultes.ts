import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import {
  READ_ALL,
  WRITE_ADMIN,
  WRITE_STD,
  existsInChurch,
  registerCrud,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Module 2 — Cultes et programmes : types de culte, cultes, ordre de culte,
 * événements spéciaux (mariage, baptême d'eau, dédicace, funérailles…).
 */

const uuid = z.string().uuid();

export function registerCultesRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/culte-types",
    table: "culte_types",
    columns: ["nom", "jour_semaine", "heure_debut", "duree_minutes", "lieu", "actif"],
    createSchema: z.object({
      nom: z.string().min(2).max(120),
      jour_semaine: z.number().int().min(0).max(6).optional(),
      heure_debut: z.string().max(10).optional(),
      duree_minutes: z.number().int().positive().max(600).optional(),
      lieu: z.string().max(200).optional(),
      actif: z.boolean().default(true),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "culte_type",
    searchColumn: "nom",
  });

  registerCrud(app, db, {
    base: "/cultes",
    table: "cultes",
    columns: ["culte_type_id", "titre", "date_heure", "lieu", "orateur", "theme"],
    createSchema: z.object({
      culte_type_id: uuid.optional(),
      titre: z.string().min(2).max(200),
      date_heure: z.string().min(10).max(40),
      lieu: z.string().max(200).optional(),
      orateur: z.string().max(200).optional(),
      theme: z.string().max(300).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "culte",
    filters: { culte_type_id: "culte_type_id" },
    searchColumn: "titre",
    orderBy: "date_heure ASC",
    validate: async (db2, churchId, data) => {
      if (data.culte_type_id && !(await existsInChurch(db2, "culte_types", churchId, data.culte_type_id as string))) {
        return "Type de culte introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/ordre-culte",
    table: "ordre_culte_items",
    columns: ["culte_id", "ordre", "titre", "description", "intervenant", "duree_minutes"],
    createSchema: z.object({
      culte_id: uuid,
      ordre: z.number().int().min(0).default(0),
      titre: z.string().min(2).max(200),
      description: z.string().max(500).optional(),
      intervenant: z.string().max(200).optional(),
      duree_minutes: z.number().int().positive().max(600).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "ordre_culte",
    filters: { culte_id: "culte_id" },
    orderBy: "ordre ASC, created_at ASC",
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "cultes", churchId, data.culte_id as string))) {
        return "Culte introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/evenements-speciaux",
    table: "evenements_speciaux",
    columns: ["type", "titre", "description", "date_debut", "date_fin", "lieu", "responsable"],
    createSchema: z.object({
      type: z.enum(["mariage", "bapteme_eau", "dedicace_enfant", "funerailles", "conference", "campagne", "jeune", "autre"]),
      titre: z.string().min(2).max(200),
      description: z.string().max(1000).optional(),
      date_debut: z.string().min(10).max(40),
      date_fin: z.string().min(10).max(40).optional(),
      lieu: z.string().max(200).optional(),
      responsable: z.string().max(200).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "evenement_special",
    filters: { type: "type" },
    searchColumn: "titre",
    orderBy: "date_debut ASC",
  });

  // -- Activités à venir (V1, migration 039) : titre, description,
  //    date et heure, lieu, responsable (nom libre), statut brouillon
  //    ou publié. Écriture réservée à l'admin de l'église ; les
  //    brouillons sont invisibles aux membres (readScope), la lecture
  //    fidèle passe par GET /moi/activites (publiées à venir seulement).
  registerCrud(app, db, {
    base: "/activites",
    table: "activites",
    columns: ["titre", "description", "date_heure", "lieu", "responsable", "statut"],
    createSchema: z.object({
      titre: z.string().min(2).max(200),
      description: z.string().max(1000).optional(),
      date_heure: z.string().min(10).max(40),
      lieu: z.string().max(200).optional(),
      responsable: z.string().max(200).optional(),
      statut: z.enum(["brouillon", "publié"]).default("brouillon"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_ADMIN,
    audit: "activite",
    filters: { statut: "statut" },
    searchColumn: "titre",
    orderBy: "date_heure ASC",
    readScope: async (_db, session) => {
      if (session.role === "membre") {
        return { condition: "statut = 'publié'", values: [] };
      }
      return null;
    },
  });

  // -- Confirmations « Je serai présent » (lot 3b, migration 040) :
  //    qui a confirmé, pour un culte ou une activité, avec le compteur.
  //    Lecture admin + responsable de culte seulement : la liste nomme
  //    des membres. Ne touche pas au pointage (`presences`) : une
  //    confirmation n'est pas une présence pointée.
  app.get(
    "/cultes/:id/rsvp",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      try {
        const id = (req.params as { id: string }).id;
        const { rows: cibles } = await db.query(
          `SELECT id, titre, date_heure FROM cultes
            WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (cibles.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Culte introuvable dans votre église.",
          });
        }
        const { rows } = await db.query(
          `SELECT r.member_id, m.full_name AS membre_nom,
                  m.matricule AS membre_matricule, r.created_at
             FROM culte_rsvp r
             JOIN members m ON m.id = r.member_id
            WHERE r.culte_id = $1 AND r.church_id = $2
            ORDER BY r.created_at ASC`,
          [id, req.session.churchId],
        );
        return reply.send({
          culte: cibles[0],
          total: rows.length,
          confirmes: rows,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/activites/:id/rsvp",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      try {
        const id = (req.params as { id: string }).id;
        const { rows: cibles } = await db.query(
          `SELECT id, titre, date_heure FROM activites
            WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (cibles.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Activité introuvable dans votre église.",
          });
        }
        const { rows } = await db.query(
          `SELECT r.member_id, m.full_name AS membre_nom,
                  m.matricule AS membre_matricule, r.created_at
             FROM activite_rsvp r
             JOIN members m ON m.id = r.member_id
            WHERE r.activite_id = $1 AND r.church_id = $2
            ORDER BY r.created_at ASC`,
          [id, req.session.churchId],
        );
        return reply.send({
          activite: cibles[0],
          total: rows.length,
          confirmes: rows,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
