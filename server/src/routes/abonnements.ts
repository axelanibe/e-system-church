import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Tranche P3 — Mon abonnement : abonnement annuel de l'église mère
 * (migration 021), 200 000 FCFA par an, couvrant l'église mère et
 * toutes ses annexes. Durées 1, 3 et 10 ans, avec remise dégressive.
 * Essai gratuit 30 jours, rappels avant l'expiration, puis 30 jours
 * de grâce avant la lecture seule.
 *
 * Aucun moyen de paiement ici : il n'est pas décidé. Les codes promo
 * sont réservés au lancement, avec une date de fin ; la validation
 * seule est exposée, aucune interface admin de création des codes
 * pour l'instant (point ouvert).
 *
 * Une annexe n'a pas son propre abonnement : elle est couverte par
 * celui de son église mère (premier ancêtre).
 */

// Tarifs validés par Axel le 12 novembre 2026, remises déjà incluses.
const TARIFS: Record<number, number> = { 1: 200000, 3: 540000, 10: 1600000 };
const ESSAI_JOURS = 30;
const GRACE_JOURS = 30;

const codePromoSchema = z.object({
  code: z.string().min(1).max(50),
  duree_annees: z.union([z.literal(1), z.literal(3), z.literal(10)]),
});

export function registerAbonnementsRoutes(app: FastifyInstance, db: Pool) {
  // -- Mon abonnement (admin de l'église) : l'abonnement de mon église
  //    mère, ou la couverture par la mère si je suis une annexe. Sans
  //    ligne en base, l'application est vierge : statut Actif, plan
  //    annuel, expiration à compléter, comme dans la projection.
  app.get(
    "/moi/abonnement",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows: racines } = await db.query(
          `WITH RECURSIVE ancetres AS (
             SELECT id, parent_church_id, name FROM churches WHERE id = $1
             UNION ALL
             SELECT c.id, c.parent_church_id, c.name
               FROM churches c
               JOIN ancetres a ON c.id = a.parent_church_id
           )
           SELECT id, name FROM ancetres
            WHERE parent_church_id IS NULL LIMIT 1`,
          [req.session.churchId],
        );
        if (racines.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Église introuvable.",
          });
        }
        const mere = racines[0] as { id: string; name: string };
        const estAnnexe = mere.id !== req.session.churchId;
        if (estAnnexe) {
          return reply.send({
            est_annexe: true,
            eglise_mere_nom: mere.name,
            abonnement: null,
          });
        }
        const { rows } = await db.query(
          `SELECT plan, duree_annees, montant_fcfa, statut,
                  date_debut, date_expiration,
                  (statut = 'expire' AND date_expiration IS NOT NULL
                     AND date_expiration + ($1 || ' days')::interval
                         < CURRENT_DATE) AS lecture_seule
             FROM abonnements WHERE church_id = $2`,
          [String(GRACE_JOURS), mere.id],
        );
        const ligne = rows[0] as
          | {
              plan: string;
              duree_annees: number;
              montant_fcfa: number;
              statut: string;
              date_debut: string | null;
              date_expiration: string | null;
              lecture_seule: boolean;
            }
          | undefined;
        return reply.send({
          est_annexe: false,
          eglise_mere_nom: mere.name,
          abonnement: ligne
            ? {
                plan: ligne.plan,
                duree_annees: ligne.duree_annees,
                montant_fcfa: ligne.montant_fcfa,
                statut: ligne.statut,
                date_debut: ligne.date_debut,
                date_expiration: ligne.date_expiration,
                essai_jours: ESSAI_JOURS,
                lecture_seule: ligne.lecture_seule,
              }
            : {
                plan: "annuel",
                duree_annees: 1,
                montant_fcfa: TARIFS[1],
                statut: "actif",
                date_debut: null,
                date_expiration: null,
                essai_jours: ESSAI_JOURS,
                lecture_seule: false,
              },
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Validation d'un code promo (admin de l'église) : le code seul
  //    est vérifié, avec la durée choisie, sans rien créer ni payer.
  //    La réduction dépend du code. Codes inconnus, inactifs ou hors
  //    dates : refusés.
  app.post(
    "/moi/abonnement/code-promo",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = codePromoSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Code promo ou durée invalide.",
        });
      }
      const { code, duree_annees } = parsed.data;
      try {
        const { rows } = await db.query(
          `SELECT code, type_reduction, valeur FROM codes_promo
            WHERE upper(code) = $1 AND actif = true
              AND (date_debut IS NULL OR date_debut <= CURRENT_DATE)
              AND (date_fin IS NULL OR date_fin >= CURRENT_DATE)`,
          [code.trim().toUpperCase()],
        );
        if (rows.length === 0) {
          return reply.code(404).send({
            error: "code_invalide",
            message: "Code promo invalide.",
          });
        }
        const promo = rows[0] as {
          code: string;
          type_reduction: string;
          valeur: number;
        };
        const totalAvant = TARIFS[duree_annees];
        const totalApres =
          promo.type_reduction === "pourcentage"
            ? Math.round(totalAvant * (1 - promo.valeur / 100))
            : Math.max(0, totalAvant - promo.valeur);
        return reply.send({
          valide: true,
          code: promo.code,
          type_reduction: promo.type_reduction,
          valeur: promo.valeur,
          total_avant: totalAvant,
          total_apres: totalApres,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
