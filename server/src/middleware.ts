import type { FastifyReply, FastifyRequest } from "fastify";
import jwt from "jsonwebtoken";
import type { Pool } from "pg";
import { getJwtSecret } from "./auth.js";

/** Session d'église : l'utilisateur, l'église active et son rôle DANS cette église. */
export interface Session {
  userId: string;
  churchId: string;
  role: string;
}

declare module "fastify" {
  interface FastifyRequest {
    session: Session;
  }
}

export function bearerToken(req: FastifyRequest): string | null {
  const h = req.headers.authorization ?? "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}

/**
 * preHandler : exige un JWT valide ET une appartenance toujours existante
 * (le rôle est relu en base à chaque requête, donc frais).
 * En cas d'échec : 401 et la route ne s'exécute pas.
 */
export function requireAuth(db: Pool) {
  return async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const token = bearerToken(req);
    if (!token) {
      reply.code(401).send({ error: "unauthorized", message: "Jeton manquant." });
      return;
    }
    let payload: unknown;
    try {
      payload = jwt.verify(token, getJwtSecret());
    } catch {
      reply.code(401).send({ error: "unauthorized", message: "Jeton invalide ou expiré." });
      return;
    }
    const p = payload as { sub?: string; churchId?: string; role?: string };
    if (!p.sub || !p.churchId || !p.role) {
      reply.code(401).send({ error: "unauthorized", message: "Jeton incomplet." });
      return;
    }
    const { rows } = await db.query<{ role: string }>(
      `SELECT role FROM church_users WHERE user_id = $1 AND church_id = $2`,
      [p.sub, p.churchId],
    );
    if (rows.length === 0) {
      reply.code(401).send({ error: "unauthorized", message: "Appartenance à l'église introuvable." });
      return;
    }
    req.session = { userId: p.sub, churchId: p.churchId, role: rows[0].role };
  };
}

/**
 * preHandler : exige l'un des rôles donnés dans l'église de la session.
 * À placer APRÈS requireAuth(db) dans le tableau preHandler.
 */
export function requireRole(...roles: string[]) {
  return async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    if (!roles.includes(req.session.role)) {
      reply.code(403).send({
        error: "forbidden",
        message: `Action non autorisée pour le rôle « ${req.session.role} ».`,
      });
    }
  };
}

/** Erreurs PostgreSQL connues → réponses HTTP cohérentes. Relance sinon. */
export function dbError(reply: FastifyReply, e: unknown): void {
  const err = e as { code?: string; message?: string };
  if (err?.code === "23505") {
    reply.code(409).send({ error: "duplicate", message: "Doublon : cet élément existe déjà." });
    return;
  }
  if (err?.code === "23503") {
    reply.code(400).send({ error: "invalid_reference", message: "Référence invalide." });
    return;
  }
  if (err?.code === "23514") {
    reply.code(400).send({ error: "invalid_value", message: "Valeur refusée par une contrainte." });
    return;
  }
  throw e;
}
