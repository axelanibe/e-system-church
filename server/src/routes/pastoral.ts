import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import {
  WRITE_STD,
  existsInChurch,
  invalidInput,
  memberInChurch,
  registerCrud,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Module 6 — Suivi pastoral : parcours des nouveaux convertis (accueil →
 * formation → baptême → intégration en cellule), visites pastorales,
 * accompagnements (couples, familles, malades, difficultés).
 *
 * Confidentialité (Lot B, tranche 1) : lecture réservée à l'admin de
 * l'église et au responsable de culte — le trésorier et le simple membre
 * sont exclus, comptes rendus inclus. Chaque lecture est journalisée
 * dans audit_logs (US17 : consultation tracée).
 *
 * Tranche T6 (Lot B) : radar des absences consécutives (vue calculée
 * v_radar_absences, GET /radar-absences), gestion des rendez-vous côté
 * admin (GET /rendez-vous, PATCH /rendez-vous/:id/statut — machine à
 * états, pas de PATCH générique sur le statut), visites typées
 * (domicile / hôpital, avec lieu), rencontres d'accompagnement datées
 * (table rencontres_accompagnement), suivi des personnes en difficulté
 * (priorité + tableau des cas ouverts GET /accompagnements/cas-ouverts).
 * Aucun envoi SMS ni push : le rappel se fait en application seulement.
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

/** Rôles autorisés à lire les données pastorales (tranche 1). */
const LECTURE_PASTORALE = ["admin_eglise", "responsable_culte"] as const;

/** Machine à états des rendez-vous (migration 022). */
const RDV_TRANSITIONS: Record<string, { from: string }> = {
  confirme: { from: "en_attente" },
  refuse: { from: "en_attente" },
  annule: { from: "confirme" },
};

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
    columns: ["member_id", "visiteur_id", "date_visite", "motif", "compte_rendu", "type", "lieu", "statut"],
    createSchema: z.object({
      member_id: uuid,
      visiteur_id: uuid.optional(),
      date_visite: z.string().min(10).max(40),
      motif: z.string().max(500).optional(),
      compte_rendu: z.string().max(5000).optional(),
      // Tranche T6 : visite typée (domicile / hôpital) avec lieu.
      type: z.enum(["domicile", "hopital"]).optional(),
      lieu: z.string().max(200).optional(),
      statut: z.enum(["planifiee", "realisee", "annulee"]).default("planifiee"),
    }),
    readRoles: ["admin_eglise", "responsable_culte"],
    writeRoles: WRITE_STD,
    audit: "visite_pastorale",
    logReads: true,
    filters: { member_id: "member_id", statut: "statut", type: "type" },
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
    columns: ["member_id", "type", "accompagnateur_id", "description", "priorite", "statut"],
    createSchema: z.object({
      member_id: uuid,
      type: z.enum(["couple", "famille", "malade", "difficulte", "autre"]),
      accompagnateur_id: uuid.optional(),
      description: z.string().max(2000).optional(),
      // Tranche T6 : priorité du cas (suivi des personnes en difficulté).
      priorite: z.enum(["basse", "normale", "haute", "urgente"]).default("normale"),
      statut: z.enum(["en_cours", "termine"]).default("en_cours"),
    }),
    readRoles: ["admin_eglise", "responsable_culte"],
    writeRoles: WRITE_STD,
    audit: "accompagnement",
    logReads: true,
    filters: { member_id: "member_id", type: "type", statut: "statut", priorite: "priorite" },
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  // -- Rencontres d'accompagnement datées (tranche T6) : un accompagnement
  //    peut avoir plusieurs rencontres, chacune datée, avec une note. ------
  registerCrud(app, db, {
    base: "/rencontres-accompagnement",
    table: "rencontres_accompagnement",
    columns: ["accompagnement_id", "date_rencontre", "note"],
    createSchema: z.object({
      accompagnement_id: uuid,
      date_rencontre: z.string().regex(dateRe, "Date au format AAAA-MM-JJ."),
      note: z.string().max(1000).optional(),
    }),
    readRoles: ["admin_eglise", "responsable_culte"],
    writeRoles: WRITE_STD,
    audit: "rencontre_accompagnement",
    logReads: true,
    filters: { accompagnement_id: "accompagnement_id" },
    orderBy: "date_rencontre DESC",
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "accompagnements", churchId, data.accompagnement_id as string))) {
        return "Accompagnement introuvable dans votre église.";
      }
      return null;
    },
  });

  // -- Radar des absences consécutives (tranche T6) : vue calculée
  //    v_radar_absences (migration 024). Seuil par défaut : 3 absences
  //    consécutives. L'alerte est un message bienveillant, la visite est
  //    suggérée (jamais créée automatiquement) ; l'admin la crée via
  //    POST /visites-pastorales (type domicile). Lecture journalisée. -----
  app.get(
    "/radar-absences",
    { preHandler: [requireAuth(db), requireRole(...LECTURE_PASTORALE)] },
    async (req, reply) => {
      const parsed = z
        .object({ seuil: z.coerce.number().int().min(1).max(10).default(3) })
        .safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const seuil = parsed.data.seuil;
      try {
        const { rows } = await db.query(
          `SELECT member_id, membre_nom, membre_matricule, membre_telephone,
                  membre_email, membre_statut, absences_consecutives, derniere_presence
             FROM v_radar_absences
            WHERE church_id = $1 AND absences_consecutives >= $2
            ORDER BY absences_consecutives DESC, membre_nom ASC`,
          [req.session.churchId, seuil],
        );
        const items = rows.map((r) => {
          const n = r.absences_consecutives as number;
          const nom = r.membre_nom as string;
          const derniere = r.derniere_presence
            ? new Date(r.derniere_presence as string).toISOString().slice(0, 10)
            : null;
          return {
            ...r,
            alerte: derniere
              ? `Nous n'avons pas vu ${nom} depuis ${n} cultes consécutifs (dernière présence le ${derniere}) — une visite serait la bienvenue.`
              : `Nous n'avons pas encore vu ${nom} à un culte (${n} cultes depuis son arrivée) — une visite serait la bienvenue.`,
            visite_suggeree: {
              type: "domicile",
              motif: `Absence prolongée (${n} cultes consécutifs)`,
            },
          };
        });
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "radar_absences.lu",
          details: { total: items.length, seuil },
        });
        return reply.send({ seuil, total: items.length, items });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Rendez-vous, côté admin (tranche T6) : liste des demandes de
  //    l'église, lecture d'une demande, et machine à états
  //    (confirmer / refuser / annuler) avec créneau fixé à la
  //    confirmation. Pas de PATCH générique sur le statut (tranche 1) :
  //    seule cette route change le statut. Rappel en application
  //    seulement : aucun envoi SMS ni push. -------------------------------
  app.get(
    "/rendez-vous",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      const parsed = z
        .object({
          limit: z.coerce.number().int().min(1).max(100).default(50),
          offset: z.coerce.number().int().min(0).default(0),
          statut: z.enum(["en_attente", "confirme", "refuse", "annule"]).optional(),
          member_id: uuid.optional(),
        })
        .safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { limit, offset, statut, member_id } = parsed.data;
      try {
        const conditions = [`r.church_id = $1`];
        const values: unknown[] = [req.session.churchId];
        if (statut) {
          values.push(statut);
          conditions.push(`r.statut = $${values.length}`);
        }
        if (member_id) {
          values.push(member_id);
          conditions.push(`r.member_id = $${values.length}`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM rendez_vous r ${where}`,
          values,
        );
        const { rows } = await db.query(
          `SELECT r.*, m.full_name AS membre_nom, m.matricule AS membre_matricule
             FROM rendez_vous r
             JOIN members m ON m.id = r.member_id
            ${where}
            ORDER BY r.date_souhaitee ASC, r.created_at DESC
            LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
          [...values, limit, offset],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "rendez_vous.lu",
          details: { total: Number(total.rows[0]?.n ?? 0), limit, offset },
        });
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/rendez-vous/:id",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT r.*, m.full_name AS membre_nom, m.matricule AS membre_matricule
             FROM rendez_vous r
             JOIN members m ON m.id = r.member_id
            WHERE r.id = $1 AND r.church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Rendez-vous introuvable." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "rendez_vous.lu",
          details: { id: rows[0].id },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/rendez-vous/:id/statut",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      const parsed = z
        .object({
          statut: z.enum(["confirme", "refuse", "annule"]),
          creneau: z.string().min(1).max(50).optional(),
        })
        .safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const cible = parsed.data.statut;
      const regle = RDV_TRANSITIONS[cible];
      if (cible === "confirme" && !parsed.data.creneau?.trim()) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Indiquez le créneau confirmé.",
        });
      }
      try {
        const { rows } = await db.query(
          `UPDATE rendez_vous
              SET statut = $3, creneau = COALESCE($4, creneau)
            WHERE id = $1 AND church_id = $2 AND statut = $5
            RETURNING id, member_id, date_souhaitee, creneau, motif, statut, created_at`,
          [
            (req.params as { id: string }).id,
            req.session.churchId,
            cible,
            parsed.data.creneau?.trim() ?? null,
            regle.from,
          ],
        );
        if (rows.length === 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Rendez-vous introuvable, ou transition non autorisée depuis son statut actuel.",
          });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: `rendez_vous.${cible}`,
          details: {
            rendez_vous_id: rows[0].id,
            member_id: rows[0].member_id,
            creneau: rows[0].creneau,
          },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Tableau des cas ouverts (tranche T6) : accompagnements en cours,
  //    par défaut les personnes en difficulté, triés par priorité
  //    (urgente d'abord) puis par ancienneté. Le nom du membre est joint
  //    pour que le tableau soit lisible sans aller-retour. Lecture
  //    journalisée. ---------------------------------------------------------
  app.get(
    "/accompagnements/cas-ouverts",
    { preHandler: [requireAuth(db), requireRole(...LECTURE_PASTORALE)] },
    async (req, reply) => {
      const parsed = z
        .object({
          type: z.enum(["couple", "famille", "malade", "difficulte", "autre", "tous"]).default("difficulte"),
          priorite: z.enum(["basse", "normale", "haute", "urgente"]).optional(),
          limit: z.coerce.number().int().min(1).max(100).default(50),
          offset: z.coerce.number().int().min(0).default(0),
        })
        .safeParse(req.query);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const { type, priorite, limit, offset } = parsed.data;
      try {
        const conditions = [`a.church_id = $1`, `a.statut = 'en_cours'`];
        const values: unknown[] = [req.session.churchId];
        if (type !== "tous") {
          values.push(type);
          conditions.push(`a.type = $${values.length}`);
        }
        if (priorite) {
          values.push(priorite);
          conditions.push(`a.priorite = $${values.length}`);
        }
        const where = `WHERE ${conditions.join(" AND ")}`;
        const total = await db.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM accompagnements a ${where}`,
          values,
        );
        const { rows } = await db.query(
          `SELECT a.*, m.full_name AS membre_nom, m.matricule AS membre_matricule
             FROM accompagnements a
             JOIN members m ON m.id = a.member_id
            ${where}
            ORDER BY CASE a.priorite
                       WHEN 'urgente' THEN 0
                       WHEN 'haute' THEN 1
                       WHEN 'normale' THEN 2
                       ELSE 3
                     END,
                     a.created_at ASC
            LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
          [...values, limit, offset],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "accompagnement.cas_ouverts_lu",
          details: { total: Number(total.rows[0]?.n ?? 0), type, limit, offset },
        });
        return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
