import { createHash } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { dbError, requireAuth } from "../middleware.js";
import { estParticipantActif, ficheMembre } from "../messagerie_commun.js";
import { gardeMessagerie } from "./messagerie.js";

/**
 * Tranche T-Msg-4 — Signalement / modération / recours, sur le schéma
 * de la migration 034 (tables reports, moderation_actions, appeals).
 *
 * Modèle adapté de Connexion Prophétique (10 motifs, escalade,
 * recours 15/30 jours) à e-System Church :
 * - isolation par church_id (une église ne voit jamais les
 *   signalements d'une autre, 404 sans révéler l'existence) ;
 * - escalade vers l'église mère (churches.parent_church_id) ou vers
 *   le référent protection de l'enfance (hors circuit, sans
 *   destinataire désigné en base pour l'instant) ;
 * - modération par l'administrateur de l'église seulement : il n'y a
 *   pas de rôle « modérateur » dans user_role, et l'église mère ne
 *   voit un signalement transmis qu'en lecture seule (politique
 *   escalade_mere de la migration 034, appliquée ici au niveau
 *   applicatif) ;
 * - reporter_id, moderator_id, appellant_id et reviewer_id sont des
 *   identifiants d'utilisateur (users.id), comme dans les autres
 *   routes d'audit ; l'identité du rapporteur n'est jamais montrée
 *   à la personne signalée (ni dans la liste, ni dans mes-sanctions).
 *
 * Motifs : l'enum de la migration 034 en compte 7 (les 3 motifs
 * propres à Connexion Prophétique — erreur doctrinale, trafic
 * d'influence, mauvaise gestion des finances — n'y figurent pas ;
 * les ajouter exigerait une migration qui élargit le CHECK de
 * reports.reason, tranche à part).
 */

const uuid = z.string().uuid();

/** Motifs de signalement, enum de reports.reason (migration 034). */
const MOTIFS_SIGNALEMENT = [
  "harassment",
  "hate_speech",
  "threat",
  "misinformation",
  "spam",
  "child_safety",
  "other",
] as const;

/** Statuts d'un signalement, enum de reports.status (migration 034). */
const STATUTS_SIGNALEMENT = [
  "pending",
  "in_review",
  "resolved",
  "dismissed",
  "escalated",
  "appealed",
] as const;

/** Actions de modération (table moderation_actions, texte libre). */
const ACTIONS_MODERATION = ["rejeter", "avertir", "sourdine", "suspendre"] as const;

/** Durées de sourdine / suspension proposées, en heures. */
const DUREES_MODERATION_HEURES = [24, 168, 720] as const;

/** Délai pour contester une sanction : 15 jours. */
const DELAI_RECOURS_JOURS = 15;

/** Délai pour répondre à un recours : 30 jours. */
const DELAI_REPONSE_RECOURS_JOURS = 30;

/** Un signalement déjà traité ne peut plus recevoir d'action. */
const STATUTS_FERMES = ["resolved", "dismissed", "escalated", "appealed"] as const;

const signalerSchema = z.object({
  target_type: z.enum(["message", "conversation"]),
  target_id: uuid,
  reason: z.enum(MOTIFS_SIGNALEMENT),
  description: z.string().max(500).optional(),
  // Destinataire choisi par le rapporteur ; la sécurité d'un enfant
  // force le routage vers le référent, quel que soit ce choix.
  routed_to: z.enum(["local", "mother"]).optional().default("local"),
});

const actionModerationSchema = z.object({
  action: z.enum(ACTIONS_MODERATION),
  // Note motivée exigée : moderation_actions.notes est NOT NULL.
  notes: z.string().min(1).max(1000),
  duree_heures: z
    .number()
    .int()
    .refine((d) => (DUREES_MODERATION_HEURES as readonly number[]).includes(d))
    .optional(),
});

const escaladeSchema = z.object({
  destination: z.enum(["mother", "child_safety_referent"]),
});

const recoursSchema = z.object({
  reason: z.string().max(500).optional(),
  moderation_action_id: uuid.optional(),
});

const traiterRecoursSchema = z.object({
  statut: z.enum(["resolved", "dismissed"]),
});

