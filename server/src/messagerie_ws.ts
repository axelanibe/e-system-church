import type { FastifyInstance } from "fastify";
import jwt from "jsonwebtoken";
import type { Pool } from "pg";
import type { WebSocket } from "ws";
import { z } from "zod";
import { auditLog, getJwtSecret } from "./auth.js";
import type { Session } from "./middleware.js";
import { estParticipantActif, ficheMembre } from "./messagerie_commun.js";

/**
 * Tranche T-Msg-1 — Messagerie et Signalement : WebSocket authentifié,
 * abonnement par conversation, diffusion aux participants.
 *
 * Le WebSocket est en réception seulement : l'envoi reste sur le POST
 * HTTP de T-Msg-0, qui appelle diffuserMessageWs après un envoi réussi.
 * Authentification par jeton JWT en paramètre de requête `?token=` :
 * un client WebSocket navigateur ne peut pas poser d'en-tête
 * Authorization. Même secret et même logique que requireAuth (jeton,
 * version, appartenance à l'église), plus la garde de rôle propre à
 * la messagerie : le super administrateur et l'aide Plateforme n'ont
 * aucun accès au contenu des messages.
 */

// 1008 (Policy Violation) : fermeture explicite pour jeton ou rôle refusé.
const FERMETURE_NON_AUTORISE = 1008;

const ROLES_MESSAGERIE = ["admin_eglise", "tresorier", "responsable_culte", "membre"];

const uuid = z.string().uuid();

interface ClientConnecte {
  socket: WebSocket;
  session: Session;
  memberId: string;
  abonnements: Set<string>;
}

const clients = new Set<ClientConnecte>();

/**
 * Diffuse un message à tous les participants connectés de la
 * conversation, dans cette église seulement. Appelé par le POST HTTP
 * après un envoi réussi.
 */
export function diffuserMessageWs(
  conversationId: string,
  churchId: string,
  message: unknown,
): void {
  const texte = JSON.stringify({ type: "message", conversation_id: conversationId, message });
  for (const client of clients) {
    if (client.session.churchId !== churchId) continue;
    if (!client.abonnements.has(conversationId)) continue;
    if (client.socket.readyState !== 1) continue;
    client.socket.send(texte);
  }
}

/** Vérifie un JWT comme requireAuth, sans objet requête. Renvoie la
 *  session, ou le motif du refus. */
async function verifierJetonWs(db: Pool, token: string): Promise<Session | { refus: string }> {
  let payload: unknown;
  try {
    payload = jwt.verify(token, getJwtSecret());
  } catch {
    return { refus: "Jeton invalide ou expiré." };
  }
  const p = payload as { sub?: string; churchId?: string; role?: string; v?: number };
  if (!p.sub || !p.churchId || !p.role) return { refus: "Jeton incomplet." };
  const { rows: versionRows } = await db.query<{ token_version: number }>(
    `SELECT token_version FROM users WHERE id = $1`,
    [p.sub],
  );
  if (versionRows.length === 0) return { refus: "Compte introuvable." };
  if ((p.v ?? 0) !== versionRows[0].token_version) {
    return { refus: "Session invalidée (mot de passe changé). Reconnectez-vous." };
  }
  const { rows } = await db.query<{ role: string }>(
    `SELECT role FROM church_users WHERE user_id = $1 AND church_id = $2`,
    [p.sub, p.churchId],
  );
  if (rows.length === 0) return { refus: "Appartenance à l'église introuvable." };
  return { userId: p.sub, churchId: p.churchId, role: rows[0].role };
}

