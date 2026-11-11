import type { FastifyInstance, FastifyReply } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import {
  auditLog,
  checkAuthToken,
  consumeAuthToken,
  createAuthToken,
  recordFailedAttempt,
  setPassword,
  verifyPassword,
} from "../auth.js";
import { inviteLink, mailEnabled, resetLink, sendMail } from "../mailer.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Modules 15-16 — mot de passe : oubli, réinitialisation, invitation,
 * initialisation, changement, et lien de réinitialisation généré par l'admin
 * (quand le SMTP n'est pas configuré).
 *
 * Sécurité : jetons 32 octets aléatoires, stockés hashés SHA-256, usage
 * unique, expiration (réinitialisation 24 h, invitation 7 jours) ; mots de
 * passe argon2id (8 caractères minimum) ; pas d'énumération d'e-mails sur
 * /mot-de-passe-oublie ; les tentatives sur les jetons comptent comme des
 * échecs (5 échecs → 15 min, comme le login) ; la réinitialisation et le
 * changement invalident toutes les sessions (token_version).
 */

const MAX_DEMANDES_HEURE = 5;
/** Limite 5 demandes / heure / e-mail (en mémoire ; instance unique MVP). */
const demandesParEmail = new Map<string, number[]>();

function limiteAtteinte(email: string): boolean {
  const now = Date.now();
  const key = email.toLowerCase();
  const passees = (demandesParEmail.get(key) ?? []).filter((t) => now - t < 3_600_000);
  if (passees.length >= MAX_DEMANDES_HEURE) {
    demandesParEmail.set(key, passees);
    return true;
  }
  passees.push(now);
  demandesParEmail.set(key, passees);
  return false;
}

const emailSchema = z.object({ email: z.string().email().max(254) });
const tokenPasswordSchema = z.object({
  token: z.string().min(16).max(256),
  mot_de_passe: z.string().min(8).max(256),
});
const inviterSchema = z.object({
  email: z.string().email().max(254),
  role: z.enum(["admin_eglise", "tresorier", "responsable_culte", "membre"]),
  member_id: z.string().uuid().optional(),
  full_name: z.string().min(2).max(200).optional(),
});
const changerSchema = z.object({
  ancien: z.string().min(1).max(256),
  nouveau: z.string().min(8).max(256),
});

/** Échec sur un jeton attribuable à un compte : compte l'échec (verrouillage éventuel). */
async function echecJeton(
  db: Pool,
  reply: FastifyReply,
  userId: string | undefined,
): Promise<boolean> {
  if (!userId) return false;
  const { rows } = await db.query<{ failed_logins: number }>(
    `SELECT failed_logins FROM users WHERE id = $1`,
    [userId],
  );
  if (rows.length === 0) return false;
  const verrouille = await recordFailedAttempt(db, { id: userId, failed_logins: rows[0].failed_logins });
  if (verrouille) {
    reply.code(423).send({
      error: "locked",
      message: "Compte verrouillé 15 minutes après 5 échecs.",
    });
    return true;
  }
  return false;
}

export function registerMotDePasseRoutes(app: FastifyInstance, db: Pool) {
  // -- Mot de passe oublié : toujours la même réponse, que l'e-mail existe ou non.
  app.post("/auth/mot-de-passe-oublie", async (req, reply) => {
    const parsed = emailSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "E-mail invalide.",
      });
    }
    const email = parsed.data.email.toLowerCase();
    if (limiteAtteinte(email)) {
      return reply.code(429).send({
        error: "too_many_requests",
        message: "Trop de demandes. Réessayez dans une heure.",
      });
    }
    const message =
      "Si cet e-mail correspond à un compte, un lien de réinitialisation a été envoyé.";
    try {
      const { rows } = await db.query<{ id: string }>(
        `SELECT id FROM users WHERE lower(email) = $1 LIMIT 1`,
        [email],
      );
      const user = rows[0];
      if (!user) return reply.send({ message, email_envoye: false });

      const { token } = await createAuthToken(db, user.id, "reinitialisation");
      let envoye = false;
      if (mailEnabled()) {
        envoye = await sendMail(
          email,
          "e-System Church — réinitialisation de votre mot de passe",
          `Bonjour,\n\nVous avez demandé la réinitialisation de votre mot de passe e-System Church.\n` +
            `Ouvrez ce lien (valable 24 h) : ${resetLink(token)}\n\n` +
            `Si vous n'avez rien demandé, ignorez cet e-mail.`,
        );
      }
      await auditLog(db, {
        churchId: null,
        userId: user.id,
        action: "auth.mot_de_passe_oublie",
        details: { email_envoye: envoye },
      });
      return reply.send({ message, email_envoye: envoye });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Réinitialisation par jeton (24 h, usage unique).
  app.post("/auth/reinitialiser-mot-de-passe", async (req, reply) => {
    const parsed = tokenPasswordSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Jeton ou mot de passe invalide (8 caractères minimum).",
      });
    }
    const { token, mot_de_passe } = parsed.data;
    try {
      const check = await checkAuthToken(db, token, "reinitialisation");
      if (!check.ok) {
        if (await echecJeton(db, reply, check.userId)) return;
        return reply.code(400).send({
          error: "invalid_token",
          message: "Lien invalide ou expiré.",
        });
      }
      await setPassword(db, check.userId, mot_de_passe);
      await consumeAuthToken(db, check.tokenId);
      await auditLog(db, {
        churchId: null,
        userId: check.userId,
        action: "auth.mot_de_passe_reinitialise",
        details: {},
      });
      return reply.send({
        message: "Mot de passe réinitialisé. Vous pouvez vous connecter.",
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Invitation par l'admin : crée le compte (sans mot de passe) et
  // renvoie le lien à l'admin, qui le transmet (WhatsApp, SMS, etc.).
  // Le jeton n'est exposé nulle part ailleurs.
  app.post(
    "/auth/inviter",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = inviterSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données d'invitation invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { email, role, member_id, full_name } = parsed.data;
      const client = await db.connect();
      try {
        await client.query("BEGIN");

        const existing = await client.query(`SELECT id FROM users WHERE lower(email) = $1`, [
          email.toLowerCase(),
        ]);
        if (existing.rowCount && existing.rowCount > 0) {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "email_taken",
            message: "Cet e-mail est déjà utilisé.",
          });
        }

        let member: { id: string; full_name: string; user_id: string | null } | null = null;
        if (member_id) {
          const { rows } = await client.query(
            `SELECT id, full_name, user_id FROM members
              WHERE id = $1 AND church_id = $2`,
            [member_id, req.session.churchId],
          );
          member = rows[0] ?? null;
          if (!member) {
            await client.query("ROLLBACK");
            return reply.code(404).send({
              error: "not_found",
              message: "Membre introuvable dans votre église.",
            });
          }
          if (role !== "membre") {
            await client.query("ROLLBACK");
            return reply.code(400).send({
              error: "invalid_input",
              message: "Un membre invité par sa fiche reçoit le rôle « membre ».",
            });
          }
          if (member.user_id) {
            await client.query("ROLLBACK");
            return reply.code(409).send({
              error: "already_linked",
              message: "Ce membre est déjà lié à un compte.",
            });
          }
        }

        const nom = full_name ?? member?.full_name ?? email.split("@")[0];
        const { rows: userRows } = await client.query<{ id: string }>(
          `INSERT INTO users (email, password_hash, full_name)
           VALUES ($1, NULL, $2) RETURNING id`,
          [email.toLowerCase(), nom],
        );
        const userId = userRows[0].id;

        await client.query(
          `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
          [userId, req.session.churchId, role],
        );
        if (member) {
          await client.query(`UPDATE users SET member_id = $2 WHERE id = $1`, [userId, member.id]);
          await client.query(`UPDATE members SET user_id = $2 WHERE id = $1`, [member.id, userId]);
        }

        const { token, expiresAt } = await createAuthToken(
          client,
          userId,
          "invitation",
        );
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "auth.invitation_creee",
          details: { invite_id: userId, role, member_id: member?.id ?? null },
        });
        await client.query("COMMIT");
        return reply.code(201).send({
          user: { id: userId, email: email.toLowerCase(), full_name: nom },
          lien_invitation: inviteLink(token),
          expires_at: expiresAt,
        });
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  // -- Initialisation du mot de passe par jeton d'invitation (7 jours, usage unique).
  app.post("/auth/initialiser-mot-de-passe", async (req, reply) => {
    const parsed = tokenPasswordSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Jeton ou mot de passe invalide (8 caractères minimum).",
      });
    }
    const { token, mot_de_passe } = parsed.data;
    try {
      const check = await checkAuthToken(db, token, "invitation");
      if (!check.ok) {
        if (await echecJeton(db, reply, check.userId)) return;
        return reply.code(400).send({
          error: "invalid_token",
          message: "Lien invalide ou expiré.",
        });
      }
      await setPassword(db, check.userId, mot_de_passe);
      await consumeAuthToken(db, check.tokenId);
      await auditLog(db, {
        churchId: null,
        userId: check.userId,
        action: "auth.mot_de_passe_initialise",
        details: {},
      });
      return reply.send({
        message: "Mot de passe initialisé. Vous pouvez vous connecter.",
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Changement de mot de passe (connecté) : vérifie l'ancien.
  app.post(
    "/auth/changer-mot-de-passe",
    { preHandler: [requireAuth(db)] },
    async (req, reply) => {
      const parsed = changerSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Mot de passe invalide (8 caractères minimum pour le nouveau).",
        });
      }
      const { ancien, nouveau } = parsed.data;
      try {
        const { rows } = await db.query<{ password_hash: string | null }>(
          `SELECT password_hash FROM users WHERE id = $1`,
          [req.session.userId],
        );
        const hash = rows[0]?.password_hash;
        if (!hash) {
          return reply.code(400).send({
            error: "password_not_set",
            message: "Initialisez votre mot de passe via le lien reçu.",
          });
        }
        if (!(await verifyPassword(hash, ancien))) {
          return reply.code(401).send({
            error: "invalid_credentials",
            message: "Mot de passe actuel incorrect.",
          });
        }
        await setPassword(db, req.session.userId, nouveau);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "auth.mot_de_passe_change",
          details: {},
        });
        return reply.send({
          message: "Mot de passe changé. Vos autres sessions ont été déconnectées.",
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Lien de réinitialisation généré par l'admin (sans SMTP) : l'admin
  // transmet le lien lui-même (WhatsApp, SMS, etc.). Admin seulement.
  app.post(
    "/auth/admin/lien-reinitialisation",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = emailSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "invalid_input", message: "E-mail invalide." });
      }
      try {
        const { rows } = await db.query<{ id: string }>(
          `SELECT id FROM users WHERE lower(email) = $1 LIMIT 1`,
          [parsed.data.email.toLowerCase()],
        );
        const user = rows[0];
        if (!user) {
          return reply.code(404).send({
            error: "not_found",
            message: "Utilisateur introuvable.",
          });
        }
        const { token, expiresAt } = await createAuthToken(
          db,
          user.id,
          "reinitialisation",
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "auth.lien_reinitialisation_genere",
          details: { cible_id: user.id },
        });
        return reply.send({ lien: resetLink(token), expires_at: expiresAt });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
