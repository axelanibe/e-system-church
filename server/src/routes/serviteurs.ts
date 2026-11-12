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
 * Module 7 — Départements et serviteurs : affectation d'un membre à un
 * département (chorale, musique, accueil, média, enfants…), planning des
 * serviteurs pour chaque culte ou événement.
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

export function registerServiteursRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/serviteurs",
    table: "serviteurs",
    columns: ["member_id", "departement_id", "role", "disponibilite", "actif"],
    createSchema: z.object({
      member_id: uuid,
      departement_id: uuid,
      role: z.string().min(2).max(80).default("serviteur"),
      disponibilite: z.string().max(300).optional(),
      actif: z.boolean().default(true),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "serviteur",
    filters: { member_id: "member_id", departement_id: "departement_id" },
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      if (!(await existsInChurch(db2, "departements", churchId, data.departement_id as string))) {
        return "Département introuvable dans votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/planning-serviteurs",
    table: "planning_serviteurs",
    columns: ["serviteur_id", "culte_id", "event_id", "date_service", "role_service", "statut"],
    createSchema: z.object({
      serviteur_id: uuid,
      culte_id: uuid.optional(),
      event_id: uuid.optional(),
      date_service: z.string().regex(dateRe, "Date au format AAAA-MM-JJ."),
      role_service: z.string().max(120).optional(),
      statut: z.enum(["prevu", "confirme", "absent"]).default("prevu"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "planning_serviteur",
    filters: { serviteur_id: "serviteur_id", culte_id: "culte_id", statut: "statut" },
    orderBy: "date_service ASC",
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "serviteurs", churchId, data.serviteur_id as string))) {
        return "Serviteur introuvable dans votre église.";
      }
      if (data.culte_id && !(await existsInChurch(db2, "cultes", churchId, data.culte_id as string))) {
        return "Culte introuvable dans votre église.";
      }
      if (data.event_id && !(await existsInChurch(db2, "events", churchId, data.event_id as string))) {
        return "Événement introuvable dans votre église.";
      }
      return null;
    },
  });
}
