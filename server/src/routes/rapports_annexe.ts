import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Tranche P5 — Rapports à mon église mère : une annexe choisit le type
 * de rapport (migration 023), l'application le génère depuis ses
 * vraies données et l'envoie par e-mail à son église mère, en pièce
 * jointe PDF. La mère lit les rapports reçus dans « Rapports reçus ».
 *
 * L'envoi par e-mail passe par mailer.ts (Lot B) : ce fichier ne
 * l'importe pas. En attendant, le rapport est enregistré avec le
 * statut `en_attente_envoi`, visible par la mère, et l'envoi est
 * marqué en attente du Lot B, jamais présenté comme envoyé. Le Lot B
 * branchera l'envoi (PDF + mailer) et passera le statut à `envoye`.
 *
 * Aucune adresse e-mail inventée : celle de la mère se lit dans
 * churches.email, nulle tant qu'elle n'est pas renseignée en base.
 */

const TYPES = ["bilan_annuel", "bilan_activite", "rapport_financier"] as const;

const envoiSchema = z.object({
  type: z.enum(TYPES),
  message: z.string().max(2000).optional().nullable(),
  membres: z.number().int().min(0),
  recettes_fcfa: z.number().int().min(0),
  depenses_fcfa: z.number().int().min(0),
  solde_fcfa: z.number().int(),
});

// Racine du réseau de mon église : premier ancêtre sans mère. Une
// église mère est sa propre racine.
const RACINE_SQL = `
  WITH RECURSIVE ancetres AS (
     SELECT id, parent_church_id, name, email FROM churches WHERE id = $1
     UNION ALL
     SELECT c.id, c.parent_church_id, c.name, c.email
       FROM churches c
       JOIN ancetres a ON c.id = a.parent_church_id
   )
   SELECT id, name, email FROM ancetres
    WHERE parent_church_id IS NULL LIMIT 1`;

export function registerRapportsAnnexeRoutes(app: FastifyInstance, db: Pool) {
  // -- Mon église mère (admin de l'église) : racine du réseau, nom et
  //    adresse e-mail, nulle tant qu'elle n'est pas renseignée.
  app.get(
    "/moi/eglise-mere",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(RACINE_SQL, [req.session.churchId]);
        if (rows.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église introuvable.",
          });
        }
        const mere = rows[0] as {
          id: string;
          name: string;
          email: string | null;
        };
        return reply.send({
          id: mere.id,
          nom: mere.name,
          email: mere.email,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Envoyer un rapport à mon église mère (admin d'une annexe) : le
  //    rapport est enregistré avec ses chiffres réels, statut
  //    `en_attente_envoi`. Une église mère n'envoie pas de rapport à
  //    elle-même. L'envoi par e-mail suit avec le Lot B.
  app.post(
    "/moi/rapports-annexe",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = envoiSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Rapport invalide.",
        });
      }
      const { type, message, membres, recettes_fcfa, depenses_fcfa, solde_fcfa } =
        parsed.data;
      try {
        const { rows: racines } = await db.query(RACINE_SQL, [
          req.session.churchId,
        ]);
        if (racines.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église introuvable.",
          });
        }
        const mere = racines[0] as { id: string };
        if (mere.id === req.session.churchId) {
          return reply.code(403).send({
            error: "mere_sans_mere",
            message:
              "Une église mère n’envoie pas de rapport à elle-même.",
          });
        }
        const { rows } = await db.query(
          `INSERT INTO rapports_annexe
             (eglise_id, eglise_mere_id, type, message, membres,
              recettes_fcfa, depenses_fcfa, solde_fcfa, statut)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'en_attente_envoi')
           RETURNING id, type, message, membres, recettes_fcfa,
             depenses_fcfa, solde_fcfa, statut, cree_le`,
          [
            req.session.churchId,
            mere.id,
            type,
            message ?? null,
            membres,
            recettes_fcfa,
            depenses_fcfa,
            solde_fcfa,
          ],
        );
        const ligne = rows[0] as Record<string, unknown>;
        return reply.send({
          ...ligne,
          envoi_email: "en_attente_lot_b",
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rapports reçus par mon église mère (admin de la mère) : ceux
  //    envoyés par ses églises annexes, le plus récent d'abord, avec
  //    le nom de l'église expéditrice. Une annexe ne lit pas les
  //    rapports des autres annexes.
  app.get(
    "/moi/rapports-annexe/recus",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows: racines } = await db.query(RACINE_SQL, [
          req.session.churchId,
        ]);
        if (racines.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église introuvable.",
          });
        }
        const mere = racines[0] as { id: string };
        if (mere.id !== req.session.churchId) {
          return reply.code(403).send({
            error: "annexe_sans_recus",
            message:
              "Une église annexe ne lit pas les rapports reçus.",
          });
        }
        const { rows } = await db.query(
          `SELECT r.id, r.type, r.message, r.membres, r.recettes_fcfa,
                  r.depenses_fcfa, r.solde_fcfa, r.statut, r.cree_le,
                  c.name AS eglise_nom
             FROM rapports_annexe r
             JOIN churches c ON c.id = r.eglise_id
            WHERE r.eglise_mere_id = $1
            ORDER BY r.cree_le DESC`,
          [req.session.churchId],
        );
        return reply.send(rows);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