export function registerMessagerieWs(app: FastifyInstance, db: Pool) {
  app.get("/messagerie/ws", { websocket: true }, async (socket, req) => {
    // Les messages envoyés dès l'ouverture peuvent arriver pendant
    // l'authentification (requêtes en base) : `ws` ne met pas les
    // trames en attente, elles seraient perdues si l'écouteur n'était
    // posé qu'après. On pose l'écouteur tout de suite, on tamponne,
    // on rejoue après l'authentification.
    const tampon: Array<Buffer | ArrayBuffer | Buffer[]> = [];
    let pret = false;
    let client: ClientConnecte | undefined;
    socket.on("message", (donnees) => {
      if (!pret) {
        tampon.push(donnees);
        return;
      }
      void traiterMessage(donnees);
    });

    /** Traite un message { type: "subscribe", conversation_id }. */
    async function traiterMessage(donnees: Buffer | ArrayBuffer | Buffer[]): Promise<void> {
      if (!client) return;
      const texte = Array.isArray(donnees)
        ? Buffer.concat(donnees).toString("utf8")
        : donnees.toString();
      let recu: unknown;
      try {
        recu = JSON.parse(texte);
      } catch {
        socket.send(
          JSON.stringify({
            type: "error",
            code: "invalid_message",
            message: "Message JSON invalide.",
          }),
        );
        return;
      }
      const msg = recu as { type?: string; conversation_id?: string };
      if (msg.type !== "subscribe" || typeof msg.conversation_id !== "string") {
        socket.send(
          JSON.stringify({
            type: "error",
            code: "invalid_message",
            message: 'Message attendu : { type: "subscribe", conversation_id }.',
          }),
        );
        return;
      }
      const conversationId = msg.conversation_id;
      if (!uuid.safeParse(conversationId).success) {
        socket.send(
          JSON.stringify({
            type: "error",
            code: "not_found",
            message: "Conversation introuvable.",
          }),
        );
        return;
      }
      let participant = false;
      try {
        participant = await estParticipantActif(
          db,
          client.session.churchId,
          conversationId,
          client.memberId,
        );
      } catch (e) {
        app.log.error(e, "WebSocket messagerie : vérification de participation en échec.");
        socket.send(
          JSON.stringify({
            type: "error",
            code: "server_error",
            message: "Vérification impossible pour le moment.",
          }),
        );
        return;
      }
      if (!participant) {
        // Tentative hors périmètre : journalisée dans l'audit de
        // l'église de l'appelant, sans révéler si la conversation
        // existe ni à quelle église elle appartient.
        app.log.warn(
          `WebSocket messagerie : abonnement refusé pour ${client.session.userId} à la conversation ${conversationId} (église ${client.session.churchId}).`,
        );
        await auditLog(db, {
          churchId: client.session.churchId,
          userId: client.session.userId,
          action: "messagerie.abonnement_refuse",
          details: { conversation_id: conversationId },
        }).catch((e) =>
          app.log.error(e, "WebSocket messagerie : audit de l'abonnement refusé en échec."),
        );
        socket.send(
          JSON.stringify({
            type: "error",
            code: "forbidden",
            message: "Conversation introuvable ou accès refusé.",
          }),
        );
        return;
      }
      // Réabonnement idempotent : un Set, un seul accusé par demande,
      // une seule diffusion par message ensuite.
      client.abonnements.add(conversationId);
      socket.send(JSON.stringify({ type: "subscribed", conversation_id: conversationId }));
    }

    // req.query n'est pas renseigné sur les routes WebSocket : le jeton
    // se lit dans l'URL brute de la demande de mise à niveau.
    const url = new URL(req.raw.url ?? "", "http://localhost");
    const token = url.searchParams.get("token") ?? undefined;
    if (!token) {
      app.log.warn("WebSocket messagerie : connexion sans jeton, fermée.");
      socket.close(FERMETURE_NON_AUTORISE, "Jeton manquant.");
      return;
    }
    const session = await verifierJetonWs(db, token);
    if ("refus" in session) {
      app.log.warn(`WebSocket messagerie : jeton refusé (${session.refus})`);
      socket.close(FERMETURE_NON_AUTORISE, session.refus);
      return;
    }
    if (session.role === "super_admin" || session.role === "aide_plateforme") {
      app.log.warn(
        `WebSocket messagerie : rôle ${session.role} sans accès au contenu, connexion fermée.`,
      );
      socket.close(FERMETURE_NON_AUTORISE, "Ce rôle n'a pas accès au contenu des messages.");
      return;
    }
    if (!ROLES_MESSAGERIE.includes(session.role)) {
      socket.close(
        FERMETURE_NON_AUTORISE,
        `Action non autorisée pour le rôle « ${session.role} ».`,
      );
      return;
    }
    const memberId = await ficheMembre(db, session.userId);
    if (!memberId) {
      socket.close(
        FERMETURE_NON_AUTORISE,
        "Votre compte n'est pas lié à une fiche membre.",
      );
      return;
    }
    // La connexion a pu se fermer pendant l'authentification : ne pas
    // enregistrer un client déjà parti.
    if (socket.readyState !== 1) return;

    client = {
      socket,
      session,
      memberId,
      abonnements: new Set(),
    };
    clients.add(client);

    socket.on("close", () => {
      clients.delete(client);
    });
    socket.on("error", (err) => {
      app.log.warn(err, "WebSocket messagerie : erreur de connexion.");
      clients.delete(client);
    });
    // Messages arrivés pendant l'authentification : rejoués ici.
    pret = true;
    for (const donnees of tampon) void traiterMessage(donnees);
    tampon.length = 0;
  });
}
