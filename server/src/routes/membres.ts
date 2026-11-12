import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog, generateMatricule, normalizeMatricule, normalizeSexe } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Membres de l'église de la session (isolation stricte par church_id).
 * GET  /membres     — liste + recherche (nom / matricule) + filtres.
 * GET  /membres/:id — un membre (404 s'il appartient à une autre église).
 * POST /membres     — création (admin_eglise, responsable_culte).
 *                      Le trésorier ne peut PAS créer de membre ; le matricule
 *                      est généré automatiquement (M-LA-171268-01…) sauf s'il est fourni.
 * PATCH /membres/:id — modification (le matricule ne change pas).
 * DELETE /membres/:id — suppression (contributions → membre NULL, présences /
 *                      statuts / baptêmes / liens en cascade).
 */

const createMembreSchema = z.object({
  full_name: z.string().min(2).max(200),
  phone: z.string().min(8).max(30).optional(),
  email: z.string().email().max(254).optional(),
  birth_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").optional(),
  /** Sexe (M ou F), facultatif : règle +50 au mois pour les femmes (matricule québécois). */
  sexe: z.string().max(20).optional(),
  department: z.string().min(2).max(120).optional(),
  fonction: z.string().min(2).max(120).optional(),
  poste: z.string().min(2).max(120).optional(),
  cell_group: z.string().min(2).max(120).optional(),
  /** Dates d'événements de vie (US7, migration 019) : NULL tant que non renseignées. */
  date_mariage: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").optional(),
  date_conversion: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").optional(),
  status: z.enum(["actif", "nouveau_converti", "inactif"]).default("actif"),
  matricule: z.string().min(1).max(30).optional(),
});

const listQuerySchema = z.object({
  q: z.string().max(200).optional(),
  department: z.string().max(120).optional(),
  // « ancien » n'est pas dans l'enum simple de members.status : c'est le
  // dernier statut riche de membre_statuts (tranche T4).
  status: z.enum(["actif", "nouveau_converti", "inactif", "ancien"]).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte", "membre"];
const WRITE_ROLES = ["admin_eglise", "responsable_culte"];

export function registerMembresRoutes(app: FastifyInstance, db: Pool) {
  app.get("/membres", { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] }, async (req, reply) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Paramètres de recherche invalides.",
        details: parsed.error.issues.map((i) => i.message),
      });
    }
    const { q, department, status, limit, offset } = parsed.data;
    try {
      const conditions = [`m.church_id = $1`];
      const values: unknown[] = [req.session.churchId];
      if (q) {
        values.push(`%${q}%`);
        conditions.push(`(m.full_name ILIKE $${values.length} OR m.matricule ILIKE $${values.length})`);
      }
      if (department) {
        values.push(department);
        conditions.push(`m.department = $${values.length}`);
      }
      if (status) {
        if (status === "ancien") {
          // Dernier statut riche « ancien » (membre_statuts), pas l'enum simple.
          conditions.push(`dernier.statut = 'ancien'`);
        } else {
          values.push(status);
          conditions.push(`m.status = $${values.length}`);
        }
      }
      const where = `WHERE ${conditions.join(" AND ")}`;
      // Dernier statut riche de chaque membre (pour afficher « Ancien »).
      const from = `FROM members m
        LEFT JOIN LATERAL (
          SELECT ms.statut FROM membre_statuts ms
           WHERE ms.member_id = m.id AND ms.church_id = $1
           ORDER BY ms.created_at DESC, ms.id DESC LIMIT 1
        ) dernier ON true`;
      const total = await db.query<{ n: string }>(
        `SELECT count(*)::text AS n FROM members m
           LEFT JOIN LATERAL (
             SELECT ms.statut FROM membre_statuts ms
              WHERE ms.member_id = m.id AND ms.church_id = $1
              ORDER BY ms.created_at DESC, ms.id DESC LIMIT 1
           ) dernier ON true ${where}`,
        values,
      );
      const { rows } = await db.query(
        `SELECT m.id, m.church_id, m.matricule, m.full_name, m.phone, m.email, m.birth_date, m.sexe,
                m.department, m.fonction, m.poste, m.cell_group, m.status, m.created_at,
                m.photo_url, m.date_mariage, m.date_conversion,
                dernier.statut AS statut_riche
           ${from} ${where}
          ORDER BY m.full_name ASC
          LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
        [...values, limit, offset],
      );
      return reply.send({ total: Number(total.rows[0]?.n ?? 0), membres: rows });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Anniversaires proches : membres dont l'anniversaire tombe dans les
  //    N jours à venir (30 par défaut, 90 au plus). Aucun message envoyé,
  //    la liste seulement (tranche T4, le fournisseur SMS n'est pas choisi).
  app.get(
    "/membres/anniversaires",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      const jours = Math.min(90, Math.max(1, Number((req.query as { jours?: string }).jours ?? 30) || 30));
      try {
        const { rows } = await db.query(
          `WITH anniv AS (
             SELECT id, full_name, matricule, birth_date,
               CASE
                 WHEN (birth_date + ((EXTRACT(YEAR FROM CURRENT_DATE)::int - EXTRACT(YEAR FROM birth_date)::int) || ' years')::interval)::date >= CURRENT_DATE
                 THEN (birth_date + ((EXTRACT(YEAR FROM CURRENT_DATE)::int - EXTRACT(YEAR FROM birth_date)::int) || ' years')::interval)::date
                 ELSE (birth_date + ((EXTRACT(YEAR FROM CURRENT_DATE)::int - EXTRACT(YEAR FROM birth_date)::int + 1) || ' years')::interval)::date
               END AS prochain
               FROM members
              WHERE church_id = $1 AND birth_date IS NOT NULL
           )
           SELECT id, full_name, matricule, birth_date, prochain,
                  (prochain - CURRENT_DATE)::int AS jours_restants,
                  (EXTRACT(YEAR FROM prochain)::int - EXTRACT(YEAR FROM birth_date)::int) AS age_atteint
             FROM anniv
            WHERE (prochain - CURRENT_DATE) <= $2
            ORDER BY jours_restants ASC, full_name ASC
            LIMIT 200`,
          [req.session.churchId, jours],
        );
        return reply.send({ jours, anniversaires: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/membres/:id",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        // Dernier statut riche, comme dans la liste : la fiche affiche
        // « Ancien » même après rechargement du membre seul.
        const { rows } = await db.query(
          `SELECT m.id, m.church_id, m.matricule, m.full_name, m.phone, m.email, m.birth_date, m.sexe,
                  m.department, m.fonction, m.poste, m.cell_group, m.status, m.created_at,
                  m.photo_url, m.date_mariage, m.date_conversion,
                  dernier.statut AS statut_riche
             FROM members m
             LEFT JOIN LATERAL (
               SELECT ms.statut FROM membre_statuts ms
                WHERE ms.member_id = m.id AND ms.church_id = $2
                ORDER BY ms.created_at DESC, ms.id DESC LIMIT 1
             ) dernier ON true
            WHERE m.id = $1 AND m.church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post("/membres", { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] }, async (req, reply) => {
    const parsed = createMembreSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Données du membre invalides.",
        details: parsed.error.issues.map((i) => i.message),
      });
    }
    const data = parsed.data;
    const sexeNorm = normalizeSexe(data.sexe);
    try {
      // Matricule fourni par l'admin (normalisé : sans espaces ni
      // tirets, en majuscules, forme canonique M-LA-171268-01) : il doit
      // être unique dans tout le système — la chaîne complète ne doit
      // exister chez aucun membre, quelle que soit l'église. Les anciens
      // matricules M-XXXX (sans lettres) et M-KA-0001 fournis manuellement
      // restent valides.
      const matriculeFourni = data.matricule ? normalizeMatricule(data.matricule) : null;
      if (matriculeFourni) {
        const clash = await db.query(`SELECT 1 FROM members WHERE matricule = $1`, [matriculeFourni]);
        if (clash.rowCount && clash.rowCount > 0) {
          return reply.code(409).send({
            error: "matricule_taken",
            message: "Ce matricule est déjà utilisé par un autre membre.",
          });
        }
      }
      // Matricule : fourni par le client ou généré (système du permis
      // du Québec : M-LA-171268-01 — initiales + date de naissance +
      // séquence, unique dans tout le système). Réessaie en cas de
      // collision (contrainte UNIQUE church_id + matricule).
      let lastError: unknown = null;
      for (let attempt = 0; attempt < 3; attempt++) {
        const matricule = matriculeFourni ?? (await generateMatricule(db, data.full_name, data.birth_date ?? null, sexeNorm));
        try {
          const { rows } = await db.query(
            `INSERT INTO members
               (church_id, matricule, full_name, phone, email, birth_date, sexe, department, fonction, poste, cell_group, status, date_mariage, date_conversion)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
             RETURNING id, church_id, matricule, full_name, phone, email, birth_date, sexe,
                       department, fonction, poste, cell_group, status, created_at,
                       photo_url, date_mariage, date_conversion`,
            [
              req.session.churchId,
              matricule,
              data.full_name,
              data.phone ?? null,
              data.email ?? null,
              data.birth_date ?? null,
              sexeNorm,
              data.department ?? null,
              data.fonction ?? null,
              data.poste ?? null,
              data.cell_group ?? null,
              data.status,
              data.date_mariage ?? null,
              data.date_conversion ?? null,
            ],
          );
          await auditLog(db, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "membre.cree",
            details: { membre_id: rows[0].id, matricule, nom: data.full_name },
          });
          return reply.code(201).send(rows[0]);
        } catch (e) {
          const code = (e as { code?: string }).code;
          if (code === "23505" && !data.matricule) {
            lastError = e; // collision sur le matricule généré : on régénère.
            continue;
          }
          throw e;
        }
      }
      throw lastError ?? new Error("Création du membre impossible.");
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Modification d'un membre (le matricule ne change pas). --------------
  // Les champs sont nullables : l'application envoie explicitement null pour
  // effacer une valeur (une date par exemple), ce n'est pas une erreur.
  const updateMembreSchema = z.object({
    full_name: z.string().min(2).max(200).optional(),
    phone: z.string().min(8).max(30).nullable().optional(),
    email: z.string().email().max(254).nullable().optional(),
    birth_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").nullable().optional(),
    /** Sexe (M ou F) : modifiable (correction) — le matricule, lui, ne change pas. */
    sexe: z.string().max(20).nullable().optional(),
    department: z.string().min(2).max(120).nullable().optional(),
    fonction: z.string().min(2).max(120).nullable().optional(),
    poste: z.string().min(2).max(120).nullable().optional(),
    cell_group: z.string().min(2).max(120).nullable().optional(),
    status: z.enum(["actif", "nouveau_converti", "inactif"]).nullable().optional(),
    photo_url: z.string().url().max(500).nullable().optional(),
    date_mariage: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").nullable().optional(),
    date_conversion: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date au format AAAA-MM-JJ.").nullable().optional(),
  });
  app.patch(
    "/membres/:id",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = updateMembreSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données du membre invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const data = parsed.data as Record<string, unknown>;
      if (data.sexe !== undefined) data.sexe = normalizeSexe(data.sexe);
      const keys = ["full_name", "phone", "email", "birth_date", "sexe", "department", "fonction", "poste", "cell_group", "status", "photo_url", "date_mariage", "date_conversion"].filter(
        (c) => data[c] !== undefined,
      );
      if (keys.length === 0) {
        return reply.code(400).send({ error: "invalid_input", message: "Rien à modifier." });
      }
      try {
        const sets = keys.map((c, i) => `${c} = $${i + 3}`).join(", ");
        const { rows } = await db.query(
          `UPDATE members SET ${sets} WHERE id = $1 AND church_id = $2
           RETURNING id, church_id, matricule, full_name, phone, email, birth_date, sexe,
                     department, fonction, poste, cell_group, status, created_at,
                     photo_url, date_mariage, date_conversion`,
          [(req.params as { id: string }).id, req.session.churchId, ...keys.map((c) => data[c])],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "membre.modifie",
          details: { membre_id: rows[0].id },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Suppression d'un membre (les contributions passent à membre NULL,
  //    les présences / statuts / baptêmes / liens sont supprimés en cascade).
  app.delete(
    "/membres/:id",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `DELETE FROM members WHERE id = $1 AND church_id = $2 RETURNING id`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "membre.supprime",
          details: { membre_id: rows[0].id },
        });
        return reply.send({ ok: true, id: rows[0].id });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
