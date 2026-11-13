import type { FastifyInstance, FastifyReply } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "./auth.js";
import { dbError, requireAuth, requireRole } from "./middleware.js";
import type { Session } from "./middleware.js";

/**
 * Usine de routes CRUD standard pour les ressources « par église ».
 *
 * Conventions (identiques aux routes MVP) :
 * - isolation stricte : chaque requête est filtrée par la church_id de
 *   la session, lue dans le JWT et revérifiée en base (requireAuth) ;
 * - requêtes paramétrées ; erreurs PG connues mappées par dbError ;
 * - toute écriture est journalisée dans audit_logs ;
 * - liste paginée : `GET <base>?limit&offset` → `{ total, items }`.
 *
 * La configuration par ressource tient en quelques lignes (voir les
 * fichiers de routes) ; les comportements spéciaux (pointage, validations
 * en deux étapes, exports…) sont écrits explicitement à côté.
 */

// -- Rôles standards ---------------------------------------------------------
/** Lecture pour tous les rôles de l'église. */
export const READ_ALL = ["admin_eglise", "tresorier", "responsable_culte", "membre"];
/** Écriture classique : admin + responsable de culte. */
export const WRITE_STD = ["admin_eglise", "responsable_culte"];
/** Écriture réservée à l'admin de l'église. */
export const WRITE_ADMIN = ["admin_eglise"];
/** Écriture finances : admin + trésorier. */
export const WRITE_FINANCES = ["admin_eglise", "tresorier"];

export interface CrudOptions {
  /** Chemin de base, ex. '/familles'. */
  base: string;
  /** Table PostgreSQL. */
  table: string;
  /** Colonnes insérables (hors id, church_id, created_at). */
  columns: string[];
  /** Schéma zod du corps de création. */
  createSchema: z.ZodObject<z.ZodRawShape>;
  /** Schéma zod de mise à jour (défaut : création rendue partielle). */
  updateSchema?: z.ZodObject<z.ZodRawShape>;
  readRoles: string[];
  writeRoles: string[];
  /**
   * Rôles autorisés à CRÉER (défaut : writeRoles). Sert quand la création
   * est ouverte à tous les membres mais que la modification / suppression
   * est restreinte (ex. demandes de prière : tout membre dépose, seuls
   * l'admin et le responsable de culte modifient ou suppriment).
   */
  createRoles?: string[];
  /**
   * Rôles autorisés à MODIFIER et SUPPRIMER (défaut : writeRoles).
   */
  updateDeleteRoles?: string[];
  /** Préfixe d'audit, ex. 'famille' → 'famille.cree'. */
  audit: string;
  /**
   * Journaliser les lectures dans audit_logs (action `<audit>.lu`).
   * À activer pour les données sensibles (US17 : consultation tracée).
   */
  logReads?: boolean;
  /**
   * Portée de lecture : condition SQL supplémentaire (et ses paramètres)
   * appliquée à la liste et à la lecture d'un élément. Sert à rendre un
   * drapeau effectif côté serveur (ex. demandes de prière confidentielles
   * invisibles aux rôles non autorisés). `paramOffset` = nombre de
   * paramètres déjà placés : les `$n` de la condition doivent commencer
   * à `paramOffset + 1`. Retourne null quand aucune restriction ne
   * s'applique (ex. rôle autorisé).
   */
  readScope?: (
    db: Pool,
    session: Session,
    paramOffset: number,
  ) => Promise<{ condition: string; values: unknown[] } | null>;
  orderBy?: string;
  /** Filtres d'égalité : paramètre de requête -> colonne. */
  filters?: Record<string, string>;
  /** Colonne de recherche texte (ILIKE) via ?q=. */
  searchColumn?: string;
  /** Validation métier : message d'erreur ou null si OK. */
  validate?: (
    db: Pool,
    churchId: string,
    data: Record<string, unknown>,
    userId: string,
  ) => Promise<string | null>;
  /**
   * Validation métier à la MISE À JOUR (PATCH) : message d'erreur ou
   * null si OK. Sert à fermer un contournement par PATCH générique
   * (ex. refuser le changement de `statut` d'une dépense hors de la
   * machine à états, ou revalider un chevauchement de réservation).
   * `data` ne contient que les champs envoyés par le client.
   */
  validateUpdate?: (
    db: Pool,
    churchId: string,
    id: string,
    data: Record<string, unknown>,
  ) => Promise<string | null>;
  /**
   * Garde avant suppression : message d'erreur ou null si OK. Sert à
   * refuser la suppression d'un élément encore utilisé (ex. département
   * ou fonction lié à des membres) sans supprimer les données liées.
   */
  beforeDelete?: (
    db: Pool,
    churchId: string,
    id: string,
  ) => Promise<string | null>;
}

