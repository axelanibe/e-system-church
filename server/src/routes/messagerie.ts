import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { dbError, requireAuth } from "../middleware.js";
import { notifierNouveauMessage } from "../fcm.js";

/**
 * Tranche T-Msg-0 — Messagerie et Signalement : conversations et
 * messages texte (types image et file en T-Msg-5, signalement en
 * T-Msg-4). Isolation applicative par church_id et par participation :
 * une conversation n'est visible que par ses participants actifs, et
 * un utilisateur d'une autre église ne voit rien (404, sans révéler
 * l'existence). Le super administrateur et l'aide Plateforme n'ont
 * aucun accès au contenu des messages (spécification, section 4.3).
 */

const uuid = z.string().uuid();

const ROLES_MESSAGERIE = ["admin_eglise", "tresorier", "responsable_culte", "membre"];

const TYPES_CONVERSATION = [
  "directe",
  "groupe_departement",
  "groupe_eglise",
  "pastorale",
  "moderation",
] as const;

const creerConversationSchema = z.object({
  type: z.enum(TYPES_CONVERSATION),
  title: z.string().max(200).optional(),
  participant_member_ids: z.array(uuid).min(1),
});

const envoyerMessageSchema = z.object({
  content: z.string().min(1).max(5000),
  type: z.literal("text").optional().default("text"),
});

/** Fiche membre liée au compte de l'appelant, ou null. */
export async function ficheMembre(
  db: Pool | PoolClient,
  userId: string,
): Promise<string | null> {
  const { rows } = await db.query<{ member_id: string | null }>(
    `SELECT member_id FROM users WHERE id = $1`,
    [userId],
  );
  return rows[0]?.member_id ?? null;
}

/** Vrai si la fiche membre est participante active de la conversation. */
async function estParticipantActif(
  db: Pool | PoolClient,
  churchId: string,
  conversationId: string,
  memberId: string,
): Promise<boolean> {
  const { rows } = await db.query(
    `SELECT 1 FROM conversation_participants cp
      JOIN conversations c ON c.id = cp.conversation_id
     WHERE cp.conversation_id = $1 AND c.church_id = $2
       AND cp.member_id = $3 AND cp.is_active = true`,
    [conversationId, churchId, memberId],
  );
  return rows.length > 0;
}

/**
 * Garde de rôle propre à la messagerie : le super administrateur n'a
 * aucun accès au contenu des messages, l'aide Plateforme n'a que les
 * chiffres. Tous les autres rôles de l'église peuvent utiliser la
 * messagerie. Partagée avec les jetons push (même périmètre).
 */
export async function gardeMessagerie(
  req: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  if (req.session.role === "super_admin") {
    reply.code(403).send({
      error: "forbidden",
      message: "Le super administrateur n'a aucun accès au contenu des messages.",
    });
    return;
  }
  if (req.session.role === "aide_plateforme") {
    reply.code(403).send({
      error: "forbidden",
      message: "L'aide Plateforme n'a accès qu'aux chiffres, pas au contenu des messages.",
    });
    return;
  }
  if (!ROLES_MESSAGERIE.includes(req.session.role)) {
    reply.code(403).send({
      error: "forbidden",
      message: `Action non autorisée pour le rôle « ${req.session.role} ».`,
    });
  }
}

