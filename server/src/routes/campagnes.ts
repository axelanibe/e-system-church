import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * US2 — Campagnes de collecte.
 *
 * GET   /campagnes            — liste de mon église, avec total collecté.
 * GET   /campagnes/:id        — une campagne, avec ses contributions confirmées.
 * POST  /campagnes            — créer (admin_eglise, tresorier).
 * PATCH /campagnes/:id        — modifier, sauf clôturée (admin_eglise, tresorier).
 * PATCH /campagnes/:id/cloturer — clôturer, définitif (admin_eglise, tresorier).
 *
 * Total collecté = somme des contributions CONFIRMÉES affectées ; au-delà
 * de 100 % de l'objectif, l'écran l'indique explicitement (dépassé), le
 * pourcentage n'est jamais plafonné. Clôturer interdit toute nouvelle
 * affectation, sans modifier les contributions déjà enregistrées.
 * Un membre simple ne voit que les campagnes dont l'église a choisi de
 * montrer le total (`visible_membres`), les autres lui sont invisibles
 * (404 sur le détail, absentes de la liste).
 */

const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const createSchema = z
  .object({
    nom: z.string().trim().min(2).max(120),
    objectif_fcfa: z.number().int().positive().max(100_000_000),
    date_debut: dateSchema,
    date_fin: dateSchema,
    statut: z.enum(["brouillon", "active"]).optional(),
    visible_membres: z.boolean().optional(),
  })
  .refine((d) => d.date_fin > d.date_debut, {
    message: "La date de fin doit être postérieure à la date de début.",
  });

const updateSchema = z
  .object({
    nom: z.string().trim().min(2).max(120).optional(),
    objectif_fcfa: z.number().int().positive().max(100_000_000).optional(),
    date_debut: dateSchema.optional(),
    date_fin: dateSchema.optional(),
    statut: z.enum(["brouillon", "active"]).optional(),
    visible_membres: z.boolean().optional(),
  })
  .refine((d) => d.nom !== undefined || d.objectif_fcfa !== undefined || d.date_debut !== undefined || d.date_fin !== undefined || d.statut !== undefined || d.visible_membres !== undefined, {
    message: "Aucun champ à modifier.",
  });

const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte", "membre"];
const WRITE_ROLES = ["admin_eglise", "tresorier"];

/** Colonnes + total collecté (confirmées seulement), pourcentage, dépassement. */
const SELECT_CAMPAGNE = `
  SELECT c.id, c.church_id, c.nom, c.objectif_fcfa, c.date_debut, c.date_fin,
         c.statut, c.visible_membres, c.created_at,
         coalesce(sum(co.amount_fcfa) FILTER (WHERE co.status = 'confirme'), 0)::int AS total_collecte,
         count(co.id) FILTER (WHERE co.status = 'confirme')::int AS nombre_contributions
    FROM campagnes c
    LEFT JOIN contributions co ON co.campagne_id = c.id
`;

function avecProgression(row: Record<string, unknown>) {
  const objectif = Number(row["objectif_fcfa"]);
  const total = Number(row["total_collecte"]);
  const pourcentage = objectif > 0 ? Math.round((total / objectif) * 100) : 0;
  return { ...row, total_collecte: total, pourcentage, depasse: pourcentage > 100 };
}

