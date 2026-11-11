import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import {
  READ_ALL,
  WRITE_STD,
  existsInChurch,
  memberInChurch,
  registerCrud,
} from "../crud.js";

/**
 * Module 8 — Enfants et jeunesse : école du dimanche (classes par âge,
 * enseignants), autorisations parentales de sortie, activités jeunesse.
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

export function registerEnfantsRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/classes-enfants",
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
}
