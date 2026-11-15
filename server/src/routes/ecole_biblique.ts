import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import {
  READ_ALL,
  WRITE_STD,
  existsInChurch,
  invalidInput,
  memberInChurch,
  registerCrud,
} from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import type { Session } from "../middleware.js";

/**
 * École biblique (tranche T9, Lot B).
 *
 * Cours et leçons : créés par l'église (admin / responsable de culte),
 * jamais pré-remplis — aucun contenu fictif. Inscription : le membre
 * s'inscrit lui-même (son propre member_id, résolu depuis son compte),
 * l'admin / le responsable peut inscrire n'importe quel membre.
 * Progression : une leçon terminée par inscription ; quand toutes les
 * leçons du cours sont terminées, le serveur pose le statut 'termine'.
 * Le statut 'termine' ne se pose jamais par PATCH (géré par le serveur).
 */

const uuid = z.string().uuid();
const niveaux = ["debutant", "intermediaire", "avance"] as const;

const pagination = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
  cours_id: uuid.optional(),
  member_id: uuid.optional(),
  statut: z.enum(["inscrit", "termine", "abandonne"]).optional(),
});

/** member_id lié au compte de la session (null si le compte n'a pas de membre). */
async function membreDeSession(
  db: Pool,
  session: Session,
): Promise<string | null> {
  const { rows } = await db.query<{ member_id: string | null }>(
    `SELECT member_id FROM users WHERE id = $1`,
    [session.userId],
  );
  return rows[0]?.member_id ?? null;
}

/** Vrai si l'inscription appartient au membre de la session. */
async function inscriptionEstMienne(
  db: Pool,
  session: Session,
  inscriptionId: string,
): Promise<boolean> {
  const membreId = await membreDeSession(db, session);
  if (!membreId) return false;
  const { rowCount } = await db.query(
    `SELECT 1 FROM inscriptions_ecole
      WHERE id = $1 AND church_id = $2 AND member_id = $3`,
    [inscriptionId, session.churchId, membreId],
  );
  return (rowCount ?? 0) > 0;
}

