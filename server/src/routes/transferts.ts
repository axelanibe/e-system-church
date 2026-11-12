import type { FastifyInstance, FastifyReply } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog, generateMatricule } from "../auth.js";
import { dbError, requireAuth, requireRole, type Session } from "../middleware.js";

/**
 * Transferts de membre entre branches (tranche symbiose, 10 novembre 2026).
 *
 * Règle d'Axel : demande par matricule, validation par les deux pasteurs,
 * historique gardé, l'ancienne branche ne voit plus le membre comme actif.
 * Modèle inspiré de liens_parent_enfant (PR #13 de Connexion Prophétique) :
 * demande, validation par un responsable, seule la liaison validée donne
 * effet — sans copier le code de Connexion Prophétique.
 *
 * Déroulement (deux validations, dans l'ordre) :
 *  1. L'admin de l'église de départ demande le transfert (matricule du
 *     membre + code de l'église d'arrivée + motif facultatif).
 *  2. L'admin de l'église de départ accepte (ou refuse) : tant qu'il n'a
 *     pas accepté, l'église d'arrivée ne peut pas décider.
 *  3. L'admin de l'église d'arrivée accepte (ou refuse).
 *  4. À la double acceptation, le membre change de church_id et reçoit un
 *     nouveau matricule dans l'église d'arrivée (M-KA-0001…) ; l'ancienne
 *     branche ne le voit plus. Un refus d'un côté, ou une annulation par
 *     l'église de départ tant que la demande est en attente, clôt la
 *     demande sans déplacement. L'historique reste dans audit_logs.
 *
 * Isolation stricte : un transfert n'est visible que par ses deux églises
 * (départ et arrivée), filtrées par la church_id de la session.
 *
 * POST /transferts                 — demander (admin de l'église de départ).
 * GET  /transferts                 — à traiter, émises, reçues, historique.
 * GET  /transferts/:id             — un transfert (églises concernées seulement).
 * POST /transferts/:id/accepter    — décision du côté de mon église (admin).
 * POST /transferts/:id/refuser     — décision du côté de mon église (admin).
 * POST /transferts/:id/annuler     — annulation par l'église de départ (admin).
 */

const createSchema = z
  .object({
    matricule: z.string().min(1).max(30),
    eglise_arrivee_code: z.string().min(4).max(20).optional(),
    eglise_arrivee_id: z.string().uuid().optional(),
    motif: z.string().max(500).optional(),
  })
  .refine((d) => d.eglise_arrivee_code ?? d.eglise_arrivee_id, {
    message: "eglise_arrivee_code ou eglise_arrivee_id est requis.",
  });

const READ_ROLES = ["admin_eglise", "responsable_culte"];

/** Colonnes renvoyées pour un transfert, avec les noms des deux églises. */
const SELECT_TRANSFERT = `
  SELECT t.id, t.membre_id, t.membre_nom, t.ancien_matricule, t.nouveau_matricule,
         t.eglise_depart_id, t.eglise_arrivee_id, t.motif, t.status,
         t.decision_depart, t.decision_arrivee,
         t.decide_depart_at, t.decide_arrivee_at, t.created_at, t.updated_at,
         d.code AS depart_code, d.name AS depart_nom, d.city AS depart_ville,
         a.code AS arrivee_code, a.name AS arrivee_nom, a.city AS arrivee_ville
    FROM transferts_membre t
    JOIN churches d ON d.id = t.eglise_depart_id
    JOIN churches a ON a.id = t.eglise_arrivee_id
`;

