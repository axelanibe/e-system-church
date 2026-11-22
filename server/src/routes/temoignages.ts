import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { bearerToken, dbError, requireAuth, requireRole } from "../middleware.js";
import {
  LIMITE_CORPS_PUBLICATION_TEMOIGNAGE_OCTETS,
  LIMITE_PUBLICATIONS_TEMOIGNAGE_PAR_HEURE,
  decoderMediaTemoignage,
  formaterTemoignagePublic,
} from "../temoignages.js";

/**
 * Lot 3c — Témoignages (22 novembre 2026) : texte, photo, vidéo ou
 * audio, publiés par un membre, modérés par l'admin de l'église.
 * Modèle : Connexion Prophétique (lib/temoignages.dart), adapté :
 * isolation par church_id comme la messagerie, modération réservée à
 * admin_eglise, statuts en_attente / approuve / rejete, médias stockés
 * en base (BYTEA) et servis par /temoignages/:id/media — pas de
 * compartiment objet dans ce projet. Le statut ne s'affiche que pour
 * l'auteur et l'admin, jamais dans le fil public (seuls les approuvés
 * y sont visibles). Le super administrateur et l'aide Plateforme n'ont
 * aucun accès au contenu, comme pour la messagerie (même périmètre).
 */

const uuid = z.string().uuid();

const publierSchema = z.object({
  texte: z.string().max(2000).optional(),
  media_base64: z.string().optional(),
  media_mime: z.string().max(100).optional(),
  media_nom: z.string().max(200).optional(),
});

const modererSchema = z.object({
  statut: z.enum(["approuve", "rejete"]),
  motif_rejet: z.string().max(500).optional(),
});

/**
 * Limite de débit : 10 publications par heure et par auteur. Limiteur
 * simple en mémoire (une seule instance serveur), même motif que celui
 * de la messagerie. Les horodatages de plus d'une heure sont purgés à
 * chaque contrôle.
 */
const publicationsParAuteur = new Map<string, number[]>();

function depasseLimitePublications(userId: string): boolean {
  const maintenant = Date.now();
  const envois = (publicationsParAuteur.get(userId) ?? []).filter(
    (t) => maintenant - t < 3_600_000,
  );
  if (envois.length === 0) publicationsParAuteur.delete(userId);
  else publicationsParAuteur.set(userId, envois);
  return envois.length >= LIMITE_PUBLICATIONS_TEMOIGNAGE_PAR_HEURE;
}

function enregistrerPublication(userId: string): void {
  const envois = publicationsParAuteur.get(userId) ?? [];
  envois.push(Date.now());
  publicationsParAuteur.set(userId, envois);
}

/**
 * Garde de rôle propre aux témoignages : le super administrateur et
 * l'aide Plateforme n'ont aucun accès au contenu, comme pour la
 * messagerie. Tous les autres rôles de l'église peuvent publier et
 * lire le fil ; seule la modération est réservée à admin_eglise.
 */
export async function gardeTemoignages(
  req: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  if (req.session.role === "super_admin") {
    reply.code(403).send({
      error: "forbidden",
      message: "Le super administrateur n'a aucun accès au contenu des témoignages.",
    });
    return;
  }
  if (req.session.role === "aide_plateforme") {
    reply.code(403).send({
      error: "forbidden",
      message: "L'aide Plateforme n'a accès qu'aux chiffres, pas au contenu des témoignages.",
    });
    return;
  }
}

/**
 * Authentification pour le téléchargement du média : le lecteur vidéo
 * et l'afficheur d'image ne peuvent pas envoyer d'en-tête
 * Authorization, le jeton passe donc en paramètre `?token=` — même
 * motif que le WebSocket de messagerie (`?token=`). Le jeton est
 * vérifié exactement comme un Bearer (rôle relu en base).
 */
function authOuJetonRequete(db: Pool) {
  const auth = requireAuth(db);
  return async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    if (!bearerToken(req)) {
      const jeton = (req.query as { token?: string }).token;
      if (typeof jeton === "string" && jeton.length > 0) {
        req.headers.authorization = `Bearer ${jeton}`;
      }
    }
    await auth(req, reply);
  };
}