export function registerMessagerieRoutes(app: FastifyInstance, db: Pool) {
  const auth = requireAuth(db);

  // -- POST /messagerie/conversations : créer une conversation.
  app.post(
    "/messagerie/conversations",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const parsed = creerConversationSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Corps invalide : type, titre (200 caractères maximum) et au moins un participant.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const churchId = req.session.churchId;
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) {
          return reply.code(403).send({
            error: "forbidden",
            message:
              "Votre compte n'est pas lié à une fiche membre : impossible de participer à la messagerie.",
          });
        }
        // La fiche membre du créateur doit appartenir à l'église de la session.
        const { rows: createurRows } = await db.query<{ church_id: string }>(
          `SELECT church_id FROM members WHERE id = $1`,
          [memberId],
        );
        if (createurRows.length === 0 || createurRows[0].church_id !== churchId) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Votre fiche membre n'appartient pas à cette église.",
          });
        }
        // Participants uniques, créateur ajouté s'il n'est pas dans la liste.
        const participantIds = [...new Set(parsed.data.participant_member_ids)];
        if (!participantIds.includes(memberId)) participantIds.push(memberId);
        if (parsed.data.type === "directe" && participantIds.length !== 2) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Une conversation directe compte exactement 2 participants.",
          });
        }
        // Tous les participants doivent être des membres de l'église.
        const { rows: membresRows } = await db.query<{ id: string }>(
          `SELECT id FROM members WHERE church_id = $1 AND id = ANY($2)`,
          [churchId, participantIds],
        );
        if (membresRows.length !== participantIds.length) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Tous les participants doivent être des membres de votre église.",
          });
        }

        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows } = await client.query(
            `INSERT INTO conversations (church_id, type, title, created_by)
             VALUES ($1, $2, $3, $4)
             RETURNING id, type, title, created_at`,
            [churchId, parsed.data.type, parsed.data.title ?? null, memberId],
          );
          const conversation = rows[0];
          for (const pid of participantIds) {
            await client.query(
              `INSERT INTO conversation_participants
                 (conversation_id, church_id, member_id, role)
               VALUES ($1, $2, $3, 'membre')`,
              [conversation.id, churchId, pid],
            );
          }
          await client.query("COMMIT");
          return reply.code(201).send(conversation);
        } catch (e) {
          await client.query("ROLLBACK").catch(() => undefined);
          throw e;
        } finally {
          client.release();
        }
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- GET /messagerie/conversations : conversations de l'appelant.
  app.get(
    "/messagerie/conversations",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) return reply.send([]);
        const { rows } = await db.query(
          `SELECT c.id, c.type, c.title, c.created_at, c.last_message_at
             FROM conversations c
             JOIN conversation_participants cp ON cp.conversation_id = c.id
            WHERE c.church_id = $1 AND cp.member_id = $2 AND cp.is_active = true
            ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC`,
          [req.session.churchId, memberId],
        );
        return reply.send(rows);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- GET /messagerie/conversations/:id : une conversation.
  app.get(
    "/messagerie/conversations/:id",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
      }
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) {
          return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
        }
        if (!(await estParticipantActif(db, req.session.churchId, id, memberId))) {
          return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
        }
        const { rows } = await db.query(
          `SELECT id, type, title, created_at, last_message_at
             FROM conversations WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- POST /messagerie/conversations/:id/messages : envoyer un message texte.
  app.post(
    "/messagerie/conversations/:id/messages",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
      }
      const parsed = envoyerMessageSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Message invalide : contenu de 1 à 5000 caractères, type texte uniquement.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) {
          return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
        }
        if (!(await estParticipantActif(db, req.session.churchId, id, memberId))) {
          return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
        }
        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows } = await client.query(
            `INSERT INTO messages (conversation_id, church_id, sender_id, content, type)
             VALUES ($1, $2, $3, $4, 'text')
             RETURNING id, conversation_id, sender_id, content, type, created_at`,
            [id, req.session.churchId, memberId, parsed.data.content],
          );
          await client.query(
            `UPDATE conversations SET last_message_at = NOW() WHERE id = $1`,
            [id],
          );
          await client.query("COMMIT");
          // Notification push FCM aux autres participants : envoi
          // déclenché après le COMMIT, jamais bloquant. Une panne FCM
          // (compte de service absent, jeton invalide) ne doit jamais
          // faire échouer la création du message, déjà validée ici.
          try {
            const { rows: convRows } = await db.query<{ title: string | null }>(
              `SELECT title FROM conversations WHERE id = $1`,
              [id],
            );
            void notifierNouveauMessage(db, {
              churchId: req.session.churchId,
              conversationId: id,
              expediteurMemberId: memberId,
              titre: convRows[0]?.title ?? "Nouveau message",
              contenu: parsed.data.content,
            }).catch(() => undefined);
          } catch {
            // Notification seule : le message est créé, on continue.
          }
          return reply.code(201).send(rows[0]);
        } catch (e) {
          await client.query("ROLLBACK").catch(() => undefined);
          throw e;
        } finally {
          client.release();
        }
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- GET /messagerie/conversations/:id/messages : messages d'une conversation.
  app.get(
    "/messagerie/conversations/:id/messages",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
      }
      const query = req.query as { limit?: string; offset?: string };
      const limit = Math.min(Math.max(Number.parseInt(query.limit ?? "50", 10) || 50, 1), 100);
      const offset = Math.max(Number.parseInt(query.offset ?? "0", 10) || 0, 0);
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) {
          return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
        }
        if (!(await estParticipantActif(db, req.session.churchId, id, memberId))) {
          return reply.code(404).send({ error: "not_found", message: "Conversation introuvable." });
        }
        const { rows } = await db.query(
          `SELECT id, conversation_id, sender_id, content, type, created_at, edited_at
             FROM messages
            WHERE conversation_id = $1 AND church_id = $2 AND deleted_at IS NULL
            ORDER BY created_at ASC
            LIMIT $3 OFFSET $4`,
          [id, req.session.churchId, limit, offset],
        );
        return reply.send(rows);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