export function registerTransfertsRoutes(app: FastifyInstance, db: Pool) {
  app.post(
    "/transferts",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = createSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Demande de transfert invalide.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        // Le membre doit appartenir à mon église et être actif (ou nouveau converti).
        const { rows: membres } = await db.query(
          `SELECT id, full_name, matricule, status FROM members
            WHERE matricule = $1 AND church_id = $2`,
          [parsed.data.matricule, req.session.churchId],
        );
        const membre = membres[0];
        if (!membre) {
          return reply.code(404).send({
            error: "not_found",
            message: "Aucun membre de votre église ne porte ce matricule.",
          });
        }
        if (membre.status === "inactif") {
          return reply.code(400).send({
            error: "invalid_member",
            message: "Un membre inactif ne peut pas être transféré.",
          });
        }
        // Résout l'église d'arrivée (par code d'invitation ou par id).
        const { rows: arrivees } = parsed.data.eglise_arrivee_id
          ? await db.query<{ id: string; name: string }>(
              `SELECT id, name FROM churches WHERE id = $1 AND status = 'active'`,
              [parsed.data.eglise_arrivee_id],
            )
          : await db.query<{ id: string; name: string }>(
              `SELECT id, name FROM churches WHERE code = $1 AND status = 'active'`,
              [parsed.data.eglise_arrivee_code],
            );
        const arrivee = arrivees[0];
        if (!arrivee) {
          return reply.code(400).send({
            error: "invalid_destination",
            message: "Église d'arrivée introuvable ou inactive.",
          });
        }
        if (arrivee.id === req.session.churchId) {
          return reply.code(400).send({
            error: "invalid_destination",
            message: "Le membre est déjà dans cette église.",
          });
        }
        const { rows } = await db.query(
          `INSERT INTO transferts_membre
             (membre_id, membre_nom, ancien_matricule, eglise_depart_id,
              eglise_arrivee_id, demande_par, motif, status)
           VALUES ($1, $2, $3, $4, $5, $6, $7, 'en_attente')
           RETURNING id, membre_id, membre_nom, ancien_matricule,
                     eglise_depart_id, eglise_arrivee_id, motif, status,
                     decision_depart, decision_arrivee, created_at`,
          [
            membre.id,
            membre.full_name,
            membre.matricule,
            req.session.churchId,
            arrivee.id,
            req.session.userId,
            parsed.data.motif ?? null,
          ],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "transfert.demande",
          details: {
            transfert_id: rows[0].id,
            membre_id: membre.id,
            matricule: membre.matricule,
            eglise_arrivee_id: arrivee.id,
            eglise_arrivee_nom: arrivee.name,
          },
        });
        return reply.code(201).send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/transferts",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const mine = req.session.churchId;
        const { rows } = await db.query(
          `${SELECT_TRANSFERT}
            WHERE t.eglise_depart_id = $1 OR t.eglise_arrivee_id = $1
            ORDER BY t.created_at DESC`,
          [mine],
        );
        // À traiter par mon église : mon tour de décider n'est pas encore venu
        // ou n'est pas encore passé.
        const aTraiter = rows.filter(
          (r) =>
            r.status === "en_attente" &&
            ((r.eglise_depart_id === mine && r.decision_depart === "en_attente") ||
              (r.eglise_arrivee_id === mine &&
                r.decision_depart === "accepte" &&
                r.decision_arrivee === "en_attente")),
        );
        const emises = rows.filter((r) => r.eglise_depart_id === mine);
        const recues = rows.filter((r) => r.eglise_arrivee_id === mine);
        const historique = rows.filter((r) => r.status !== "en_attente");
        return reply.send({ a_traiter: aTraiter, emises, recues, historique });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/transferts/:id",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `${SELECT_TRANSFERT}
            WHERE t.id = $1
              AND (t.eglise_depart_id = $2 OR t.eglise_arrivee_id = $2)`,
          [(req.params as { id: string }).id, req.session.churchId],
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Transfert introuvable." });
        }
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  /**
   * Décision d'un côté (départ ou arrivée) : accepter ou refuser.
   * Le côté est déterminé par l'église de la session ; l'arrivée ne peut
   * décider qu'après l'acceptation du départ. À la double acceptation, le
   * membre est déplacé (nouveau matricule dans l'église d'arrivée).
   */
  async function decider(
    transfertId: string,
    session: Session,
    reply: FastifyReply,
    accepter: boolean,
  ): Promise<void> {
    try {
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        const { rows } = await client.query(
          `SELECT id, membre_id, ancien_matricule, eglise_depart_id,
                  eglise_arrivee_id, status, decision_depart, decision_arrivee
             FROM transferts_membre WHERE id = $1 FOR UPDATE`,
          [transfertId],
        );
        const t = rows[0];
        if (!t) {
          await client.query("ROLLBACK");
          reply.code(404).send({ error: "not_found", message: "Transfert introuvable." });
          return;
        }
        const cote: "depart" | "arrivee" | null =
          t.eglise_depart_id === session.churchId
            ? "depart"
            : t.eglise_arrivee_id === session.churchId
              ? "arrivee"
              : null;
        if (cote === null) {
          await client.query("ROLLBACK");
          reply.code(403).send({
            error: "forbidden",
            message: "Seules les deux églises concernées peuvent décider.",
          });
          return;
        }
        if (t.status !== "en_attente") {
          await client.query("ROLLBACK");
          reply.code(409).send({
            error: "conflict",
            message: `Ce transfert a déjà été ${t.status === "accepte" ? "accepté" : t.status === "refuse" ? "refusé" : "annulé"}.`,
          });
          return;
        }
        if (cote === "depart" && t.decision_depart !== "en_attente") {
          await client.query("ROLLBACK");
          reply.code(409).send({ error: "conflict", message: "Votre église a déjà décidé." });
          return;
        }
        if (cote === "arrivee") {
          if (t.decision_depart !== "accepte") {
            await client.query("ROLLBACK");
            reply.code(409).send({
              error: "conflict",
              message: "En attente de la décision de l'église de départ.",
            });
            return;
          }
          if (t.decision_arrivee !== "en_attente") {
            await client.query("ROLLBACK");
            reply.code(409).send({ error: "conflict", message: "Votre église a déjà décidé." });
            return;
          }
        }

        const decisionCol = cote === "depart" ? "decision_depart" : "decision_arrivee";
        const decideParCol = cote === "depart" ? "decide_depart_par" : "decide_arrivee_par";
        const decideAtCol = cote === "depart" ? "decide_depart_at" : "decide_arrivee_at";
        const decision = accepter ? "accepte" : "refuse";
        await client.query(
          `UPDATE transferts_membre
              SET ${decisionCol} = $2, ${decideParCol} = $3, ${decideAtCol} = now(),
                  updated_at = now()
            WHERE id = $1`,
          [t.id, decision, session.userId],
        );
        await auditLog(client, {
          churchId: session.churchId,
          userId: session.userId,
          action: accepter ? `transfert.accepte_${cote}` : `transfert.refuse_${cote}`,
          details: { transfert_id: t.id, membre_id: t.membre_id },
        });

        let status = "en_attente";
        let nouveauMatricule: string | null = null;
        if (!accepter) {
          status = "refuse";
        } else if (cote === "arrivee") {
          // Double acceptation : le membre déménage.
          nouveauMatricule = await deplacerMembre(client, t);
          status = "accepte";
        }
        if (status !== "en_attente") {
          await client.query(
            `UPDATE transferts_membre
                SET status = $2, nouveau_matricule = $3, updated_at = now()
              WHERE id = $1`,
            [t.id, status, nouveauMatricule],
          );
          if (status === "accepte") {
            await auditLog(client, {
              churchId: t.eglise_arrivee_id as string,
              userId: session.userId,
              action: "transfert.effectue",
              details: {
                transfert_id: t.id,
                membre_id: t.membre_id,
                ancien_matricule: t.ancien_matricule,
                nouveau_matricule: nouveauMatricule,
                eglise_depart_id: t.eglise_depart_id,
              },
            });
          }
        }
        await client.query("COMMIT");
        reply.send({ id: t.id, status, nouveau_matricule: nouveauMatricule });
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

  /**
   * Déplace le membre vers l'église d'arrivée avec un nouveau matricule
   * (M-KA-0001 : 2 lettres du nom du membre + 4 chiffres, séquentiel
   * global par préfixe, unique dans tout le système). La contrainte
   * UNIQUE (church_id, matricule) protège des courses : en cas de
   * collision on régénère après un retour au point de sauvegarde,
   * 3 essais maximum.
   */
  async function deplacerMembre(
    client: PoolClient,
    t: {
      membre_id: string;
      eglise_depart_id: string;
      eglise_arrivee_id: string;
    },
  ): Promise<string> {
    const { rows: nomRows } = await client.query<{ full_name: string }>(
      `SELECT full_name FROM members WHERE id = $1`,
      [t.membre_id],
    );
    const fullName = nomRows[0]?.full_name ?? "";
    for (let attempt = 0; attempt < 3; attempt++) {
      const matricule = await generateMatricule(client, fullName);
      await client.query("SAVEPOINT deplacement");
      try {
        const { rowCount } = await client.query(
          `UPDATE members
              SET church_id = $2, matricule = $3, updated_at = now()
            WHERE id = $1 AND church_id = $4`,
          [t.membre_id, t.eglise_arrivee_id, matricule, t.eglise_depart_id],
        );
        if (!rowCount || rowCount === 0) {
          throw new Error("Le membre n'est plus dans l'église de départ.");
        }
        await client.query("RELEASE SAVEPOINT deplacement");
        return matricule;
      } catch (e) {
        await client.query("ROLLBACK TO SAVEPOINT deplacement").catch(() => undefined);
        if ((e as { code?: string }).code === "23505" && attempt < 2) continue;
        throw e;
      }
    }
    throw new Error("Déplacement du membre impossible.");
  }

  app.post(
    "/transferts/:id/accepter",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) =>
      decider((req.params as { id: string }).id, req.session, reply, true),
  );

  app.post(
    "/transferts/:id/refuser",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) =>
      decider((req.params as { id: string }).id, req.session, reply, false),
  );

  app.post(
    "/transferts/:id/annuler",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, eglise_depart_id, status FROM transferts_membre WHERE id = $1`,
          [(req.params as { id: string }).id],
        );
        const t = rows[0];
        if (!t) {
          return reply.code(404).send({ error: "not_found", message: "Transfert introuvable." });
        }
        if (t.eglise_depart_id !== req.session.churchId) {
          return reply.code(403).send({
            error: "forbidden",
            message: "Seule l'église de départ peut annuler la demande.",
          });
        }
        if (t.status !== "en_attente") {
          return reply.code(409).send({
            error: "conflict",
            message: "Seule une demande en attente peut être annulée.",
          });
        }
        await db.query(
          `UPDATE transferts_membre SET status = 'annule', updated_at = now() WHERE id = $1`,
          [t.id],
        );
        await auditLog(db, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "transfert.annule",
          details: { transfert_id: t.id },
        });
        return reply.send({ id: t.id, status: "annule" });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