const COLONNES_PUBLIQUES = `id, auteur_nom, texte, type_media, type_mime,
  statut, cree_le,
  CASE WHEN media_octets IS NULL THEN false ELSE true END AS a_media`;

type LignePublique = Parameters<typeof formaterTemoignagePublic>[0];

export function registerTemoignagesRoutes(app: FastifyInstance, db: Pool) {
  const auth = requireAuth(db);

  // -- GET /temoignages : fil approuvé, mes témoignages, file de modération.
  app.get(
    "/temoignages",
    { preHandler: [auth, gardeTemoignages] },
    async (req, reply) => {
      try {
        const churchId = req.session.churchId;
        const { rows: fil } = await db.query(
          `SELECT ${COLONNES_PUBLIQUES} FROM temoignages
            WHERE church_id = $1 AND statut = 'approuve'
            ORDER BY cree_le DESC LIMIT 100`,
          [churchId],
        );
        const { rows: miens } = await db.query(
          `SELECT ${COLONNES_PUBLIQUES} FROM temoignages
            WHERE church_id = $1 AND auteur_user_id = $2
            ORDER BY cree_le DESC LIMIT 100`,
          [churchId, req.session.userId],
        );
        let moderation: LignePublique[] = [];
        if (req.session.role === "admin_eglise") {
          const { rows } = await db.query(
            `SELECT ${COLONNES_PUBLIQUES} FROM temoignages
              WHERE church_id = $1 AND statut = 'en_attente'
              ORDER BY cree_le ASC LIMIT 100`,
            [churchId],
          );
          moderation = rows as LignePublique[];
        }
        return reply.send({
          temoignages: fil.map((r) => formaterTemoignagePublic(r)),
          mes_temoignages: miens.map((r) => formaterTemoignagePublic(r)),
          moderation: moderation.map((r) => formaterTemoignagePublic(r)),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- POST /temoignages : publier (texte seul accepté, ou texte + un média).
  app.post(
    "/temoignages",
    {
      preHandler: [auth, gardeTemoignages],
      bodyLimit: LIMITE_CORPS_PUBLICATION_TEMOIGNAGE_OCTETS,
    },
    async (req, reply) => {
      const parsed = publierSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Corps invalide : texte (2000 caractères maximum) et média facultatif.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const controle = decoderMediaTemoignage({
        mediaBase64: parsed.data.media_base64,
        mediaMime: parsed.data.media_mime,
        texte: parsed.data.texte,
      });
      if ("statut" in controle) {
        return reply.code(controle.statut).send({
          error: "invalid_input",
          message: controle.message,
        });
      }
      try {
        if (depasseLimitePublications(req.session.userId)) {
          return reply.code(429).send({
            error: "rate_limited",
            message: "Trop de témoignages : 10 par heure maximum.",
          });
        }
        // Nom de l'auteur : fiche membre liée au compte (dans cette
        // église), sinon le nom du compte.
        const { rows: auteurRows } = await db.query<{
          nom_compte: string;
          member_id: string | null;
          nom_membre: string | null;
        }>(
          `SELECT u.full_name AS nom_compte, m.id AS member_id, m.full_name AS nom_membre
             FROM users u
             LEFT JOIN members m ON m.id = u.member_id AND m.church_id = $2
            WHERE u.id = $1`,
          [req.session.userId, req.session.churchId],
        );
        const auteur = auteurRows[0];
        if (!auteur) {
          return reply.code(401).send({ error: "unauthorized", message: "Compte introuvable." });
        }
        const textePropre = (parsed.data.texte ?? "").trim();
        const { rows } = await db.query(
          `INSERT INTO temoignages
             (church_id, auteur_user_id, auteur_member_id, auteur_nom,
              texte, type_media, type_mime, media_octets, media_nom, statut)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'en_attente')
           RETURNING ${COLONNES_PUBLIQUES}`,
          [
            req.session.churchId,
            req.session.userId,
            auteur.member_id,
            auteur.nom_membre ?? auteur.nom_compte,
            textePropre,
            controle.typeMedia,
            controle.typeMedia === "texte" ? null : controle.mimeReel,
            controle.typeMedia === "texte" ? null : controle.octets,
            parsed.data.media_nom ?? null,
          ],
        );
        enregistrerPublication(req.session.userId);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "temoignage.publie",
          details: { temoignage_id: rows[0].id, type_media: controle.typeMedia },
        });
        return reply.code(201).send(formaterTemoignagePublic(rows[0]));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- POST /temoignages/:id/moderer : approuver ou rejeter (admin_eglise).
  app.post(
    "/temoignages/:id/moderer",
    { preHandler: [auth, gardeTemoignages, requireRole("admin_eglise")] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Témoignage introuvable." });
      }
      const parsed = modererSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Corps invalide : statut « approuve » ou « rejete », motif facultatif.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const { rows } = await db.query(
          `UPDATE temoignages
              SET statut = $3, motif_rejet = $4, modere_le = NOW(), modere_par = $5
            WHERE id = $1 AND church_id = $2 AND statut = 'en_attente'
            RETURNING ${COLONNES_PUBLIQUES}`,
          [
            id,
            req.session.churchId,
            parsed.data.statut,
            parsed.data.statut === "rejete" ? (parsed.data.motif_rejet ?? null) : null,
            req.session.userId,
          ],
        );
        if (rows.length === 0) {
          return reply.code(409).send({
            error: "conflict",
            message: "Témoignage introuvable, ou déjà modéré.",
          });
        }
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "temoignage.modere",
          details: { temoignage_id: id, statut: parsed.data.statut },
        });
        return reply.send(formaterTemoignagePublic(rows[0]));
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- DELETE /temoignages/:id : auteur ou admin_eglise.
  app.delete(
    "/temoignages/:id",
    { preHandler: [auth, gardeTemoignages] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Témoignage introuvable." });
      }
      try {
        const { rows: trouves } = await db.query<{ auteur_user_id: string }>(
          `SELECT auteur_user_id FROM temoignages WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (trouves.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Témoignage introuvable." });
        }
        if (
          trouves[0].auteur_user_id !== req.session.userId &&
          req.session.role !== "admin_eglise"
        ) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Seul l'auteur ou l'admin de l'église peut supprimer ce témoignage.",
          });
        }
        await db.query(`DELETE FROM temoignages WHERE id = $1 AND church_id = $2`, [
          id,
          req.session.churchId,
        ]);
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "temoignage.supprime",
          details: { temoignage_id: id },
        });
        return reply.send({ ok: true });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- GET /temoignages/:id/media : octets du média, accès contrôlé.
  // Un témoignage approuvé est lisible par tous les membres de
  // l'église ; en attente ou rejeté, seulement par son auteur et
  // l'admin. Hors de ces cas : 404, sans révéler l'existence.
  app.get(
    "/temoignages/:id/media",
    { preHandler: [authOuJetonRequete(db), gardeTemoignages] },
    async (req, reply) => {
      const id = (req.params as { id: string }).id;
      if (!uuid.safeParse(id).success) {
        return reply.code(404).send({ error: "not_found", message: "Témoignage introuvable." });
      }
      try {
        const { rows } = await db.query<{
          statut: string;
          auteur_user_id: string;
          type_mime: string | null;
          media_octets: Buffer | null;
        }>(
          `SELECT statut, auteur_user_id, type_mime, media_octets
             FROM temoignages WHERE id = $1 AND church_id = $2`,
          [id, req.session.churchId],
        );
        if (rows.length === 0 || !rows[0].media_octets) {
          return reply.code(404).send({ error: "not_found", message: "Média introuvable." });
        }
        const ligne = rows[0];
        const visible =
          ligne.statut === "approuve" ||
          ligne.auteur_user_id === req.session.userId ||
          req.session.role === "admin_eglise";
        if (!visible) {
          return reply.code(404).send({ error: "not_found", message: "Média introuvable." });
        }
        return reply
          .header("Content-Type", ligne.type_mime ?? "application/octet-stream")
          .header("Content-Disposition", "inline")
          .header("Cache-Control", "private, max-age=3600")
          .send(ligne.media_octets);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
