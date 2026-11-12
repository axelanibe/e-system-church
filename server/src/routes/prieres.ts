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
 *
 * Confidentialité (Lot B, tranche 1) : tout membre peut déposer une
 * demande, mais seuls l'admin et le responsable de culte peuvent la
 * modifier ou la supprimer. Le drapeau `confidentiel` est effectif côté
 * serveur : une demande confidentielle n'est visible que par l'admin, le
 * responsable de culte et son auteur (fiche membre liée au compte) ;
 * une demande non confidentielle est visible par tous les rôles de
 * l'église. Chaque lecture est journalisée (US17 : consultation tracée).
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
    // le responsable de culte peuvent les lire en entier (confidentialité)
    // et les modifier ou les supprimer. Le drapeau `confidentiel` est
    // effectif : une demande confidentielle est invisible aux autres
    // rôles, sauf à son auteur (fiche membre liée au compte).
    readRoles: READ_ALL,
    writeRoles: READ_ALL,
    createRoles: READ_ALL,
    updateDeleteRoles: ["admin_eglise", "responsable_culte"],
    audit: "demande_priere",
    logReads: true,
    readScope: async (db2, session, paramOffset) => {
      if (session.role === "admin_eglise" || session.role === "responsable_culte") {
        return null;
      }
      const { rows } = await db2.query<{ member_id: string | null }>(
        `SELECT member_id FROM users WHERE id = $1`,
        [session.userId],
      );
      const memberId = rows[0]?.member_id ?? null;
      if (memberId) {
        return {
          condition: `confidentiel = false OR member_id = $${paramOffset + 1}`,
          values: [memberId],
        };
      }
      return { condition: "confidentiel = false", values: [] };
    },
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
