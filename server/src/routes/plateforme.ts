import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog, createAuthToken } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { inviteLink } from "../mailer.js";

/**
 * Plateforme — super_admin seulement pour la gestion, chiffres ouverts
 * aux aides (tranche symbiose, 10 novembre 2026 ; accès spécial,
 * 13 novembre 2026).
 * GET /plateforme/chiffres — chiffres globaux seulement : nombre d'églises
 *   mères, nombre total de branches, membres actifs au total, contributions
 *   confirmées au total. Aucun détail nominatif, aucune liste de membres,
 *   aucune gestion des membres au jour le jour : la plateforme ne voit que
 *   les chiffres. Le rôle super_admin existe depuis la fondation, mais il
 *   était hors périmètre MVP ; cette route est son premier écran.
 * GET /plateforme/acces — accès Plateforme (super_admin seulement).
 * POST /plateforme/acces — ajouter une personne pour aider (super_admin
 *   seulement) : un aide reçoit ses propres identifiants (invitation si
 *   nouveau compte, sinon son mot de passe existant) et les droits limités
 *   choisis par Axel, révocables.
 * DELETE /plateforme/acces/:userId — révoquer un accès d'aide
 *   (super_admin seulement, jamais soi-même, jamais un super_admin).
 */

/** Droits Plateforme existants. Un seul aujourd'hui (« chiffres ») ; la
 *  liste s'allongera avec les capacités de la Plateforme. */
export const DROITS_PLATEFORME = ["chiffres"] as const;
export type DroitPlateforme = (typeof DROITS_PLATEFORME)[number];

export const LIBELLES_DROITS_PLATEFORME: Record<DroitPlateforme, string> = {
  chiffres: "Voir les chiffres globaux",
};

/** Droits effectifs d'un super_admin : tous. */
export const DROITS_SUPER_ADMIN: string[] = ["chiffres", "acces"];

/** preHandler : exige le droit Plateforme donné. Le super_admin a tous
 *  les droits ; un aide doit l'avoir dans sa ligne `acces_plateforme`. */
function exigerDroitPlateforme(db: Pool, droit: DroitPlateforme) {
  return async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    if (req.session.role === "super_admin") return;
    const { rows } = await db.query<{ droits: string[] }>(
      `SELECT droits FROM acces_plateforme WHERE user_id = $1`,
      [req.session.userId],
    );
    if (!(rows[0]?.droits ?? []).includes(droit)) {
      reply.code(403).send({
        error: "forbidden",
        message: "Votre accès Plateforme ne comprend pas ce droit.",
      });
    }
  };
}

const accesSchema = z.object({
  email: z.string().email().max(254),
  full_name: z.string().min(2).max(200).optional(),
  droits: z.array(z.enum(DROITS_PLATEFORME)).min(1),
});

