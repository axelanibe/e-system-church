import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { ficheMembre } from "../messagerie_commun.js";
import {
  NB_CRENEAUX,
  chaineComplete,
  compterCouverts,
  heureValide,
  jourPasse,
  jourValide,
  normaliserHeure,
  normaliserJour,
  validerEngagement,
} from "../chaine_priere.js";

/**
 * Lot 3d — Chaîne de prière : 24 créneaux d'une heure par jour, un
 * membre par créneau, un créneau par membre et par jour. Adapté de
 * Connexion Prophétique (lib/chaine_priere.dart et
 * server-production/src/chaine_priere.js), avec l'isolation par
 * `church_id` de la messagerie : une église ne voit que sa propre
 * chaîne, et un membre ne prend ou ne libère que ses propres créneaux.
 *
 * Le jour est en AAAA-MM-JJ ; sans jour, le jour courant de l'église
 * (fuseau horaire de l'église, calculé côté base). Les jours passés
 * sont en lecture seule. Le prénom affiché est le premier mot du nom
 * complet du membre en base, jamais inventé ; le nom complet et le
 * matricule ne sortent jamais.
 *
 * Rôles : tous les rôles de l'église (comme les demandes de prière).
 * Prendre ou libérer exige une fiche membre liée au compte, comme la
 * messagerie ; sans fiche, 403 explicite.
 */

const ROLES_CHAINE = ["admin_eglise", "tresorier", "responsable_culte", "membre"];

/** Jour courant de l'église, en AAAA-MM-JJ, dans son fuseau horaire. */
async function aujourdHuiEglise(db: Pool, churchId: string): Promise<string> {
  const { rows } = await db.query<{ fuseau_horaire: string | null }>(
    `SELECT fuseau_horaire FROM churches WHERE id = $1`,
    [churchId],
  );
  const fuseau = rows[0]?.fuseau_horaire ?? "Africa/Abidjan";
  const { rows: jourRows } = await db.query<{ aujourd_hui: string }>(
    `SELECT (now() AT TIME ZONE $1)::date::text AS aujourd_hui`,
    [fuseau],
  );
  return jourRows[0].aujourd_hui;
}

/** Fiche membre de l'appelant dans l'église de la session, ou null. */
async function monMembre(
  db: Pool,
  userId: string,
  churchId: string,
): Promise<string | null> {
  const memberId = await ficheMembre(db, userId);
  if (!memberId) return null;
  const { rows } = await db.query<{ church_id: string }>(
    `SELECT church_id FROM members WHERE id = $1`,
    [memberId],
  );
  if (rows.length === 0 || rows[0].church_id !== churchId) return null;
  return memberId;
}