export function invalidInput(reply: FastifyReply, error: z.ZodError): void {
  reply.code(400).send({
    error: "invalid_input",
    message: "Données invalides.",
    details: error.issues.map((i) => i.message),
  });
}

/** Vrai si la ligne `id` existe dans `table` pour cette église. */
export async function existsInChurch(
  db: Pool,
  table: string,
  churchId: string,
  id: string | null | undefined,
): Promise<boolean> {
  if (!id) return false;
  const { rowCount } = await db.query(
    `SELECT 1 FROM ${table} WHERE id = $1 AND church_id = $2`,
    [id, churchId],
  );
  return (rowCount ?? 0) > 0;
}

/** Vrai si le membre appartient à l'église de la session. */
export async function memberInChurch(
  db: Pool,
  churchId: string,
  memberId: string | null | undefined,
): Promise<boolean> {
  return existsInChurch(db, "members", churchId, memberId);
}

function listQueryWithFilters(filters: Record<string, string>) {
  const shape: Record<string, z.ZodTypeAny> = {
    limit: z.coerce.number().int().min(1).max(100).default(50),
    offset: z.coerce.number().int().min(0).default(0),
    q: z.string().max(200).optional(),
  };
  for (const param of Object.keys(filters)) {
    shape[param] = z.string().max(200).optional();
  }
  return z.object(shape);
}