export function registerCampagnesRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/campagnes",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        // Un membre ne voit que les campagnes dont l'église montre le total.
        const filtreMembre =
          req.session.role === "membre" ? ` AND c.visible_membres = true` : "";
        const { rows } = await db.query(
          `${SELECT_CAMPAGNE}
            WHERE c.church_id = $1${filtreMembre}
            GROUP BY c.id
            ORDER BY c.date_debut DESC, c.created_at DESC`,
          [req.session.churchId],
        );
        return reply.send({ campagnes: rows.map(avecProgression) });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/campagnes/:id",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const filtreMembre =
          req.session.role === "membre" ? ` AND c.visible_membres = true` : "";
        const { rows } = await db.query(
          `${SELECT_CAMPAGNE}
            WHERE c.id = $1 AND c.church_id = $2${filtreMembre}
            GROUP BY c.id`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Campagne introuvable." });
        }
        const { rows: contributions } = await db.query(
          `SELECT co.id, co.type, co.amount_fcfa, co.status, co.created_at,
                  co.member_id, m.full_name AS membre_nom
             FROM contributions co
             LEFT JOIN members m ON m.id = co.member_id
            WHERE co.campagne_id = $1 AND co.church_id = $2 AND co.status = 'confirme'
            ORDER BY co.created_at DESC LIMIT 50`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        return reply.send({ campagne: avecProgression(rows[0]), contributions });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/campagnes",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = createSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données de la campagne invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const d = parsed.data;
      try {
        const { rows } = await db.query(
          `INSERT INTO campagnes
             (church_id, nom, objectif_fcfa, date_debut, date_fin, statut, visible_membres)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id, church_id, nom, objectif_fcfa, date_debut, date_fin,
                     statut, visible_membres, created_at`,
          [
            req.session.churchId,
            d.nom,
            d.objectif_fcfa,
            d.date_debut,
            d.date_fin,
            d.statut ?? "brouillon",
            d.visible_membres ?? false,
          ],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "campagne.creee",
          details: { campagne_id: rows[0].id, nom: d.nom, objectif_fcfa: d.objectif_fcfa },
        });
        return reply.code(201).send({ ...rows[0], total_collecte: 0, pourcentage: 0, depasse: false, nombre_contributions: 0 });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/campagnes/:id",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      const parsed = updateSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données de la campagne invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const d = parsed.data;
      try {
        const { rows: existantes } = await db.query(
          `SELECT date_debut, date_fin, statut FROM campagnes WHERE id = $1 AND church_id = $2`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (existantes.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Campagne introuvable." });
        }
        if (existantes[0].statut === "cloturee") {
          return reply.code(409).send({
            error: "conflict",
            message: "Une campagne clôturée ne peut plus être modifiée.",
          });
        }
        const debut = d.date_debut ?? (existantes[0].date_debut as Date).toISOString().slice(0, 10);
        const fin = d.date_fin ?? (existantes[0].date_fin as Date).toISOString().slice(0, 10);
        if (fin <= debut) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "La date de fin doit être postérieure à la date de début.",
          });
        }
        const champs: string[] = [];
        const valeurs: unknown[] = [req.session.churchId, (req.params as { id: string }).id];
        const pousser = (colonne: string, valeur: unknown) => {
          valeurs.push(valeur);
          champs.push(`${colonne} = $${valeurs.length}`);
        };
        if (d.nom !== undefined) pousser("nom", d.nom);
        if (d.objectif_fcfa !== undefined) pousser("objectif_fcfa", d.objectif_fcfa);
        if (d.date_debut !== undefined) pousser("date_debut", d.date_debut);
        if (d.date_fin !== undefined) pousser("date_fin", d.date_fin);
        if (d.statut !== undefined) pousser("statut", d.statut);
        if (d.visible_membres !== undefined) pousser("visible_membres", d.visible_membres);
        const { rows } = await db.query(
          `UPDATE campagnes SET ${champs.join(", ")}
            WHERE church_id = $1 AND id = $2
            RETURNING id, church_id, nom, objectif_fcfa, date_debut, date_fin,
                      statut, visible_membres, created_at`,
          valeurs,
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "campagne.modifiee",
          details: { campagne_id: rows[0].id, ...d },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/campagnes/:id/cloturer",
    { preHandler: [requireAuth(db), requireRole(...WRITE_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `UPDATE campagnes SET statut = 'cloturee'
            WHERE id = $1 AND church_id = $2 AND statut <> 'cloturee'
            RETURNING id, nom, objectif_fcfa, statut`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Campagne introuvable, ou déjà clôturée.",
          });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "campagne.cloturee",
          details: { campagne_id: rows[0].id, nom: rows[0].nom },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}

/**
 * Vérifie qu'une campagne peut recevoir une contribution : elle existe,
 * appartient à l'église de la session, est active, et la contribution
 * n'est pas une dépense. Renvoie une réponse d'erreur à envoyer, ou null.
 */
export async function verifierCampagneAffectation(
  db: Pool,
  churchId: string,
  campagneId: string,
  typeContribution: string,
): Promise<{ code: number; error: string; message: string } | null> {
  if (typeContribution === "depense") {
    return { code: 400, error: "invalid_input", message: "Une dépense ne peut pas être affectée à une campagne." };
  }
  // Tranche T7 : une cotisation est une redevance de membre, pas un don
  // de campagne — elle ne rentre pas dans le total collecté.
  if (typeContribution === "cotisation") {
    return { code: 400, error: "invalid_input", message: "Une cotisation ne peut pas être affectée à une campagne." };
  }
  const { rows } = await db.query(
    `SELECT statut FROM campagnes WHERE id = $1 AND church_id = $2`,
    [campagneId, churchId],
  );
  if (rows.length === 0) {
    return { code: 400, error: "invalid_reference", message: "Campagne introuvable pour cette église." };
  }
  if (rows[0].statut !== "active") {
    return { code: 409, error: "conflict", message: "Seule une campagne active peut recevoir des contributions." };
  }
  return null;
}