export function registerEcoleBibliqueRoutes(app: FastifyInstance, db: Pool): void {
  // -- Cours -------------------------------------------------------------------
  registerCrud(app, db, {
    base: "/cours-ecole",
    table: "cours_ecole",
    columns: ["titre", "description", "niveau", "actif"],
    createSchema: z.object({
      titre: z.string().min(2).max(200),
      description: z.string().max(2000).optional(),
      niveau: z.enum(niveaux).optional(),
      actif: z.boolean().default(true),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "cours_ecole",
    searchColumn: "titre",
    orderBy: "actif DESC, titre ASC",
    beforeDelete: async (db2, churchId, id) => {
      const lecons = await db2.query(
        `SELECT count(*)::int AS n FROM lecons_ecole
          WHERE cours_id = $1 AND church_id = $2`,
        [id, churchId],
      );
      if (lecons.rows[0].n > 0) {
        return "Ce cours a encore des leçons : supprimez-les d'abord.";
      }
      const inscriptions = await db2.query(
        `SELECT count(*)::int AS n FROM inscriptions_ecole
          WHERE cours_id = $1 AND church_id = $2`,
        [id, churchId],
      );
      if (inscriptions.rows[0].n > 0) {
        return "Ce cours a encore des inscriptions : il ne peut pas être supprimé.";
      }
      return null;
    },
  });

  // -- Leçons ------------------------------------------------------------------
  registerCrud(app, db, {
    base: "/lecons-ecole",
    table: "lecons_ecole",
    columns: ["cours_id", "ordre", "titre", "contenu", "reference_biblique"],
    createSchema: z.object({
      cours_id: uuid,
      ordre: z.number().int().min(1).max(1000),
      titre: z.string().min(2).max(200),
      contenu: z.string().max(20000).optional(),
      reference_biblique: z.string().max(100).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "lecon_ecole",
    searchColumn: "titre",
    orderBy: "ordre ASC",
    filters: { cours_id: "cours_id" },
    validate: async (db2, churchId, data) => {
      if (!(await existsInChurch(db2, "cours_ecole", churchId, data.cours_id as string))) {
        return "Cours introuvable dans votre église.";
      }
      const doublon = await db2.query(
        `SELECT 1 FROM lecons_ecole
          WHERE cours_id = $1 AND church_id = $2 AND ordre = $3`,
        [data.cours_id, churchId, data.ordre],
      );
      if ((doublon.rowCount ?? 0) > 0) {
        return "L'ordre de cette leçon existe déjà dans ce cours.";
      }
      return null;
    },
    validateUpdate: async (db2, churchId, id, data) => {
      if (data.cours_id && !(await existsInChurch(db2, "cours_ecole", churchId, data.cours_id as string))) {
        return "Cours introuvable dans votre église.";
      }
      const actuel = await db2.query(
        `SELECT cours_id, ordre FROM lecons_ecole WHERE id = $1 AND church_id = $2`,
        [id, churchId],
      );
      if (actuel.rows.length === 0) return "Leçon introuvable.";
      const coursId = (data.cours_id as string | undefined) ?? actuel.rows[0].cours_id;
      const ordre = (data.ordre as number | undefined) ?? actuel.rows[0].ordre;
      const doublon = await db2.query(
        `SELECT 1 FROM lecons_ecole
          WHERE cours_id = $1 AND church_id = $2 AND ordre = $3 AND id <> $4`,
        [coursId, churchId, ordre, id],
      );
      if ((doublon.rowCount ?? 0) > 0) {
        return "L'ordre de cette leçon existe déjà dans ce cours.";
      }
      return null;
    },
  });

  const lecture = [requireAuth(db), requireRole(...READ_ALL)];

  // -- Inscriptions : création (auto-inscription du membre) --------------------
  app.post("/inscriptions-ecole", { preHandler: lecture }, async (req, reply) => {
    const parsed = z
      .object({ cours_id: uuid, member_id: uuid.optional() })
      .safeParse(req.body);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const session = req.session;
    try {
      let memberId: string;
      if (session.role === "membre") {
        const mien = await membreDeSession(db, session);
        if (!mien) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Votre compte n'est lié à aucun membre.",
          });
        }
        if (parsed.data.member_id && parsed.data.member_id !== mien) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Vous ne pouvez inscrire que vous-même.",
          });
        }
        memberId = mien;
      } else {
        if (!parsed.data.member_id) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "member_id est requis pour inscrire un membre.",
          });
        }
        memberId = parsed.data.member_id;
      }
      const cours = await db.query(
        `SELECT id, actif FROM cours_ecole WHERE id = $1 AND church_id = $2`,
        [parsed.data.cours_id, session.churchId],
      );
      if (cours.rows.length === 0) {
        return reply.code(404).send({
          error: "not_found",
          message: "Cours introuvable dans votre église.",
        });
      }
      if (!cours.rows[0].actif) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Ce cours n'est pas ouvert aux inscriptions.",
        });
      }
      if (!(await memberInChurch(db, session.churchId, memberId))) {
        return reply.code(400).send({
          error: "invalid_reference",
          message: "Membre introuvable dans votre église.",
        });
      }
      const { rows } = await db.query(
        `INSERT INTO inscriptions_ecole (church_id, cours_id, member_id)
         VALUES ($1, $2, $3) RETURNING *`,
        [session.churchId, parsed.data.cours_id, memberId],
      );
      await auditLog(db, {
        churchId: session.churchId,
        userId: session.userId,
        action: "inscription_ecole.cree",
        details: { id: rows[0].id, cours_id: parsed.data.cours_id, member_id: memberId },
      });
      return reply.code(201).send(rows[0]);
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Inscriptions : liste (le membre ne voit que les siennes) ----------------
  app.get("/inscriptions-ecole", { preHandler: lecture }, async (req, reply) => {
    const parsed = pagination.safeParse(req.query);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const session = req.session;
    const { limit, offset } = parsed.data;
    try {
      let membreId: string | null = null;
      if (session.role === "membre") {
        membreId = await membreDeSession(db, session);
        if (!membreId) return reply.send({ total: 0, items: [] });
      }
      const conditions = [`church_id = $1`];
      const values: unknown[] = [session.churchId];
      if (membreId) {
        values.push(membreId);
        conditions.push(`member_id = $${values.length}`);
      } else if (parsed.data.member_id) {
        values.push(parsed.data.member_id);
        conditions.push(`member_id = $${values.length}`);
      }
      if (parsed.data.cours_id) {
        values.push(parsed.data.cours_id);
        conditions.push(`cours_id = $${values.length}`);
      }
      if (parsed.data.statut) {
        values.push(parsed.data.statut);
        conditions.push(`statut = $${values.length}`);
      }
      const where = `WHERE ${conditions.join(" AND ")}`;
      const total = await db.query<{ n: string }>(
        `SELECT count(*)::text AS n FROM inscriptions_ecole ${where}`,
        values,
      );
      const { rows } = await db.query(
        `SELECT * FROM inscriptions_ecole ${where}
          ORDER BY created_at DESC
          LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
        [...values, limit, offset],
      );
      return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Inscription : lecture d'un élément (propriétaire ou rôles de gestion) ---
  app.get("/inscriptions-ecole/:id", { preHandler: lecture }, async (req, reply) => {
    const session = req.session;
    const id = (req.params as { id: string }).id;
    try {
      const { rows } = await db.query(
        `SELECT * FROM inscriptions_ecole WHERE id = $1 AND church_id = $2`,
        [id, session.churchId],
      );
      if (rows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Inscription introuvable." });
      }
      if (session.role === "membre" && !(await inscriptionEstMienne(db, session, id))) {
        return reply.code(404).send({ error: "not_found", message: "Inscription introuvable." });
      }
      return reply.send(rows[0]);
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Inscription : changement de statut (abandon / reprise, jamais 'termine')
  app.patch("/inscriptions-ecole/:id", { preHandler: lecture }, async (req, reply) => {
    const parsed = z
      .object({ statut: z.enum(["inscrit", "abandonne"]) })
      .safeParse(req.body);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const session = req.session;
    const id = (req.params as { id: string }).id;
    try {
      const actuel = await db.query(
        `SELECT * FROM inscriptions_ecole WHERE id = $1 AND church_id = $2`,
        [id, session.churchId],
      );
      if (actuel.rows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Inscription introuvable." });
      }
      const mienne =
        session.role === "membre" && (await inscriptionEstMienne(db, session, id));
      const gestionnaire = WRITE_STD.includes(session.role);
      if (!mienne && !gestionnaire) {
        return reply.code(403).send({
          error: "forbidden",
          message: "Vous ne pouvez pas modifier cette inscription.",
        });
      }
      const { rows } = await db.query(
        `UPDATE inscriptions_ecole SET statut = $1 WHERE id = $2 AND church_id = $3 RETURNING *`,
        [parsed.data.statut, id, session.churchId],
      );
      await auditLog(db, {
        churchId: session.churchId,
        userId: session.userId,
        action: "inscription_ecole.modifiee",
        details: { id, statut: parsed.data.statut },
      });
      return reply.send(rows[0]);
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Inscription : suppression (propriétaire ou rôles de gestion) -------------
  app.delete("/inscriptions-ecole/:id", { preHandler: lecture }, async (req, reply) => {
    const session = req.session;
    const id = (req.params as { id: string }).id;
    try {
      const actuel = await db.query(
        `SELECT id FROM inscriptions_ecole WHERE id = $1 AND church_id = $2`,
        [id, session.churchId],
      );
      if (actuel.rows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Inscription introuvable." });
      }
      const mienne =
        session.role === "membre" && (await inscriptionEstMienne(db, session, id));
      const gestionnaire = WRITE_STD.includes(session.role);
      if (!mienne && !gestionnaire) {
        return reply.code(403).send({
          error: "forbidden",
          message: "Vous ne pouvez pas supprimer cette inscription.",
        });
      }
      await db.query(
        `DELETE FROM inscriptions_ecole WHERE id = $1 AND church_id = $2`,
        [id, session.churchId],
      );
      await auditLog(db, {
        churchId: session.churchId,
        userId: session.userId,
        action: "inscription_ecole.supprimee",
        details: { id },
      });
      return reply.code(204).send();
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Progression : marquer une leçon terminée (idempotent) -------------------
  app.post(
    "/inscriptions-ecole/:id/terminer",
    { preHandler: lecture },
    async (req, reply) => {
      const parsed = z.object({ lecon_id: uuid }).safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const session = req.session;
      const id = (req.params as { id: string }).id;
      try {
        const inscription = await db.query(
          `SELECT * FROM inscriptions_ecole WHERE id = $1 AND church_id = $2`,
          [id, session.churchId],
        );
        if (inscription.rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Inscription introuvable." });
        }
        const mienne =
          session.role === "membre" && (await inscriptionEstMienne(db, session, id));
        const gestionnaire = WRITE_STD.includes(session.role);
        if (!mienne && !gestionnaire) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Vous ne pouvez pas marquer la progression de cette inscription.",
          });
        }
        const lecon = await db.query(
          `SELECT id, cours_id FROM lecons_ecole WHERE id = $1 AND church_id = $2`,
          [parsed.data.lecon_id, session.churchId],
        );
        if (lecon.rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Leçon introuvable." });
        }
        if (lecon.rows[0].cours_id !== inscription.rows[0].cours_id) {
          return reply.code(400).send({
            error: "invalid_reference",
            message: "Cette leçon n'appartient pas au cours de cette inscription.",
          });
        }
        const progression = await db.query(
          `INSERT INTO progressions_ecole (church_id, inscription_id, lecon_id)
           VALUES ($1, $2, $3)
           ON CONFLICT (inscription_id, lecon_id) DO NOTHING
           RETURNING *`,
          [session.churchId, id, parsed.data.lecon_id],
        );
        let ligne = progression.rows[0];
        if (!ligne) {
          const deja = await db.query(
            `SELECT * FROM progressions_ecole WHERE inscription_id = $1 AND lecon_id = $2`,
            [id, parsed.data.lecon_id],
          );
          ligne = deja.rows[0];
        }
        // Cours terminé ? Le serveur pose le statut, jamais le client.
        const compte = await db.query(
          `SELECT
             (SELECT count(*)::int FROM lecons_ecole WHERE cours_id = $1 AND church_id = $2) AS total,
             (SELECT count(*)::int FROM progressions_ecole p
                JOIN lecons_ecole l ON l.id = p.lecon_id
               WHERE p.inscription_id = $3 AND l.cours_id = $1 AND p.church_id = $2) AS terminees`,
          [inscription.rows[0].cours_id, session.churchId, id],
        );
        const { total, terminees } = compte.rows[0];
        if (total > 0 && terminees >= total && inscription.rows[0].statut !== "termine") {
          await db.query(
            `UPDATE inscriptions_ecole SET statut = 'termine' WHERE id = $1`,
            [id],
          );
        }
        await auditLog(db, {
          churchId: session.churchId,
          userId: session.userId,
          action: "inscription_ecole.progression",
          details: { id, lecon_id: parsed.data.lecon_id },
        });
        return reply.send(ligne);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Progression : détail d'une inscription (leçons + état) -------------------
  app.get("/inscriptions-ecole/:id/progression", { preHandler: lecture }, async (req, reply) => {
    const session = req.session;
    const id = (req.params as { id: string }).id;
    try {
      const inscription = await db.query(
        `SELECT * FROM inscriptions_ecole WHERE id = $1 AND church_id = $2`,
        [id, session.churchId],
      );
      if (inscription.rows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Inscription introuvable." });
      }
      if (session.role === "membre" && !(await inscriptionEstMienne(db, session, id))) {
        return reply.code(404).send({ error: "not_found", message: "Inscription introuvable." });
      }
      const lecons = await db.query(
        `SELECT l.id, l.ordre, l.titre, l.reference_biblique,
                p.termine_le,
                CASE WHEN p.id IS NULL THEN false ELSE true END AS termine
           FROM lecons_ecole l
           LEFT JOIN progressions_ecole p
             ON p.lecon_id = l.id AND p.inscription_id = $2
          WHERE l.cours_id = $1 AND l.church_id = $3
          ORDER BY l.ordre ASC`,
        [inscription.rows[0].cours_id, id, session.churchId],
      );
      const terminees = lecons.rows.filter((l) => l.termine).length;
      const total = lecons.rows.length;
      return reply.send({
        inscription: inscription.rows[0],
        lecons: lecons.rows,
        terminees,
        total,
        pourcentage: total === 0 ? 0 : Math.round((terminees / total) * 100),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });
}