type LigneSignalement = {
  id: string;
  church_id: string;
  reporter_id: string;
  target_type: string;
  target_id: string;
  reason: string;
  description: string | null;
  evidence_snapshot: Record<string, unknown> | null;
  evidence_hash: string | null;
  routed_to: string;
  routed_to_church_id: string | null;
  status: string;
  created_at: string;
  resolved_at: string | null;
  resolution_notes: string | null;
  reporter_nom?: string | null;
};

/**
 * Portée de visibilité d'un signalement pour l'église de l'appelant :
 * « local » (son église, accès complet) ou « mere » (signalement
 * transmis par une église fille, lecture seule), null si invisible.
 */
function porteeSignalement(
  signalement: { church_id: string; routed_to: string; routed_to_church_id: string | null },
  churchId: string,
): "local" | "mere" | null {
  if (signalement.church_id === churchId) return "local";
  if (
    signalement.routed_to === "mother" &&
    signalement.routed_to_church_id === churchId
  ) {
    return "mere";
  }
  return null;
}

/**
 * Champs visibles par l'église mère sur un signalement transmis :
 * la politique escalade_mere de la migration 034 ne retient que
 * evidence_snapshot, reason, description, status et created_at
 * (plus l'identifiant et le routage, pour l'affichage).
 */
function projeterPourMere(r: LigneSignalement): Record<string, unknown> {
  return {
    id: r.id,
    reason: r.reason,
    description: r.description,
    status: r.status,
    created_at: r.created_at,
    evidence_snapshot: r.evidence_snapshot,
    routed_to: r.routed_to,
    routed_to_church_id: r.routed_to_church_id,
    resolved_at: r.resolved_at,
    escalade: true,
  };
}

/** Garde modération : l'administrateur de l'église seulement. */
function gardeModerateur(req: FastifyRequest, reply: FastifyReply): boolean {
  if (req.session.role !== "admin_eglise") {
    reply.code(403).send({
      error: "forbidden",
      message: "Seul l'administrateur de l'église traite les signalements.",
    });
    return false;
  }
  return true;
}

/** Église mère de l'église donnée, ou null. */
async function egliseMere(db: Pool, churchId: string): Promise<string | null> {
  const { rows } = await db.query<{ parent_church_id: string | null }>(
    `SELECT parent_church_id FROM churches WHERE id = $1`,
    [churchId],
  );
  return rows[0]?.parent_church_id ?? null;
}

