import type { FastifyInstance, FastifyReply } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth, requireRole, type Session } from "../middleware.js";
import { MODULES_ACTIVABLES } from "../modules.js";

/**
 * Rattachements : une église demande à rejoindre une mère ; la mère accepte
 * ou refuse. L'acceptation pose parent_church_id sur l'église demanderesse.
 * POST /rattachements            — demander à rejoindre une mère (par code ou id).
 * GET  /rattachements            — demandes reçues (je suis la mère) et émises.
 * POST /rattachements/:id/accepter — décision de la mère (admin de la mère).
 * POST /rattachements/:id/refuser  — décision de la mère (admin de la mère).
 *
 * Code de tutelle à usage unique (migration 009) : la demande peut porter
 * `code_tutelle` (ESC-T-XXXXXX) au lieu du code permanent de la mère.
 * À l'acceptation, le code passe à `utilise`, automatiquement, et tous les
 * modules de l'église rattachée sont activés automatiquement (exception à
 * la règle US1 « la mère ne force pas ses antennes », décidée par Axel
 * le 11/11/2026 : une église sous tutelle a tous ses modules actifs).
 * Un deuxième usage du même code est refusé (400 `code_tutelle_invalide`).
 * Un refus laisse le code `actif`.
 */

/** Active tous les modules activables pour une église (tutelle). */
export async function activerTousModules(
  client: PoolClient,
  churchId: string,
): Promise<string[]> {
  const codes = MODULES_ACTIVABLES.map((m) => m.code);
  for (const code of codes) {
    await client.query(
      `INSERT INTO eglise_modules (church_id, module, actif)
       VALUES ($1, $2, true)
       ON CONFLICT (church_id, module)
       DO UPDATE SET actif = true, updated_at = now()`,
      [churchId, code],
    );
  }
  return codes;
}

const createSchema = z
  .object({
    parent_code: z.string().min(4).max(20).optional(),
    parent_church_id: z.string().uuid().optional(),
    code_tutelle: z.string().min(4).max(20).optional(),
  })
  .refine((d) => d.parent_code ?? d.parent_church_id ?? d.code_tutelle, {
    message: "parent_code, parent_church_id ou code_tutelle est requis.",
  });

/**
 * Vrai si rattacher `childId` sous `parentId` créerait un cycle
 * (le parent est la même église ou l'un de ses descendants).
 */
async function wouldCreateCycle(client: Pool | PoolClient, childId: string, parentId: string): Promise<boolean> {
  if (childId === parentId) return true;
  const { rows } = await client.query(
    `WITH RECURSIVE descendants AS (
       SELECT id FROM churches WHERE id = $1
       UNION ALL
       SELECT c.id FROM churches c JOIN descendants d ON c.parent_church_id = d.id
     )
     SELECT 1 FROM descendants WHERE id = $2`,
    [childId, parentId],
  );
  return (rows.length ?? 0) > 0;
}