export function registerCrud(app: FastifyInstance, db: Pool, opts: CrudOptions): void {
  const orderBy = opts.orderBy ?? "created_at DESC";
  // Tous les modules sont actifs pour toutes les églises (règle du
  // 11/11/2026) : plus aucune garde de module ici.
  const lecture = [requireAuth(db), requireRole(...opts.readRoles)];
  // Création et modification / suppression peuvent avoir des rôles
  // différents (ex. demandes de prière : création ouverte, modification
  // restreinte). Par défaut, les deux valent writeRoles.
  const creation = [requireAuth(db), requireRole(...(opts.createRoles ?? opts.writeRoles))];
  const majSuppression = [requireAuth(db), requireRole(...(opts.updateDeleteRoles ?? opts.writeRoles))];
  const querySchema = listQueryWithFilters(opts.filters ?? {});
  const updateSchema = opts.updateSchema ?? opts.createSchema.partial();

  // -- Liste -----------------------------------------------------------------
  app.get(opts.base, { preHandler: lecture }, async (req, reply) => {
    const parsed = querySchema.safeParse(req.query);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const query = parsed.data as Record<string, unknown>;
    const limit = query.limit as number;
    const offset = query.offset as number;
    try {
      const conditions = [`church_id = $1`];
      const values: unknown[] = [req.session.churchId];
      for (const [param, column] of Object.entries(opts.filters ?? {})) {
        const value = query[param];
        if (typeof value === "string" && value.length > 0) {
          values.push(value);
          conditions.push(`${column} = $${values.length}`);
        }
      }
      if (opts.searchColumn && typeof query.q === "string" && query.q.length > 0) {
        values.push(`%${query.q}%`);
        conditions.push(`${opts.searchColumn} ILIKE $${values.length}`);
      }
      if (opts.readScope) {
        const scope = await opts.readScope(db, req.session, values.length);
        if (scope) {
          conditions.push(`(${scope.condition})`);
          values.push(...scope.values);
        }
      }
      const where = `WHERE ${conditions.join(" AND ")}`;
      const total = await db.query<{ n: string }>(
        `SELECT count(*)::text AS n FROM ${opts.table} ${where}`,
        values,
      );
      const { rows } = await db.query(
        `SELECT * FROM ${opts.table} ${where}
          ORDER BY ${orderBy}
          LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
        [...values, limit, offset],
      );
      if (opts.logReads) {
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: `${opts.audit}.lu`,
          details: { total: Number(total.rows[0]?.n ?? 0), limit, offset },
        });
      }
      return reply.send({ total: Number(total.rows[0]?.n ?? 0), items: rows });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Lecture d'un élément ----------------------------------------------------
  app.get(
    `${opts.base}/:id`,
    { preHandler: lecture },
    async (req, reply) => {
      try {
        const id = (req.params as { id: string }).id;
        const values: unknown[] = [id, req.session.churchId];
        let scopeCondition = "";
        if (opts.readScope) {
          const scope = await opts.readScope(db, req.session, values.length);
          if (scope) {
            scopeCondition = ` AND (${scope.condition})`;
            values.push(...scope.values);
          }
        }
        const { rows } = await db.query(
          `SELECT * FROM ${opts.table} WHERE id = $1 AND church_id = $2${scopeCondition}`,
          values,
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Élément introuvable." });
        }
        if (opts.logReads) {
          await auditLog(db, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: `${opts.audit}.lu`,
            details: { id: rows[0].id },
          });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Création ---------------------------------------------------------------
  app.post(opts.base, { preHandler: creation }, async (req, reply) => {
    const parsed = opts.createSchema.safeParse(req.body);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    const data = parsed.data as Record<string, unknown>;
    try {
      if (opts.validate) {
        const message = await opts.validate(db, req.session.churchId, data, req.session.userId);
        if (message) {
          return reply.code(400).send({ error: "invalid_reference", message });
        }
      }
      const cols = ["church_id", ...opts.columns];
      const placeholders = cols.map((_, i) => `$${i + 1}`).join(", ");
      const values: unknown[] = [
        req.session.churchId,
        ...opts.columns.map((c) => data[c] ?? null),
      ];
      const { rows } = await db.query(
        `INSERT INTO ${opts.table} (${cols.join(", ")})
         VALUES (${placeholders}) RETURNING *`,
        values,
      );
      await auditLog(db, {
        churchId: req.session.churchId,
        userId: req.session.userId,
        action: `${opts.audit}.cree`,
        details: { id: rows[0].id },
      });
      return reply.code(201).send(rows[0]);
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Mise à jour -------------------------------------------------------------
  app.patch(
    `${opts.base}/:id`,
    { preHandler: majSuppression },
    async (req, reply) => {
      const parsed = updateSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data as Record<string, unknown>;
      const keys = opts.columns.filter((c) => data[c] !== undefined);
      if (keys.length === 0) {
        return reply.code(400).send({ error: "invalid_input", message: "Rien à modifier." });
      }
      try {
        if (opts.validateUpdate) {
          const message = await opts.validateUpdate(
            db,
            req.session.churchId,
            (req.params as { id: string }).id,
            data,
          );
          if (message) {
            return reply.code(400).send({ error: "invalid_update", message });
          }
        }
        const sets = keys.map((c, i) => `${c} = $${i + 3}`).join(", ");
        const values: unknown[] = [
          (req.params as { id: string }).id,
          req.session.churchId,
          ...keys.map((c) => data[c]),
        ];
        const { rows } = await db.query(
          `UPDATE ${opts.table} SET ${sets} WHERE id = $1 AND church_id = $2 RETURNING *`,
          values,
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Élément introuvable." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: `${opts.audit}.modifie`,
          details: { id: rows[0].id },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Suppression -------------------------------------------------------------
  app.delete(
    `${opts.base}/:id`,
    { preHandler: majSuppression },
    async (req, reply) => {
      try {
        const id = (req.params as { id: string }).id;
        if (opts.beforeDelete) {
          const message = await opts.beforeDelete(db, req.session.churchId, id);
          if (message) {
            return reply.code(409).send({ error: "linked", message });
          }
        }
        const { rows } = await db.query(
          `DELETE FROM ${opts.table} WHERE id = $1 AND church_id = $2 RETURNING id`,
          [id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Élément introuvable." });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: `${opts.audit}.supprime`,
          details: { id: rows[0].id },
        });
        return reply.send({ ok: true, id: rows[0].id });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