export function registerMessagerieModerationRoutes(app: FastifyInstance, db: Pool) {
  const auth = requireAuth(db);

  // -- POST /messagerie/signalements : signaler un message ou une
  // conversation. La preuve est figée au moment du signalement dans
  // evidence_snapshot (avec son empreinte SHA-256) : une modification
  // ou une suppression ultérieure du message ne l'efface pas, et le
  // message est marqué is_reported.
  app.post(
    "/messagerie/signalements",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const parsed = signalerSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message:
            "Signalement invalide : cible (message ou conversation), motif et description de 500 caractères maximum.",
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
              "Votre compte n'est pas lié à une fiche membre : impossible de signaler.",
          });
        }
        let evidence: Record<string, unknown>;
        if (parsed.data.target_type === "message") {
          const { rows } = await db.query(
            `SELECT m.id, m.conversation_id, m.sender_id, m.content, m.type, m.created_at,
                    mem.full_name AS sender_nom
               FROM messages m
               LEFT JOIN members mem ON mem.id = m.sender_id
              WHERE m.id = $1 AND m.church_id = $2`,
            [parsed.data.target_id, churchId],
          );
          if (rows.length === 0) {
            return reply.code(404).send({ error: "not_found", message: "Message introuvable." });
          }
          const message = rows[0];
          if (
            !(await estParticipantActif(db, churchId, message.conversation_id, memberId))
          ) {
            return reply.code(404).send({ error: "not_found", message: "Message introuvable." });
          }
          evidence = {
            target_type: "message",
            message_id: message.id,
            conversation_id: message.conversation_id,
            content: message.content,
            sender_id: message.sender_id,
            sender_nom: message.sender_nom ?? null,
            type: message.type,
            created_at: message.created_at,
          };
        } else {
          const { rows } = await db.query(
            `SELECT id, type, title FROM conversations WHERE id = $1 AND church_id = $2`,
            [parsed.data.target_id, churchId],
          );
          if (rows.length === 0) {
            return reply.code(404).send({
              error: "not_found",
              message: "Conversation introuvable.",
            });
          }
          if (!(await estParticipantActif(db, churchId, parsed.data.target_id, memberId))) {
            return reply.code(404).send({
              error: "not_found",
              message: "Conversation introuvable.",
            });
          }
          evidence = {
            target_type: "conversation",
            conversation_id: rows[0].id,
            type: rows[0].type,
            title: rows[0].title ?? null,
          };
        }

        // Routage : la sécurité d'un enfant part toujours vers le
        // référent protection de l'enfance, hors du circuit ordinaire,
        // quel que soit le destinataire choisi.
        let routedTo: "local" | "mother" | "child_safety_referent" = parsed.data.routed_to;
        let routedToChurchId: string | null = null;
        if (parsed.data.reason === "child_safety") {
          routedTo = "child_safety_referent";
        } else if (routedTo === "mother") {
          const mere = await egliseMere(db, churchId);
          if (!mere) {
            return reply.code(409).send({
              error: "conflict",
              message: "Votre église n'a pas d'église mère : escalade impossible.",
            });
          }
          routedToChurchId = mere;
        }
        const evidenceHash = createHash("sha256")
          .update(JSON.stringify(evidence))
          .digest("hex");

        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows } = await client.query(
            `INSERT INTO reports
               (church_id, reporter_id, target_type, target_id, reason, description,
                evidence_snapshot, evidence_hash, routed_to, routed_to_church_id)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
             RETURNING id, church_id, reporter_id, target_type, target_id, reason,
                       description, evidence_snapshot, evidence_hash, routed_to,
                       routed_to_church_id, status, created_at, resolved_at, resolution_notes`,
            [
              churchId,
              req.session.userId,
              parsed.data.target_type,
              parsed.data.target_id,
              parsed.data.reason,
              parsed.data.description ?? null,
              JSON.stringify(evidence),
              evidenceHash,
              routedTo,
              routedToChurchId,
            ],
          );
          if (parsed.data.target_type === "message") {
            await client.query(
              `UPDATE messages SET is_reported = true WHERE id = $1`,
              [parsed.data.target_id],
            );
          }
          await client.query("COMMIT");
          await auditLog(client, {
            churchId,
            userId: req.session.userId,
            action: "messagerie.signalement_cree",
            details: {
              report_id: rows[0].id,
              target_type: parsed.data.target_type,
              target_id: parsed.data.target_id,
              reason: parsed.data.reason,
              routed_to: routedTo,
            },
          }).catch(() => undefined);
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

  // -- GET /messagerie/signalements : file de modération de l'église
  // (administrateur seulement), avec les signalements transmis par
  // ses églises filles (lecture seule, champs restreints).
  app.get(
    "/messagerie/signalements",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      if (!gardeModerateur(req, reply)) return;
      const query = req.query as { statut?: string; motif?: string; routed_to?: string };
      if (
        (query.statut !== undefined && !(STATUTS_SIGNALEMENT as readonly string[]).includes(query.statut)) ||
        (query.motif !== undefined && !(MOTIFS_SIGNALEMENT as readonly string[]).includes(query.motif)) ||
        (query.routed_to !== undefined &&
          !["local", "mother", "child_safety_referent"].includes(query.routed_to))
      ) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Filtre invalide : statut, motif ou destinataire inconnu.",
        });
      }
      try {
        const conditions: string[] = [
          `(r.church_id = $1 OR (r.routed_to = 'mother' AND r.routed_to_church_id = $1))`,
        ];
        const valeurs: unknown[] = [req.session.churchId];
        if (query.statut !== undefined) {
          valeurs.push(query.statut);
          conditions.push(`r.status = $${valeurs.length}`);
        }
        if (query.motif !== undefined) {
          valeurs.push(query.motif);
          conditions.push(`r.reason = $${valeurs.length}`);
        }
        if (query.routed_to !== undefined) {
          valeurs.push(query.routed_to);
          conditions.push(`r.routed_to = $${valeurs.length}`);
        }
        const { rows } = await db.query<LigneSignalement>(
          `SELECT r.*, u.full_name AS reporter_nom
             FROM reports r
             LEFT JOIN users u ON u.id = r.reporter_id
            WHERE ${conditions.join(" AND ")}
            ORDER BY r.created_at DESC`,
          valeurs,
        );
        return reply.send(
          rows.map((r) =>
            porteeSignalement(r, req.session.churchId) === "mere"
              ? projeterPourMere(r)
              : r,
          ),
        );
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- GET /messagerie/signalements/:id : détail d'un signalement,
  // avec l'historique des actions de modération et les recours.
  app.get(
    "/messagerie/signalements/:id",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      if (!gardeModerateur(req, reply)) return;
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
      }
      try {
        const { rows } = await db.query<LigneSignalement>(
          `SELECT r.*, u.full_name AS reporter_nom
             FROM reports r
             LEFT JOIN users u ON u.id = r.reporter_id
            WHERE r.id = $1`,
          [id],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        const portee = porteeSignalement(rows[0], req.session.churchId);
        if (portee === null) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        if (portee === "mere") {
          return reply.send(projeterPourMere(rows[0]));
        }
        const { rows: actions } = await db.query(
          `SELECT id, report_id, moderator_id, action, notes, created_at
             FROM moderation_actions WHERE report_id = $1 ORDER BY created_at ASC`,
          [id],
        );
        const { rows: recours } = await db.query(
          `SELECT id, report_id, moderation_action_id, appellant_id, reason, reviewer_id,
                  status, created_at, resolved_at,
                  created_at + INTERVAL '30 days' AS repondre_avant
             FROM appeals WHERE report_id = $1 ORDER BY created_at ASC`,
          [id],
        );
        return reply.send({ ...rows[0], actions, recours });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- POST /messagerie/signalements/:id/actions : action de
  // modération (note motivée exigée). Rejeter ferme le signalement
  // sans sanction ; avertir / sourdine / suspendre le résolvent avec
  // sanction. La sourdine bloque l'auteur dans la conversation
  // signalée, la suspension dans toute la messagerie de l'église
  // (muted_until), jusqu'à la durée choisie.
  app.post(
    "/messagerie/signalements/:id/actions",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      if (!gardeModerateur(req, reply)) return;
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
      }
      const parsed = actionModerationSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message:
            "Action invalide : action (rejeter, avertir, sourdine, suspendre), note motivée obligatoire, durée 24, 168 ou 720 heures pour sourdine et suspension.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { action, notes } = parsed.data;
      if (
        (action === "sourdine" || action === "suspendre") &&
        parsed.data.duree_heures === undefined
      ) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "La sourdine et la suspension exigent une durée (24, 168 ou 720 heures).",
        });
      }
      if (
        (action === "rejeter" || action === "avertir") &&
        parsed.data.duree_heures !== undefined
      ) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Rejeter et avertir n'ont pas de durée.",
        });
      }
      try {
        const { rows } = await db.query<LigneSignalement>(
          `SELECT * FROM reports WHERE id = $1`,
          [id],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        const signalement = rows[0];
        const portee = porteeSignalement(signalement, req.session.churchId);
        if (portee === null) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        if (portee === "mere") {
          return reply.code(403).send({
            error: "forbidden",
            message: "Un signalement transmis par une église fille est en lecture seule.",
          });
        }
        if ((STATUTS_FERMES as readonly string[]).includes(signalement.status)) {
          return reply.code(409).send({
            error: "conflict",
            message: "Ce signalement est déjà traité.",
          });
        }
        // Auteur sanctionné : figé dans la preuve du signalement.
        const auteurId =
          (signalement.evidence_snapshot as Record<string, unknown> | null)?.[
            "sender_id"
          ] as string | undefined;
        if ((action === "sourdine" || action === "suspendre") && !auteurId) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "La sourdine et la suspension exigent un message signalé.",
          });
        }
        const client = await db.connect();
        try {
          await client.query("BEGIN");
          const { rows: actionRows } = await client.query(
            `INSERT INTO moderation_actions (report_id, church_id, moderator_id, action, notes)
             VALUES ($1, $2, $3, $4, $5)
             RETURNING id, report_id, moderator_id, action, notes, created_at`,
            [id, req.session.churchId, req.session.userId, action, notes],
          );
          const nouveauStatut = action === "rejeter" ? "dismissed" : "resolved";
          await client.query(
            `UPDATE reports SET status = $1, resolved_at = NOW(), resolution_notes = $2 WHERE id = $3`,
            [nouveauStatut, notes, id],
          );
          if (action === "sourdine" && auteurId) {
            const conversationId = (
              signalement.evidence_snapshot as Record<string, unknown>
            )["conversation_id"] as string;
            await client.query(
              `UPDATE conversation_participants
                  SET muted_until = NOW() + ($1 || ' hours')::interval
                WHERE conversation_id = $2 AND member_id = $3`,
              [String(parsed.data.duree_heures), conversationId, auteurId],
            );
          }
          if (action === "suspendre" && auteurId) {
            await client.query(
              `UPDATE conversation_participants
                  SET muted_until = NOW() + ($1 || ' hours')::interval
                WHERE church_id = $2 AND member_id = $3`,
              [String(parsed.data.duree_heures), req.session.churchId, auteurId],
            );
          }
          await client.query("COMMIT");
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "messagerie.moderation_action",
            details: {
              report_id: id,
              action,
              duree_heures: parsed.data.duree_heures ?? null,
            },
          }).catch(() => undefined);
          return reply.code(201).send({
            ...actionRows[0],
            report_status: nouveauStatut,
          });
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

  // -- POST /messagerie/signalements/:id/escalade : transmettre un
  // signalement à l'église mère ou au référent protection de
  // l'enfance. Le signalement passe en « escalated » et ne peut plus
  // être traité localement.
  app.post(
    "/messagerie/signalements/:id/escalade",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      if (!gardeModerateur(req, reply)) return;
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
      }
      const parsed = escaladeSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Destination invalide : mother ou child_safety_referent.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const { rows } = await db.query<LigneSignalement>(
          `SELECT * FROM reports WHERE id = $1`,
          [id],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        const signalement = rows[0];
        const portee = porteeSignalement(signalement, req.session.churchId);
        if (portee === null) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        if (portee === "mere") {
          return reply.code(403).send({
            error: "forbidden",
            message: "Un signalement transmis par une église fille est en lecture seule.",
          });
        }
        if (signalement.status !== "pending" && signalement.status !== "in_review") {
          return reply.code(409).send({
            error: "conflict",
            message: "Ce signalement est déjà traité.",
          });
        }
        let routedToChurchId: string | null = null;
        if (parsed.data.destination === "mother") {
          const mere = await egliseMere(db, req.session.churchId);
          if (!mere) {
            return reply.code(409).send({
              error: "conflict",
              message: "Votre église n'a pas d'église mère : escalade impossible.",
            });
          }
          routedToChurchId = mere;
        }
        await db.query(
          `UPDATE reports
              SET routed_to = $1, routed_to_church_id = $2, status = 'escalated'
            WHERE id = $3`,
          [parsed.data.destination, routedToChurchId, id],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "messagerie.signalement_escalade",
          details: { report_id: id, destination: parsed.data.destination },
        }).catch(() => undefined);
        return reply.send({
          id,
          routed_to: parsed.data.destination,
          routed_to_church_id: routedToChurchId,
          status: "escalated",
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- POST /messagerie/signalements/:id/recours : contester une
  // sanction. Seule la personne sanctionnée (auteur du message
  // signalé) peut contester, dans les 15 jours qui suivent l'action
  // de modération. Le signalement passe en « appealed » ; le
  // modérateur a 30 jours pour répondre (repondre_avant).
  app.post(
    "/messagerie/signalements/:id/recours",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
      }
      const parsed = recoursSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Recours invalide : motif de 500 caractères maximum.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        const { rows } = await db.query<LigneSignalement>(
          `SELECT * FROM reports WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        const signalement = rows[0];
        const auteurId = (
          signalement.evidence_snapshot as Record<string, unknown> | null
        )?.["sender_id"] as string | undefined;
        if (auteurId !== memberId) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Seule la personne sanctionnée peut contester.",
          });
        }
        const { rows: actions } = await db.query<{ id: string; action: string; created_at: string }>(
          `SELECT id, action, created_at FROM moderation_actions
            WHERE report_id = $1 AND action <> 'rejeter'
            ORDER BY created_at DESC LIMIT 1`,
          [id],
        );
        if (actions.length === 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Aucune sanction à contester sur ce signalement.",
          });
        }
        const derniereAction = actions[0];
        if (parsed.data.moderation_action_id !== undefined) {
          const { rows: cible } = await db.query(
            `SELECT 1 FROM moderation_actions WHERE id = $1 AND report_id = $2`,
            [parsed.data.moderation_action_id, id],
          );
          if (cible.length === 0) {
            return reply.code(400).send({
              error: "invalid_input",
              message: "L'action de modération contestée n'appartient pas à ce signalement.",
            });
          }
        }
        const limite = new Date(derniereAction.created_at).getTime() + DELAI_RECOURS_JOURS * 86_400_000;
        if (Date.now() > limite) {
          return reply.code(409).send({
            error: "conflict",
            message: `Le délai de recours de ${DELAI_RECOURS_JOURS} jours est dépassé.`,
          });
        }
        const { rows: existants } = await db.query(
          `SELECT 1 FROM appeals
            WHERE report_id = $1 AND appellant_id = $2 AND status IN ('pending', 'in_review')`,
          [id, req.session.userId],
        );
        if (existants.length > 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Un recours est déjà en cours sur ce signalement.",
          });
        }
        const actionId = parsed.data.moderation_action_id ?? derniereAction.id;
        const { rows: recours } = await db.query(
          `INSERT INTO appeals (report_id, church_id, moderation_action_id, appellant_id, reason)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, report_id, moderation_action_id, appellant_id, reason,
                     status, created_at, resolved_at,
                     created_at + INTERVAL '30 days' AS repondre_avant`,
          [id, req.session.churchId, actionId, req.session.userId, parsed.data.reason ?? null],
        );
        await db.query(`UPDATE reports SET status = 'appealed' WHERE id = $1`, [id]);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "messagerie.recours_cree",
          details: { report_id: id, moderation_action_id: actionId },
        }).catch(() => undefined);
        return reply.code(201).send(recours[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- GET /messagerie/signalements/:id/recours : recours d'un
  // signalement (modérateur de l'église, ou la personne concernée).
  app.get(
    "/messagerie/signalements/:id/recours",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
      }
      try {
        const { rows } = await db.query<LigneSignalement>(
          `SELECT * FROM reports WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Signalement introuvable." });
        }
        const estAdmin = req.session.role === "admin_eglise";
        if (!estAdmin) {
          const { rows: miens } = await db.query(
            `SELECT 1 FROM appeals WHERE report_id = $1 AND appellant_id = $2`,
            [id, req.session.userId],
          );
          if (miens.length === 0) {
            return reply.code(403).send({
              error: "forbidden",
              message: "Seul le modérateur ou la personne concernée voit les recours.",
            });
          }
        }
        const { rows: recours } = await db.query(
          `SELECT id, report_id, moderation_action_id, appellant_id, reason, reviewer_id,
                  status, created_at, resolved_at,
                  created_at + INTERVAL '30 days' AS repondre_avant
             FROM appeals WHERE report_id = $1 ORDER BY created_at ASC`,
          [id],
        );
        return reply.send(recours);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- POST /messagerie/recours/:id/traiter : le modérateur répond
  // à un recours (30 jours). Une réponse favorable annule la
  // sanction (sourdine / suspension levée) et ferme le signalement
  // en « dismissed » ; un rejet du recours remet le signalement en
  // « resolved ».
  app.post(
    "/messagerie/recours/:id/traiter",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      if (!gardeModerateur(req, reply)) return;
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Recours introuvable." });
      }
      const parsed = traiterRecoursSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Décision invalide : resolved (favorable) ou dismissed (rejet).",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const { rows } = await db.query<{
          id: string;
          report_id: string;
          church_id: string;
          moderation_action_id: string | null;
          status: string;
        }>(
          `SELECT id, report_id, church_id, moderation_action_id, status
             FROM appeals WHERE id = $1`,
          [id],
        );
        if (rows.length === 0 || rows[0].church_id !== req.session.churchId) {
          return reply.code(404).send({ error: "not_found", message: "Recours introuvable." });
        }
        const recours = rows[0];
        if (recours.status !== "pending" && recours.status !== "in_review") {
          return reply.code(409).send({
            error: "conflict",
            message: "Ce recours est déjà traité.",
          });
        }
        const client = await db.connect();
        try {
          await client.query("BEGIN");
          await client.query(
            `UPDATE appeals SET status = $1, reviewer_id = $2, resolved_at = NOW() WHERE id = $3`,
            [parsed.data.statut, req.session.userId, id],
          );
          if (parsed.data.statut === "resolved") {
            await client.query(
              `UPDATE reports SET status = 'dismissed', resolution_notes = 'Recours accepté : sanction annulée.' WHERE id = $1`,
              [recours.report_id],
            );
            // Sanction annulée : la sourdine / suspension est levée.
            const { rows: sanction } = await client.query<{
              action: string;
            }>(
              `SELECT action FROM moderation_actions WHERE id = $1`,
              [recours.moderation_action_id],
            );
            if (
              sanction.length > 0 &&
              (sanction[0].action === "sourdine" || sanction[0].action === "suspendre")
            ) {
              const { rows: signale } = await client.query<{
                evidence_snapshot: Record<string, unknown> | null;
              }>(`SELECT evidence_snapshot FROM reports WHERE id = $1`, [recours.report_id]);
              const auteurId = signale[0]?.evidence_snapshot?.["sender_id"] as
                | string
                | undefined;
              if (auteurId) {
                await client.query(
                  `UPDATE conversation_participants SET muted_until = NULL
                    WHERE church_id = $1 AND member_id = $2`,
                  [req.session.churchId, auteurId],
                );
              }
            }
          } else {
            await client.query(
              `UPDATE reports SET status = 'resolved' WHERE id = $1`,
              [recours.report_id],
            );
          }
          await client.query("COMMIT");
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "messagerie.recours_traite",
            details: { recours_id: id, report_id: recours.report_id, statut: parsed.data.statut },
          }).catch(() => undefined);
          return reply.send({ id, status: parsed.data.statut, report_id: recours.report_id });
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

  // -- GET /messagerie/mes-sanctions : sanctions qui me concernent
  // (actions de modération sur des messages dont je suis l'auteur),
  // avec le délai de recours restant. L'identité du rapporteur n'y
  // figure jamais.
  app.get(
    "/messagerie/mes-sanctions",
    { preHandler: [auth, gardeMessagerie] },
    async (req, reply) => {
      try {
        const memberId = await ficheMembre(db, req.session.userId);
        if (!memberId) return reply.send([]);
        const { rows } = await db.query(
          `SELECT ma.id AS action_id, ma.report_id, ma.action, ma.notes, ma.created_at,
                  r.reason, r.status AS report_status,
                  EXISTS (SELECT 1 FROM appeals a
                           WHERE a.moderation_action_id = ma.id
                             AND a.status IN ('pending', 'in_review')) AS appel_en_cours,
                  ma.created_at + INTERVAL '15 days' AS contester_avant
             FROM moderation_actions ma
             JOIN reports r ON r.id = ma.report_id
            WHERE r.church_id = $1
              AND ma.action <> 'rejeter'
              AND (r.evidence_snapshot ->> 'sender_id') = $2
            ORDER BY ma.created_at DESC`,
          [req.session.churchId, memberId],
        );
        return reply.send(
          rows.map((r) => ({
            ...r,
            contestable:
              !r.appel_en_cours &&
              new Date(r.contester_avant as string).getTime() > Date.now(),
          })),
        );
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
