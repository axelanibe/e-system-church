import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { randomBytes } from "node:crypto";
import { auditLog } from "../auth.js";
import { dbError, estAnnexe, requireAuth, requireRole } from "../middleware.js";

/**
 * Codes de tutelle à usage unique (migration 009).
 *
 * Une église mère génère un code `ESC-T-XXXXXX` et le donne à une église
 * qui veut se rattacher à elle. Le code ne sert qu'une fois : à
 * l'acceptation du rattachement il passe à `utilise`, automatiquement.
 * Un deuxième usage est refusé par POST /rattachements (400
 * `code_tutelle_invalide`), et journalisé.
 *
 * Le code permanent ESC-… de l'église mère n'est pas touché : il sert
 * toujours à l'inscription des membres et aux demandes par `parent_code`.
 *
 * Règle du 11/11/2026 : seule une église mère génère un code de tutelle,
 * une annexe ne peut pas avoir d'annexe (403 `annexe_sans_annexe`).
 *
 * POST /codes-tutelle            — générer un code (admin_eglise, mère seulement).
 * GET  /codes-tutelle            — mes codes, avec leur statut.
 * POST /codes-tutelle/:id/annuler — annuler un code encore actif.
 */

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function generateTutelleCode(): string {
  let suffix = "";
  for (let i = 0; i < 6; i++) suffix += CODE_ALPHABET[randomBytes(1)[0] % CODE_ALPHABET.length];
  return `ESC-T-${suffix}`;
}

export function registerCodesTutelleRoutes(app: FastifyInstance, db: Pool) {
  app.post(
    "/codes-tutelle",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      // Seule une église mère génère un code de tutelle.
      if (await estAnnexe(db, req.session.churchId)) {
        return reply.code(403).send({
          error: "annexe_sans_annexe",
          message: "Une église annexe ne peut pas avoir d'église annexe.",
        });
      }
      try {
        let code = "";
        for (let attempt = 0; attempt < 5; attempt++) {
          code = generateTutelleCode();
          const clash = await db.query(`SELECT 1 FROM codes_tutelle WHERE code = $1`, [code]);
          if (clash.rowCount === 0) break;
          if (attempt === 4) throw new Error("Impossible de générer un code de tutelle unique.");
        }
        const { rows } = await db.query(
          `INSERT INTO codes_tutelle (church_id, code, created_by)
           VALUES ($1, $2, $3)
           RETURNING id, church_id, code, status, created_at`,
          [req.session.churchId, code, req.session.userId],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "codes_tutelle.cree",
          details: { code },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/codes-tutelle",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT ct.id, ct.code, ct.status, ct.used_at, ct.created_at,
                  c.name AS utilisee_par_nom, c.code AS utilisee_par_code
             FROM codes_tutelle ct
             LEFT JOIN churches c ON c.id = ct.used_by
            WHERE ct.church_id = $1
            ORDER BY ct.created_at DESC`,
          [req.session.churchId],
        );
        return reply.send({ codes: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/codes-tutelle/:id/annuler",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, church_id, code, status FROM codes_tutelle WHERE id = $1`,
          [(req.params as { id: string }).id],
        );
        const code = rows[0];
        if (!code || code.church_id !== req.session.churchId) {
          return reply.code(404).send({ error: "not_found", message: "Code de tutelle introuvable." });
        }
        if (code.status !== "actif") {
          return reply.code(409).send({
            error: "conflict",
            message: `Ce code est déjà ${code.status === "utilise" ? "utilisé" : "annulé"}.`,
          });
        }
        await db.query(`UPDATE codes_tutelle SET status = 'annule' WHERE id = $1`, [code.id]);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "codes_tutelle.annule",
          details: { code: code.code },
        });
        return reply.send({ id: code.id, code: code.code, status: "annule" });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
