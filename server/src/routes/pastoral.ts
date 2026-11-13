import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import {
  WRITE_STD,
  memberInChurch,
  registerCrud,
} from "../crud.js";

/**
 * Module 6 — Suivi pastoral : parcours des nouveaux convertis (accueil →
 * formation → baptême → intégration en cellule), visites pastorales,
 * accompagnements (couples, familles, malades, difficultés).
 *
 * Confidentialité (Lot B, tranche 1) : lecture réservée à l'admin de
 * l'église et au responsable de culte — le trésorier et le simple membre
 * sont exclus, comptes rendus inclus. Chaque lecture est journalisée
 * dans audit_logs (US17 : consultation tracée).
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

export function registerPastoralRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/parcours-nouveaux",
    table: "parcours_nouveaux",
    columns: ["member_id", "etape", "date_etape", "note"],
    createSchema: z.object({
      member_id: uuid,
      etape: z.enum(["accueil", "formation", "bapteme", "integration_cellule", "integre"]).default("accueil"),
      date_etape: z.string().regex(dateRe, "Date au format AAAA-MM-JJ.").optional(),
      note: z.string().max(1000).optional(),
    }),
    readRoles: ["admin_eglise", "responsable_culte"],
    writeRoles: WRITE_STD,
    audit: "parcours_nouveau",
    logReads: true,
    filters: { member_id: "member_id", etape: "etape" },
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/visites-pastorales",
    table: "visites_pastorales",
    columns: ["member_id", "visiteur_id", "date_visite", "motif", "compte_rendu", "statut"],
    createSchema: z.object({
      member_id: uuid,
      visiteur_id: uuid.optional(),
      date_visite: z.string().min(10).max(40),
      motif: z.string().max(500).optional(),
      compte_rendu: z.string().max(5000).optional(),
      statut: z.enum(["planifiee", "realisee", "annulee"]).default("planifiee"),
    }),
    readRoles: ["admin_eglise", "responsable_culte"],
    writeRoles: WRITE_STD,
    audit: "visite_pastorale",
    logReads: true,
    filters: { member_id: "member_id", statut: "statut" },
    orderBy: "date_visite ASC",
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/accompagnements",
    table: "accompagnements",
    columns: ["member_id", "type", "accompagnateur_id", "description", "statut"],
    createSchema: z.object({
      member_id: uuid,
      type: z.enum(["couple", "famille", "malade", "difficulte", "autre"]),
      accompagnateur_id: uuid.optional(),
      description: z.string().max(2000).optional(),
      statut: z.enum(["en_cours", "termine"]).default("en_cours"),
    }),
    readRoles: ["admin_eglise", "responsable_culte"],
    writeRoles: WRITE_STD,
    audit: "accompagnement",
    logReads: true,
    filters: { member_id: "member_id", type: "type", statut: "statut" },
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });
}