export function registerChainePriereRoutes(app: FastifyInstance, db: Pool) {
  const auth = requireAuth(db);

  // -- GET /chaine-priere?jour=AAAA-MM-JJ : les 24 créneaux du jour.
  app.get(
    "/chaine-priere",
    { preHandler: [auth, requireRole(...ROLES_CHAINE)] },
    async (req, reply) => {
      const query = req.query as { jour?: unknown };
      const aujourdHui = await aujourdHuiEglise(db, req.session.churchId);
      const jour =
        query.jour == null || query.jour === ""
          ? aujourdHui
          : normaliserJour(query.jour);
      if (jour == null) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Jour invalide : un jour AAAA-MM-JJ.",
        });
      }
      try {
        const { rows } = await db.query<{
          heure: number;
          member_id: string;
          nom_complet: string;
        }>(
          `SELECT cp.heure, cp.member_id, m.full_name AS nom_complet
             FROM creneaux_priere cp
             JOIN members m ON m.id = cp.member_id
            WHERE cp.church_id = $1 AND cp.jour = $2
            ORDER BY cp.heure`,
          [req.session.churchId, jour],
        );
        const creneaux = chaineComplete(rows);
        const memberId = await monMembre(
          db,
          req.session.userId,
          req.session.churchId,
        );
        return reply.send({
          jour,
          aujourd_hui: aujourdHui,
          heures_couvertes: compterCouverts(creneaux),
          heures_totales: NB_CRENEAUX,
          mon_member_id: memberId,
          creneaux,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- POST /chaine-priere {heure, jour?} : prendre un créneau.
  app.post(
    "/chaine-priere",
    { preHandler: [auth, requireRole(...ROLES_CHAINE)] },
    async (req, reply) => {
      const corps = (req.body ?? {}) as { heure?: unknown; jour?: unknown };
      const refus = validerEngagement(corps);
      if (refus) {
        return reply.code(refus.statut).send({
          error: "invalid_input",
          message: refus.message,
        });
      }
      const heure = normaliserHeure(corps.heure)!;
      const aujourdHui = await aujourdHuiEglise(db, req.session.churchId);
      const jour =
        corps.jour == null || corps.jour === ""
          ? aujourdHui
          : normaliserJour(corps.jour)!;
      if (jourPasse(jour, aujourdHui)) {
        return reply.code(400).send({
          error: "invalid_input",
          message:
            "Ce jour est passé : la chaîne de prière est en lecture seule.",
        });
      }
      const memberId = await monMembre(
        db,
        req.session.userId,
        req.session.churchId,
      );
      if (!memberId) {
        return reply.code(403).send({
          error: "forbidden",
          message:
            "Votre compte n'est pas lié à une fiche membre : impossible de prendre un créneau de prière.",
        });
      }
      try {
        const { rows } = await db.query<{ id: string }>(
          `INSERT INTO creneaux_priere (church_id, member_id, jour, heure)
           VALUES ($1, $2, $3, $4)
           RETURNING id`,
          [req.session.churchId, memberId, jour, heure],
        );
        return reply.code(201).send({
          id: rows[0].id,
          jour,
          heure,
          member_id: memberId,
        });
      } catch (e) {
        const err = e as { code?: string; constraint?: string };
        if (err?.code === "23505") {
          if (err.constraint === "uq_creneaux_priere_creneau") {
            return reply.code(409).send({
              error: "duplicate",
              message: "Ce créneau est déjà pris par un autre membre.",
            });
          }
          if (err.constraint === "uq_creneaux_priere_membre_jour") {
            return reply.code(409).send({
              error: "duplicate",
              message: "Vous avez déjà pris un créneau ce jour-là.",
            });
          }
        }
        return dbError(reply, e);
      }
    },
  );

  // -- DELETE /chaine-priere/:heure?jour=AAAA-MM-JJ : libérer son créneau.
  app.delete(
    "/chaine-priere/:heure",
    { preHandler: [auth, requireRole(...ROLES_CHAINE)] },
    async (req, reply) => {
      const params = req.params as { heure?: unknown };
      const query = req.query as { jour?: unknown };
      const heure = normaliserHeure(params.heure);
      if (heure == null || !heureValide(heure)) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Créneau invalide : une heure de 0 à 23.",
        });
      }
      const aujourdHui = await aujourdHuiEglise(db, req.session.churchId);
      const jour =
        query.jour == null || query.jour === ""
          ? aujourdHui
          : normaliserJour(query.jour);
      if (jour == null || !jourValide(jour)) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Jour invalide : un jour AAAA-MM-JJ.",
        });
      }
      if (jourPasse(jour, aujourdHui)) {
        return reply.code(400).send({
          error: "invalid_input",
          message:
            "Ce jour est passé : la chaîne de prière est en lecture seule.",
        });
      }
      const memberId = await monMembre(
        db,
        req.session.userId,
        req.session.churchId,
      );
      if (!memberId) {
        return reply.code(403).send({
          error: "forbidden",
          message:
            "Votre compte n'est pas lié à une fiche membre : impossible de libérer un créneau de prière.",
        });
      }
      try {
        const { rowCount } = await db.query(
          `DELETE FROM creneaux_priere
            WHERE church_id = $1 AND member_id = $2 AND jour = $3 AND heure = $4`,
          [req.session.churchId, memberId, jour, heure],
        );
        if ((rowCount ?? 0) === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Créneau introuvable, ou il ne vous appartient pas.",
          });
        }
        return reply.send({ ok: true, jour, heure });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
