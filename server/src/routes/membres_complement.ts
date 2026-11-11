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

/**
 * Module 1 — Membres (compléter) : familles, historique des statuts,
 * baptêmes, liens parent-enfant, départements, cellules, affectations.
 * Les statuts riches (sympathisant, en formation, suspendu, parti) vivent
 * dans membre_statuts ; members.status garde l'enum d'origine.
 */

const uuid = z.string().uuid();
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

/** Nouveau statut riche -> statut simple de members. */
function toMemberStatus(statut: string): "actif" | "nouveau_converti" | "inactif" {
  if (statut === "nouveau_converti") return "nouveau_converti";
  if (statut === "suspendu" || statut === "parti") return "inactif";
  return "actif";
}

export function registerMembresComplementRoutes(app: FastifyInstance, db: Pool) {
  registerCrud(app, db, {
    base: "/familles",
    table: "familles",
    columns: ["nom", "chef_famille_id", "adresse", "telephone"],
    createSchema: z.object({
      nom: z.string().min(2).max(200),
      chef_famille_id: uuid.optional(),
      adresse: z.string().max(300).optional(),
      telephone: z.string().min(8).max(30).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "famille",
    searchColumn: "nom",
    validate: async (db2, churchId, data) => {
      if (data.chef_famille_id && !(await memberInChurch(db2, churchId, data.chef_famille_id as string))) {
        return "Le chef de famille n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/membre-statuts",
    table: "membre_statuts",
    columns: ["member_id", "statut", "ancien_statut", "motif"],
    createSchema: z.object({
      member_id: uuid,
      statut: z.enum(["membre", "sympathisant", "nouveau_converti", "en_formation", "suspendu", "parti"]),
      ancien_statut: z.string().max(50).optional(),
      motif: z.string().max(500).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "membre_statut",
    filters: { member_id: "member_id" },
    orderBy: "created_at DESC",
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/baptemes",
    table: "baptemes",
    columns: ["member_id", "date_bapteme", "lieu", "pasteur", "certificat_numero"],
    createSchema: z.object({
      member_id: uuid,
      date_bapteme: z.string().regex(dateRe, "Date au format AAAA-MM-JJ."),
      lieu: z.string().max(200).optional(),
      pasteur: z.string().max(200).optional(),
      certificat_numero: z.string().max(100).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "bapteme",
    filters: { member_id: "member_id" },
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/liens-parent-enfant",
    table: "liens_parent_enfant",
    columns: ["parent_member_id", "enfant_member_id", "lien", "statut"],
    createSchema: z.object({
      parent_member_id: uuid,
      enfant_member_id: uuid,
      lien: z.enum(["pere", "mere", "tuteur", "autre"]),
      statut: z.enum(["en_attente", "valide", "refuse"]).default("en_attente"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "lien_parent_enfant",
    filters: { enfant_member_id: "enfant_member_id", parent_member_id: "parent_member_id", statut: "statut" },
    validate: async (db2, churchId, data) => {
      const parentOk = await memberInChurch(db2, churchId, data.parent_member_id as string);
      const enfantOk = await memberInChurch(db2, churchId, data.enfant_member_id as string);
      if (!parentOk || !enfantOk) return "Parent ou enfant hors de votre église.";
      if (data.parent_member_id === data.enfant_member_id) return "Un membre ne peut pas être son propre parent.";
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/departements",
    table: "departements",
    columns: ["nom", "description", "responsable_member_id"],
    createSchema: z.object({
      nom: z.string().min(2).max(120),
      description: z.string().max(500).optional(),
      responsable_member_id: uuid.optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "departement",
    searchColumn: "nom",
    validate: async (db2, churchId, data) => {
      if (data.responsable_member_id && !(await memberInChurch(db2, churchId, data.responsable_member_id as string))) {
        return "Le responsable n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/cellules",
    table: "cellules",
    columns: ["nom", "quartier", "responsable_member_id", "jour_reunion", "heure_reunion"],
    createSchema: z.object({
      nom: z.string().min(2).max(120),
      quartier: z.string().max(120).optional(),
      responsable_member_id: uuid.optional(),
      jour_reunion: z.string().max(30).optional(),
      heure_reunion: z.string().max(10).optional(),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "cellule",
    searchColumn: "nom",
    validate: async (db2, churchId, data) => {
      if (data.responsable_member_id && !(await memberInChurch(db2, churchId, data.responsable_member_id as string))) {
        return "Le responsable n'appartient pas à votre église.";
      }
      return null;
    },
  });

  registerCrud(app, db, {
    base: "/membre-departements",
    table: "membre_departements",
    columns: ["member_id", "departement_id", "role"],
    createSchema: z.object({
      member_id: uuid,
      departement_id: uuid,
      role: z.string().min(2).max(80).default("membre"),
    }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "membre_departement",
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
    base: "/membre-cellules",
    table: "membre_cellules",
    columns: ["member_id", "cellule_id"],
    createSchema: z.object({ member_id: uuid, cellule_id: uuid }),
    readRoles: READ_ALL,
    writeRoles: WRITE_STD,
    audit: "membre_cellule",
    filters: { member_id: "member_id", cellule_id: "cellule_id" },
    validate: async (db2, churchId, data) => {
      if (!(await memberInChurch(db2, churchId, data.member_id as string))) {
        return "Ce membre n'appartient pas à votre église.";
      }
      if (!(await existsInChurch(db2, "cellules", churchId, data.cellule_id as string))) {
        return "Cellule introuvable dans votre église.";
      }
      return null;
    },
  });

  // -- Changement de statut d'un membre (écrit l'historique + met à jour
  //    members.status avec le statut simple correspondant). -----------------
  const statutSchema = z.object({
    statut: z.enum(["membre", "sympathisant", "nouveau_converti", "en_formation", "suspendu", "parti"]),
    motif: z.string().max(500).optional(),
  });
  app.post(
    "/membres/:id/statut",
    { preHandler: [requireAuth(db), requireRole(...WRITE_STD)] },
    async (req, reply) => {
      const parsed = statutSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const memberId = (req.params as { id: string }).id;
      try {
        const { rows: memberRows } = await db.query(
          `SELECT id, status FROM members WHERE id = $1 AND church_id = $2`,
          [memberId, req.session.churchId],
        );
        if (memberRows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
        }
        const ancien = memberRows[0].status as string;
        const simple = toMemberStatus(parsed.data.statut);
        await db.query(
          `INSERT INTO membre_statuts (church_id, member_id, statut, ancien_statut, motif, change_par)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [req.session.churchId, memberId, parsed.data.statut, ancien, parsed.data.motif ?? null, req.session.userId],
        );
        await db.query(
          `UPDATE members SET status = $3, updated_at = now() WHERE id = $1 AND church_id = $2`,
          [memberId, req.session.churchId, simple],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "membre.statut_change",
          details: { membre_id: memberId, statut: parsed.data.statut },
        });
        return reply.send({ membre_id: memberId, statut: parsed.data.statut, statut_simple: simple });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Fiche membre enrichie : membre + historique, baptême, départements,
  //    cellules, liens parent-enfant. ----------------------------------------
  app.get(
    "/membres/:id/complet",
    { preHandler: [requireAuth(db), requireRole(...READ_ALL)] },
    async (req, reply) => {
      const memberId = (req.params as { id: string }).id;
      try {
        const { rows: memberRows } = await db.query(
          `SELECT * FROM members WHERE id = $1 AND church_id = $2`,
          [memberId, req.session.churchId],
        );
        if (memberRows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
        }
        const churchId = req.session.churchId;
        const [statuts, bapteme, departs, cellules, liensParents, liensEnfants] = await Promise.all([
          db.query(`SELECT * FROM membre_statuts WHERE member_id = $1 AND church_id = $2 ORDER BY created_at DESC`, [memberId, churchId]),
          db.query(`SELECT * FROM baptemes WHERE member_id = $1 AND church_id = $2`, [memberId, churchId]),
          db.query(
            `SELECT d.* FROM membre_departements md JOIN departements d ON d.id = md.departement_id
              WHERE md.member_id = $1 AND md.church_id = $2`,
            [memberId, churchId],
          ),
          db.query(
            `SELECT c.* FROM membre_cellules mc JOIN cellules c ON c.id = mc.cellule_id
              WHERE mc.member_id = $1 AND mc.church_id = $2`,
            [memberId, churchId],
          ),
          db.query(
            `SELECT l.*, m.full_name AS enfant_nom, m.matricule AS enfant_matricule
               FROM liens_parent_enfant l JOIN members m ON m.id = l.enfant_member_id
              WHERE l.parent_member_id = $1 AND l.church_id = $2`,
            [memberId, churchId],
          ),
          db.query(
            `SELECT l.*, m.full_name AS parent_nom, m.matricule AS parent_matricule
               FROM liens_parent_enfant l JOIN members m ON m.id = l.parent_member_id
              WHERE l.enfant_member_id = $1 AND l.church_id = $2`,
            [memberId, churchId],
          ),
        ]);
        return reply.send({
          membre: memberRows[0],
          historique_statuts: statuts.rows,
          bapteme: bapteme.rows[0] ?? null,
          departements: departs.rows,
          cellules: cellules.rows,
          enfants: liensParents.rows,
          parents: liensEnfants.rows,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