export function registerRattachementsRoutes(app: FastifyInstance, db: Pool) {
  app.post(
    "/rattachements",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = createSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Demande de rattachement invalide.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        // Résout la mère : par code de tutelle à usage unique, par code
        // permanent, ou par id.
        let parent: { id: string; name: string } | undefined;
        let codeTutelleId: string | null = null;
        if (parsed.data.code_tutelle) {
          const { rows: codes } = await db.query<{
            id: string;
            church_id: string;
            status: string;
          }>(
            `SELECT id, church_id, status FROM codes_tutelle WHERE code = $1`,
            [parsed.data.code_tutelle],
          );
          const code = codes[0];
          if (!code) {
            return reply.code(400).send({
              error: "code_tutelle_invalide",
              message: "Ce code de tutelle est inconnu.",
            });
          }
          if (code.status === "utilise") {
            return reply.code(400).send({
              error: "code_tutelle_invalide",
              message: "Ce code de tutelle a déjà été utilisé, il n'est plus valide.",
            });
          }
          if (code.status === "annule") {
            return reply.code(400).send({
              error: "code_tutelle_invalide",
              message: "Ce code de tutelle a été annulé.",
            });
          }
          codeTutelleId = code.id;
          const { rows: parents } = await db.query<{ id: string; name: string }>(
            `SELECT id, name FROM churches WHERE id = $1 AND status = 'active'`,
            [code.church_id],
          );
          parent = parents[0];
          if (!parent) {
            return reply.code(400).send({
              error: "invalid_parent",
              message: "Église mère introuvable ou inactive.",
            });
          }
          const enAttente = await db.query(
            `SELECT id FROM rattachements
              WHERE code_tutelle_id = $1 AND status = 'en_attente'`,
            [codeTutelleId],
          );
          if (enAttente.rowCount && enAttente.rowCount > 0) {
            return reply.code(409).send({
              error: "duplicate",
              message: "Ce code est déjà utilisé par une demande en attente.",
            });
          }
        } else {
          const { rows: parents } = parsed.data.parent_church_id
            ? await db.query<{ id: string; name: string }>(
                `SELECT id, name FROM churches WHERE id = $1 AND status = 'active'`,
                [parsed.data.parent_church_id],
              )
            : await db.query<{ id: string; name: string }>(
                `SELECT id, name FROM churches WHERE code = $1 AND status = 'active'`,
                [parsed.data.parent_code],
              );
          parent = parents[0];
        }
        if (!parent) {
          return reply.code(400).send({
            error: "invalid_parent",
            message: "Église mère introuvable ou inactive.",
          });
        }
        if (parent.id === req.session.churchId) {
          return reply.code(400).send({
            error: "invalid_parent",
            message: "Une église ne peut pas se rattacher à elle-même.",
          });
        }
        if (await wouldCreateCycle(db, req.session.churchId, parent.id)) {
          return reply.code(400).send({
            error: "cycle",
            message: "Rattachement impossible : cette église est déjà dans votre descendance.",
          });
        }
        const existing = await db.query(
          `SELECT id, status FROM rattachements
            WHERE church_id = $1 AND parent_church_id = $2 AND status = 'en_attente'`,
          [req.session.churchId, parent.id],
        );
        if (existing.rowCount && existing.rowCount > 0) {
          return reply.code(409).send({
            error: "duplicate",
            message: "Une demande est déjà en attente vers cette église mère.",
          });
        }

        const { rows } = await db.query(
          `INSERT INTO rattachements (church_id, parent_church_id, status, code_tutelle_id)
           VALUES ($1, $2, 'en_attente', $3) RETURNING id, church_id, parent_church_id, status, created_at`,
          [req.session.churchId, parent.id, codeTutelleId],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "rattachement.demande",
          details: { parent_church_id: parent.id, parent_nom: parent.name },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/rattachements",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        // Demandes reçues : mon église est la mère sollicitée.
        const { rows: recues } = await db.query(
          `SELECT r.id, r.status, r.created_at,
                  c.id AS eglise_id, c.code AS eglise_code, c.name AS eglise_nom, c.city AS eglise_ville
             FROM rattachements r
             JOIN churches c ON c.id = r.church_id
            WHERE r.parent_church_id = $1
            ORDER BY r.created_at DESC`,
          [req.session.churchId],
        );
        // Demandes émises : mon église demande à rejoindre une mère.
        const { rows: emises } = await db.query(
          `SELECT r.id, r.status, r.created_at,
                  c.id AS eglise_id, c.code AS eglise_code, c.name AS eglise_nom, c.city AS eglise_ville
             FROM rattachements r
             JOIN churches c ON c.id = r.parent_church_id
            WHERE r.church_id = $1
            ORDER BY r.created_at DESC`,
          [req.session.churchId],
        );
        return reply.send({ recues, emises });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // Décision de la mère : accepter ou refuser. Factorisée (même garde, même flux).
  async function decider(
    rattachementId: string,
    session: Session,
    reply: FastifyReply,
    accepter: boolean,
  ): Promise<void> {
    // UUID invalide : 400, pas 500 (la requête SQL `WHERE id = $1` rejette
    // la valeur et `dbError` la relaie en erreur serveur).
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        rattachementId,
      )
    ) {
      reply.code(400).send({
        error: "invalid_id",
        message: "Demande introuvable.",
      });
      return;
    }
    try {
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        const { rows } = await client.query(
          `SELECT id, church_id, parent_church_id, status, code_tutelle_id
             FROM rattachements WHERE id = $1 FOR UPDATE`,
          [rattachementId],
        );
        const r = rows[0];
        if (!r) {
          await client.query("ROLLBACK");
          reply.code(404).send({ error: "not_found", message: "Demande introuvable." });
          return;
        }
        if (r.parent_church_id !== session.churchId) {
          await client.query("ROLLBACK");
          reply.code(403).send({
            error: "forbidden",
            message: "Seule l'église mère sollicitée peut décider.",
          });
          return;
        }
        if (r.status !== "en_attente") {
          await client.query("ROLLBACK");
          reply.code(409).send({
            error: "conflict",
            message: `Cette demande a déjà été ${r.status === "acceptee" ? "acceptée" : "refusée"}.`,
          });
          return;
        }
        if (accepter && (await wouldCreateCycle(client, r.church_id as string, r.parent_church_id as string))) {
          await client.query("ROLLBACK");
          reply.code(400).send({
            error: "cycle",
            message: "Acceptation impossible : cela créerait un cycle dans l'arborescence.",
          });
          return;
        }

        const status = accepter ? "acceptee" : "refusee";
        await client.query(
          `UPDATE rattachements
              SET status = $2, decided_by = $3, decided_at = now()
            WHERE id = $1`,
          [r.id, status, session.userId],
        );
        if (accepter) {
          await client.query(
            `UPDATE churches SET parent_church_id = $2, updated_at = now() WHERE id = $1`,
            [r.church_id, r.parent_church_id],
          );
          // Tutelle : tous les modules de l'église rattachée sont activés
          // automatiquement, sans action de son admin.
          const modulesActives = await activerTousModules(client, r.church_id as string);
          await auditLog(client, {
            churchId: r.church_id as string,
            userId: session.userId,
            action: "modules.actives_tutelle",
            details: { par_mere: r.parent_church_id, modules: modulesActives },
          });
          // Code de tutelle à usage unique : il n'est plus valide, tout
          // de suite, sans action manuelle. Si un autre accept a déjà
          // consommé le code entre-temps, on annule tout (409).
          if (r.code_tutelle_id) {
            const used = await client.query(
              `UPDATE codes_tutelle
                  SET status = 'utilise', used_by = $2, used_at = now()
                WHERE id = $1 AND status = 'actif'`,
              [r.code_tutelle_id, r.church_id],
            );
            if ((used.rowCount ?? 0) === 0) {
              await client.query("ROLLBACK");
              reply.code(409).send({
                error: "code_tutelle_invalide",
                message: "Ce code de tutelle a déjà été utilisé, il n'est plus valide.",
              });
              return;
            }
            await auditLog(client, {
              churchId: session.churchId,
              userId: session.userId,
              action: "codes_tutelle.utilise",
              details: { code_tutelle_id: r.code_tutelle_id, eglise_id: r.church_id },
            });
          }
        }
        await auditLog(client, {
          churchId: session.churchId,
          userId: session.userId,
          action: accepter ? "rattachement.accepte" : "rattachement.refuse",
          details: { rattachement_id: r.id, eglise_id: r.church_id },
        });
        await client.query("COMMIT");
        reply.send({ id: r.id, status });
        return;
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        throw e;
      } finally {
        client.release();
      }
    } catch (e) {
      dbError(reply, e);
    }
  }

  app.post(
    "/rattachements/:id/accepter",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) =>
      decider((req.params as { id: string }).id, req.session, reply, true),
  );

  app.post(
    "/rattachements/:id/refuser",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) =>
      decider((req.params as { id: string }).id, req.session, reply, false),
  );
}