export function registerPlateformeRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/plateforme/chiffres",
    {
      preHandler: [
        requireAuth(db),
        requireRole("super_admin", "aide_plateforme"),
        exigerDroitPlateforme(db, "chiffres"),
      ],
    },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT
             (SELECT count(*)::int FROM churches WHERE parent_church_id IS NULL) AS eglises_meres,
             (SELECT count(*)::int FROM churches WHERE parent_church_id IS NOT NULL) AS branches,
             (SELECT count(*)::int FROM churches) AS eglises_total,
             (SELECT count(*)::int FROM members WHERE status = 'actif') AS membres_actifs,
             (SELECT count(*)::int FROM contributions
               WHERE type IN ('dime','offrande','don') AND status = 'confirme') AS nombre_contributions,
             (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions
               WHERE type IN ('dime','offrande','don') AND status = 'confirme') AS total_contributions_fcfa,
             (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions
               WHERE type = 'depense' AND status = 'confirme') AS depenses_fcfa`,
        );
        const chiffres = rows[0];

        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "plateforme.chiffres_consultes",
          details: {},
        });

        return reply.send({ chiffres });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Accès Plateforme -----------------------------------------------------
  app.get(
    "/plateforme/acces",
    { preHandler: [requireAuth(db), requireRole("super_admin")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query<{
          user_id: string;
          full_name: string;
          email: string;
          role: string;
          droits: string[] | null;
          cree_le: Date | null;
        }>(
          `SELECT u.id AS user_id, u.full_name, u.email, cu.role,
                  ap.droits, ap.cree_le
             FROM church_users cu
             JOIN users u ON u.id = cu.user_id
             LEFT JOIN acces_plateforme ap ON ap.user_id = u.id
            WHERE cu.role IN ('super_admin', 'aide_plateforme')
            ORDER BY u.full_name`,
        );
        const parUtilisateur = new Map<string, (typeof rows)[number]>();
        for (const r of rows) {
          const precedent = parUtilisateur.get(r.user_id);
          if (!precedent || r.role === "super_admin") {
            parUtilisateur.set(r.user_id, r);
          }
        }
        return reply.send({
          acces: [...parUtilisateur.values()].map((r) => ({
            user_id: r.user_id,
            nom: r.full_name,
            email: r.email,
            role: r.role,
            droits:
              r.role === "super_admin" ? DROITS_SUPER_ADMIN : (r.droits ?? []),
            cree_le: r.cree_le,
          })),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.post(
    "/plateforme/acces",
    { preHandler: [requireAuth(db), requireRole("super_admin")] },
    async (req, reply) => {
      const parsed = accesSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données d'accès invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const email = parsed.data.email.toLowerCase();
      const droits = [...new Set(parsed.data.droits)];
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        const existant = await client.query<{ id: string; full_name: string }>(
          `SELECT id, full_name FROM users WHERE lower(email) = $1`,
          [email],
        );
        const dejaMembre = (existant.rowCount ?? 0) > 0;
        let userId: string;
        let nom: string;
        if (dejaMembre) {
          userId = existant.rows[0].id;
          nom = existant.rows[0].full_name;
          const acces = await client.query(
            `SELECT 1 FROM church_users
              WHERE user_id = $1 AND role IN ('super_admin', 'aide_plateforme')`,
            [userId],
          );
          if ((acces.rowCount ?? 0) > 0) {
            await client.query("ROLLBACK");
            return reply.code(409).send({
              error: "deja_acces_plateforme",
              message: "Cette personne a déjà un accès Plateforme.",
            });
          }
        } else {
          nom = parsed.data.full_name ?? email.split("@")[0];
          const insere = await client.query<{ id: string }>(
            `INSERT INTO users (email, password_hash, full_name)
             VALUES ($1, NULL, $2) RETURNING id`,
            [email, nom],
          );
          userId = insere.rows[0].id;
        }
        // Ancre de l'accès : l'église active du super_admin si
        // l'utilisateur n'y a pas déjà un rôle (une seule ligne par
        // (utilisateur, église)), sinon la plus ancienne église sans
        // ligne pour lui. L'ancre ne sert qu'à porter le rôle et le
        // jeton : l'aide ne voit jamais le contenu d'une église.
        const ancre = await client.query<{ id: string }>(
          `SELECT c.id FROM churches c
            WHERE NOT EXISTS (
              SELECT 1 FROM church_users cu
              WHERE cu.user_id = $1 AND cu.church_id = c.id
            )
            ORDER BY (c.id = $2) DESC, c.created_at ASC LIMIT 1`,
          [userId, req.session.churchId],
        );
        if ((ancre.rowCount ?? 0) === 0) {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "aucune_eglise_libre",
            message:
              "Cette personne a déjà un rôle dans chaque église : impossible de lui attacher un accès Plateforme.",
          });
        }
        await client.query(
          `INSERT INTO church_users (user_id, church_id, role)
           VALUES ($1, $2, 'aide_plateforme')`,
          [userId, ancre.rows[0].id],
        );
        await client.query(
          `INSERT INTO acces_plateforme (user_id, droits, cree_par)
           VALUES ($1, $2, $3)`,
          [userId, droits, req.session.userId],
        );
        let lienInvitation: string | undefined;
        let expiresAt: Date | undefined;
        if (!dejaMembre) {
          const jeton = await createAuthToken(client, userId, "invitation");
          lienInvitation = inviteLink(jeton.token);
          expiresAt = jeton.expiresAt;
        }
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "plateforme.acces_cree",
          details: {
            invite_id: userId,
            email,
            droits,
            deja_membre: dejaMembre,
          },
        });
        await client.query("COMMIT");
        return reply.code(201).send({
          user: { id: userId, email, full_name: nom },
          deja_membre: dejaMembre,
          ...(lienInvitation
            ? { lien_invitation: lienInvitation, expires_at: expiresAt }
            : {}),
        });
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  app.delete(
    "/plateforme/acces/:userId",
    { preHandler: [requireAuth(db), requireRole("super_admin")] },
    async (req, reply) => {
      const userId = (req.params as { userId: string }).userId;
      if (userId === req.session.userId) {
        return reply.code(409).send({
          error: "invalid_input",
          message: "Vous ne pouvez pas révoquer votre propre accès.",
        });
      }
      try {
        const { rows } = await db.query<{ role: string; church_id: string }>(
          `SELECT role, church_id FROM church_users
            WHERE user_id = $1 AND role IN ('super_admin', 'aide_plateforme')`,
          [userId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({
            error: "not_found",
            message: "Cette personne n'a pas d'accès Plateforme.",
          });
        }
        if (rows.some((r) => r.role === "super_admin")) {
          return reply.code(403).send({
            error: "forbidden",
            message:
              "On ne révoque pas l'accès d'un admin de la plateforme par cette route.",
          });
        }
        const egliseIds = [...new Set(rows.map((r) => r.church_id))];
        const client = await db.connect();
        try {
          await client.query("BEGIN");
          await client.query(
            `DELETE FROM refresh_tokens WHERE user_id = $1 AND church_id = ANY($2)`,
            [userId, egliseIds],
          );
          await client.query(
            `DELETE FROM church_users WHERE user_id = $1 AND role = 'aide_plateforme'`,
            [userId],
          );
          await client.query(`DELETE FROM acces_plateforme WHERE user_id = $1`, [
            userId,
          ]);
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "plateforme.acces_revoque",
            details: { invite_id: userId },
          });
          await client.query("COMMIT");
        } catch (e) {
          await client.query("ROLLBACK").catch(() => undefined);
          throw e;
        } finally {
          client.release();
        }
        return reply.send({ ok: true });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
