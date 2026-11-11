import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import {
  READ_ALL,
  WRITE_STD,
  memberInChurch,
  registerCrud,
} from "../crud.js";

/**
 * Module 5 — Communication : demandes de prière (confidentielles : lues
 * par l'admin et le responsable de culte seulement — le pasteur, en
 * pratique l'admin de l'église) et messages internes.
 */

const uuid = z.string().uuid();

export function registerPrieresRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/demandes-priere",
    table: "demandes_priere",
    columns: ["member_id", "demandeur_nom", "sujet", "details", "confidentiel", "statut"],
    createSchema: z.object({
      member_id: uuid.optional(),
      demandeur_nom: z.string().min(2).max(200).optional(),
      sujet: z.string().min(2).max(300),
      details: z.string().max(2000).optional(),
      confidentiel: z.boolean().default(false),
      statut: z.enum(["nouvelle", "en_cours", "terminee"]).default("nouvelle"),
    }),
    // Tout membre de l'église peut déposer une demande ; seuls l'admin et
    // le responsable de culte peuvent les lire (confidentialité).
    readRoles: ["admin_eglise", "responsable_culte"],
    writeRoles: READ_ALL,
    audit: "demande_priere",
    filters: { statut: "statut", confidentiel: "confidentiel" },
  });

  registerCrud(app, db, {
    base: "/messages-internes",
    table: "messages_internes",
    columns: ["expediteur_id", "destinataire_id", "sujet", "corps", "lu"],
    createSchema: z.object({
      expediteur_id: uuid,
      destinataire_id: uuid.optional(),
      sujet: z.string().min(2).max(300),
      corps: z.string().min(1).max(5000),
      lu: z.boolean().default(false),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "message_interne",
    filters: { destinataire_id: "destinataire_id", lu: "lu" },
    validate: async (db2, churchId, data, userId) => {
      // L'expéditeur doit être l'utilisateur connecté.
      if ((data.expediteur_id as string) !== userId) {
        return "L'expéditeur doit être l'utilisateur connecté.";
      }
      if (data.destinataire_id) {
        const { rowCount } = await db2.query(
          `SELECT 1 FROM church_users WHERE user_id = $1 AND church_id = $2`,
          [data.destinataire_id, churchId],
        );
        if ((rowCount ?? 0) === 0) return "Destinataire hors de votre église.";
      }
      return null;
    },
  });
}
