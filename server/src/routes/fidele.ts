import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog, hashPassword, inscriptionMembreParCode, login } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Modules 15-16 — accès fidèle : inscription par matricule (liaison
 * immédiate si l'e-mail concorde, demande en attente sinon ; champ
 * optionnel `code_fidele` pour restreindre la recherche à une église)
 * et inscription par code fidèle, sans validation (le code fait foi :
 * matricule attribué automatiquement, fiche membre et carte créées tout
 * de suite), validation des liaisons par l'admin, profil `/moi` et
 * lectures limitées à son église et à ses propres données (annonces,
 * cultes, présences, contributions, carte de membre).
 *
 * Un fidèle ne voit jamais les données d'un autre membre, ni les finances
 * globales, ni les écrans d'administration (rôle `membre` seulement).
 */

const inscriptionSchema = z.object({
  email: z.string().email().max(254),
  mot_de_passe: z.string().min(8).max(256),
  matricule: z.string().min(1).max(30),
  /**
   * Code fidèle de l'église (ESC-F-…), optionnel : quand il est fourni,
   * la recherche du membre par matricule est restreinte à cette église
   * (les nouveaux matricules, M-LA-171268-01, sont uniques dans tout le
   * système ; les anciens numéros M-XXXX et M-KA-0001 peuvent encore se
   * répéter d'une église à l'autre). Sans lui, on garde le comportement
   * existant (e-mail concordant, sinon ambiguïté).
   */
  code_fidele: z.string().min(4).max(20).optional(),
  channel: z.enum(["web", "mobile"]).default("mobile"),
});

export function registerFideleRoutes(app: FastifyInstance, db: Pool) {
  // -- Inscription fidèle : par matricule. E-mail concordant avec la fiche
  // membre → liaison immédiate + connexion. Sinon → demande en attente.
  app.post("/auth/inscription-fidele", async (req, reply) => {
    const parsed = inscriptionSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "E-mail, mot de passe (8 caractères minimum) ou matricule invalide.",
        details: parsed.error.issues.map((i) => i.message),
      });
    }
    const { email, mot_de_passe, matricule, code_fidele, channel } = parsed.data;
    const emailNorm = email.toLowerCase();
    // Saisie normalisée : sans tirets ni espaces, en majuscules — ainsi
    // « M-LA-171268-01 » et « MLA17126801 » trouvent le même membre.
    // La comparaison se fait sur les formes dépouillées, ce qui couvre
    // aussi les anciens matricules stockés sans tirets.
    const matriculeNu = matricule.trim().toUpperCase().replace(/[\s-]/g, "");
    const client = await db.connect();
    try {
      await client.query("BEGIN");

      // Code fidèle fourni : on restreint la recherche à son église
      // (le matricule seul est ambigu entre églises).
      let churchId: string | null = null;
      if (code_fidele) {
        const { rows: churchRows } = await client.query<{ id: string }>(
          `SELECT id FROM churches WHERE upper(code_fidele) = $1 AND status = 'active'`,
          [code_fidele.trim().toUpperCase()],
        );
        if (churchRows.length === 0) {
          await client.query("ROLLBACK");
          return reply.code(404).send({
            error: "invalid_code_fidele",
            message: "Code fidèle inconnu. Vérifiez le code donné par votre église.",
          });
        }
        churchId = churchRows[0].id;
      }

      // Le matricule était unique PAR église (anciens numéros) : plusieurs
      // membres peuvent encore le porter. On préfère celui dont l'e-mail
      // concorde ; sinon, un seul
      // candidat actif ; sinon, l'inscription est refusée (ambiguïté).
      const { rows: candidats } = await client.query(
        churchId
          ? `SELECT id, church_id, matricule, full_name, email, user_id
               FROM members WHERE upper(replace(replace(matricule, '-', ''), ' ', '')) = $1 AND status = 'actif' AND church_id = $2`
          : `SELECT id, church_id, matricule, full_name, email, user_id
               FROM members WHERE upper(replace(replace(matricule, '-', ''), ' ', '')) = $1 AND status = 'actif'`,
        churchId ? [matriculeNu, churchId] : [matriculeNu],
      );
      let member: (typeof candidats)[number] | undefined;
      if (candidats.length === 0) {
        await client.query("ROLLBACK");
        return reply.code(404).send({
          error: "not_found",
          message: "Aucun membre actif avec ce matricule. Vérifiez le matricule ou contactez votre église.",
        });
      }
      const concordants = candidats.filter(
        (m) => (m.email as string | null)?.toLowerCase() === emailNorm,
      );
      if (concordants.length === 1) {
        member = concordants[0];
      } else if (candidats.length === 1) {
        member = candidats[0];
      } else {
        await client.query("ROLLBACK");
        return reply.code(400).send({
          error: "ambiguous_matricule",
          message: "Plusieurs membres portent ce matricule. Vérifiez l'e-mail du membre ou contactez votre église.",
        });
      }

      if (member.user_id) {
        await client.query("ROLLBACK");
        return reply.code(409).send({
          error: "already_linked",
          message: "Ce membre est déjà lié à un compte.",
        });
      }
      const dejaLie = await client.query(
        `SELECT id FROM users WHERE member_id = $1`,
        [member.id],
      );
      if (dejaLie.rowCount && dejaLie.rowCount > 0) {
        await client.query("ROLLBACK");
        return reply.code(409).send({
          error: "already_linked",
          message: "Ce membre est déjà lié à un compte.",
        });
      }
      const emailPris = await client.query(
        `SELECT id FROM users WHERE lower(email) = $1`,
        [emailNorm],
      );
      if (emailPris.rowCount && emailPris.rowCount > 0) {
        await client.query("ROLLBACK");
        return reply.code(409).send({
          error: "email_taken",
          message: "Cet e-mail est déjà utilisé.",
        });
      }

      const passwordHash = await hashPassword(mot_de_passe);
      const { rows: userRows } = await client.query<{ id: string }>(
        `INSERT INTO users (email, password_hash, full_name)
         VALUES ($1, $2, $3) RETURNING id`,
        [emailNorm, passwordHash, member.full_name as string],
      );
      const userId = userRows[0].id;

      const emailConcorde =
        (member.email as string | null)?.toLowerCase() === emailNorm;

      if (emailConcorde) {
        // Liaison immédiate : compte + appartenance + lien membre.
        await client.query(
          `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'membre')`,
          [userId, member.church_id],
        );
        await client.query(`UPDATE users SET member_id = $2 WHERE id = $1`, [
          userId,
          member.id,
        ]);
        await client.query(`UPDATE members SET user_id = $2 WHERE id = $1`, [
          member.id,
          userId,
        ]);
        await auditLog(client, {
          churchId: member.church_id as string,
          userId,
          action: "fidele.inscrit_lie",
          details: { member_id: member.id },
        });
        await client.query("COMMIT");

        // Connexion immédiate (même réponse que /auth/login).
        const result = await login(db, { email: emailNorm, password: mot_de_passe, channel });
        if (!result.ok) {
          return reply.code(500).send({
            error: "internal",
            message: "Compte créé, mais la connexion a échoué. Essayez de vous connecter.",
          });
        }
        return reply.code(201).send({
          lie: true,
          message: "Compte créé et lié à votre fiche membre. Bienvenue !",
          token: result.token,
          user: result.user,
          church: result.church,
          eglises: result.eglises,
        });
      }

      // E-mail différent de la fiche : demande en attente de validation.
      const { rows: demandeRows } = await client.query<{ id: string }>(
        `INSERT INTO member_link_requests (member_id, user_id)
         VALUES ($1, $2) RETURNING id`,
        [member.id, userId],
      );
      await auditLog(client, {
        churchId: member.church_id as string,
        userId,
        action: "fidele.demande_liaison",
        details: { member_id: member.id, demande_id: demandeRows[0].id },
      });
      await client.query("COMMIT");
      return reply.code(201).send({
        lie: false,
        demande_id: demandeRows[0].id,
        message:
          "Demande envoyée, l'administrateur de ton église doit la valider. Tu pourras te connecter ensuite.",
      });
    } catch (e) {
      await client.query("ROLLBACK").catch(() => undefined);
      return dbError(reply, e);
    } finally {
      client.release();
    }
  });

  // -- Inscription membre par code fidèle, sans validation : le code
  // fait foi (décision de Bouf, 11 nov. 2026). Matricule attribué
  // automatiquement, fiche membre et carte créées tout de suite, compte
  // lié immédiatement et session démarrée. L'ancien parcours par
  // matricule (/auth/inscription-fidele, ci-dessous) est conservé pour
  // les membres déjà fichés, mais l'écran n'y renvoie plus.
  app.post("/auth/inscription-par-code", async (req, reply) => {
    try {
      const result = await inscriptionMembreParCode(db, req.body);
      if (!result.ok) {
        const status =
          result.reason === "invalid_input"
            ? 400
            : result.reason === "invalid_code"
              ? 404
              : 409;
        const message =
          result.reason === "invalid_input"
            ? "Nom, e-mail, téléphone, mot de passe (8 caractères minimum) ou code fidèle invalide."
            : result.reason === "invalid_code"
              ? "Code fidèle invalide. Vérifiez le code fidèle donné par votre église."
              : "Cet e-mail est déjà utilisé.";
        return reply.code(status).send({ error: result.reason, message });
      }
      return reply.code(201).send({
        lie: true,
        matricule: result.matricule,
        message: `Compte créé, votre matricule est ${result.matricule}. Bienvenue !`,
        token: result.token,
        user: result.user,
        church: result.church,
        eglises: result.eglises,
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Mon profil : utilisateur + église active + rôle + fiche membre liée.
  app.get("/moi", { preHandler: [requireAuth(db)] }, async (req, reply) => {
    try {
      const { rows } = await db.query(
        `SELECT u.id, u.full_name, u.email, u.phone, u.member_id,
                m.matricule,
                c.id AS church_id, c.code, c.code_fidele, c.name, c.parent_church_id, c.city,
                c.country, c.phone AS church_phone, c.email AS church_email,
                c.status, c.logo_url, c.couleur_principale, c.devise,
                c.fuseau_horaire, c.description, c.horaires_cultes
           FROM users u
           LEFT JOIN members m ON m.id = u.member_id
           JOIN churches c ON c.id = $2
          WHERE u.id = $1`,
        [req.session.userId, req.session.churchId],
      );
      const r = rows[0];
      if (!r) return reply.code(404).send({ error: "not_found", message: "Profil introuvable." });
      return reply.send({
        user: {
          id: r.id,
          full_name: r.full_name,
          email: r.email,
          phone: r.phone,
          member_id: r.member_id,
          matricule: r.matricule,
        },
        church: {
          id: r.church_id,
          code: r.code,
          code_fidele: r.code_fidele,
          name: r.name,
          parent_church_id: r.parent_church_id,
          city: r.city,
          country: r.country,
          phone: r.church_phone,
          email: r.church_email,
          status: r.status,
          logo_url: r.logo_url,
          couleur_principale: r.couleur_principale,
          devise: r.devise,
          fuseau_horaire: r.fuseau_horaire,
          description: r.description,
          horaires_cultes: r.horaires_cultes,
        },
        role: req.session.role,
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Demandes de liaison en attente de mon église (admin seulement).
  app.get(
    "/membres/demandes-liaison",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT r.id, r.status, r.created_at,
                  m.id AS member_id, m.matricule, m.full_name AS membre_nom,
                  m.email AS membre_email,
                  u.id AS user_id, u.email AS user_email, u.full_name AS user_nom
             FROM member_link_requests r
             JOIN members m ON m.id = r.member_id
             JOIN users u ON u.id = r.user_id
            WHERE m.church_id = $1 AND r.status = 'en_attente'
            ORDER BY r.created_at ASC`,
          [req.session.churchId],
        );
        return reply.send({ demandes: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Valider / refuser une demande de liaison (admin seulement).
  async function deciderDemande(
    req: FastifyRequest,
    reply: FastifyReply,
    accepter: boolean,
  ) {
    const id = (req.params as { id: string }).id;
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      const { rows } = await client.query(
        `SELECT r.id, r.status, r.member_id, r.user_id, m.church_id
           FROM member_link_requests r
           JOIN members m ON m.id = r.member_id
          WHERE r.id = $1 AND m.church_id = $2`,
        [id, req.session.churchId],
      );
      const demande = rows[0];
      if (!demande) {
        await client.query("ROLLBACK");
        return reply.code(404).send({
          error: "not_found",
          message: "Demande introuvable dans votre église.",
        });
      }
      if (demande.status !== "en_attente") {
        await client.query("ROLLBACK");
        return reply.code(400).send({
          error: "already_decided",
          message: "Cette demande a déjà été décidée.",
        });
      }
      if (accepter) {
        const dejaLie = await client.query(
          `SELECT id FROM users WHERE member_id = $1`,
          [demande.member_id],
        );
        if (dejaLie.rowCount && dejaLie.rowCount > 0) {
          await client.query("ROLLBACK");
          return reply.code(409).send({
            error: "already_linked",
            message: "Ce membre est déjà lié à un autre compte.",
          });
        }
        await client.query(
          `UPDATE member_link_requests
              SET status = 'valide', decided_by = $2, decided_at = now()
            WHERE id = $1`,
          [id, req.session.userId],
        );
        await client.query(
          `INSERT INTO church_users (user_id, church_id, role)
           VALUES ($1, $2, 'membre')
           ON CONFLICT (user_id, church_id) DO NOTHING`,
          [demande.user_id, demande.church_id],
        );
        await client.query(`UPDATE users SET member_id = $2 WHERE id = $1`, [
          demande.user_id,
          demande.member_id,
        ]);
        await client.query(`UPDATE members SET user_id = $2 WHERE id = $1`, [
          demande.member_id,
          demande.user_id,
        ]);
      } else {
        await client.query(
          `UPDATE member_link_requests
              SET status = 'refuse', decided_by = $2, decided_at = now()
            WHERE id = $1`,
          [id, req.session.userId],
        );
      }
      await auditLog(client, {
        churchId: req.session.churchId,
        userId: req.session.userId,
        action: accepter ? "fidele.liaison_validee" : "fidele.liaison_refusee",
        details: { demande_id: id, member_id: demande.member_id },
      });
      await client.query("COMMIT");
      return reply.send({
        id,
        status: accepter ? "valide" : "refuse",
        message: accepter
          ? "Liaison validée : le fidèle peut se connecter."
          : "Demande refusée.",
      });
    } catch (e) {
      await client.query("ROLLBACK").catch(() => undefined);
      return dbError(reply, e);
    } finally {
      client.release();
    }
  }

  app.post(
    "/membres/demandes-liaison/:id/valider",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    (req, reply) => deciderDemande(req, reply, true),
  );
  app.post(
    "/membres/demandes-liaison/:id/refuser",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    (req, reply) => deciderDemande(req, reply, false),
  );

  // -- Lectures fidèle (rôle membre, SON église, SES données).
  app.get(
    "/moi/annonces",
    { preHandler: [requireAuth(db), requireRole("membre")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `WITH RECURSIVE ancetres AS (
             SELECT id, parent_church_id FROM churches WHERE id = $1
             UNION ALL
             SELECT c.id, c.parent_church_id
               FROM churches c
               JOIN ancetres a ON c.id = a.parent_church_id
           )
           SELECT an.id, an.title, an.body, an.broadcast, an.created_at,
                  an.church_id, ch.name AS eglise_nom
             FROM announcements an
             JOIN churches ch ON ch.id = an.church_id
            WHERE an.church_id = $1
               OR (an.church_id IN (SELECT id FROM ancetres) AND an.broadcast = TRUE)
            ORDER BY an.created_at DESC
            LIMIT 100`,
          [req.session.churchId],
        );
        return reply.send({ annonces: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/moi/cultes",
    { preHandler: [requireAuth(db), requireRole("membre")] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, church_id, culte_type_id, titre, date_heure, lieu,
                  orateur, theme, created_at
             FROM cultes
            WHERE church_id = $1 AND date_heure >= now()
            ORDER BY date_heure ASC
            LIMIT 50`,
          [req.session.churchId],
        );
        return reply.send({ cultes: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/moi/presences",
    { preHandler: [requireAuth(db), requireRole("membre")] },
    async (req, reply) => {
      try {
        const memberId = await memberIdDe(req.session.userId);
        if (!memberId) {
          return reply.code(404).send({
            error: "not_found",
            message: "Aucun membre lié à ce compte.",
          });
        }
        const { rows } = await db.query(
          `SELECT p.id, p.event_id, p.culte_id, p.member_id, p.statut, p.mode,
                  p.pointe_at, m.full_name AS membre_nom,
                  c.titre AS culte_titre, e.title AS evenement_titre
             FROM presences p
             JOIN members m ON m.id = p.member_id
             LEFT JOIN cultes c ON c.id = p.culte_id
             LEFT JOIN events e ON e.id = p.event_id
            WHERE p.member_id = $1 AND p.church_id = $2
            ORDER BY p.pointe_at DESC
            LIMIT 100`,
          [memberId, req.session.churchId],
        );
        return reply.send({ presences: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.get(
    "/moi/contributions",
    { preHandler: [requireAuth(db), requireRole("membre")] },
    async (req, reply) => {
      try {
        const memberId = await memberIdDe(req.session.userId);
        if (!memberId) {
          return reply.code(404).send({
            error: "not_found",
            message: "Aucun membre lié à ce compte.",
          });
        }
        const { rows } = await db.query(
          `SELECT co.id, co.type, co.amount_fcfa, co.payment_method,
                  co.payment_ref, co.status, co.note, co.member_id,
                  co.created_at, m.full_name AS membre_nom,
                  m.matricule AS membre_matricule
             FROM contributions co
             LEFT JOIN members m ON m.id = co.member_id
            WHERE co.member_id = $1 AND co.church_id = $2
            ORDER BY co.created_at DESC
            LIMIT 100`,
          [memberId, req.session.churchId],
        );
        return reply.send({ contributions: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Ma carte de membre : fiche membre + église (réutilise la carte
  // existante côté Flutter — MemberDetailScreen — sans la reconstruire).
  app.get(
    "/moi/carte",
    { preHandler: [requireAuth(db), requireRole("membre")] },
    async (req, reply) => {
      try {
        const memberId = await memberIdDe(req.session.userId);
        if (!memberId) {
          return reply.code(404).send({
            error: "not_found",
            message: "Aucun membre lié à ce compte.",
          });
        }
        const { rows: memberRows } = await db.query(
          `SELECT id, church_id, matricule, full_name, phone, email,
                  birth_date, department, fonction, poste, cell_group, status, created_at
             FROM members WHERE id = $1 AND church_id = $2`,
          [memberId, req.session.churchId],
        );
        const member = memberRows[0];
        if (!member) {
          return reply.code(404).send({ error: "not_found", message: "Membre introuvable." });
        }
        const { rows: churchRows } = await db.query(
          `SELECT id, code, name, parent_church_id, city, country, phone,
                  email, status, logo_url, couleur_principale, devise,
                  fuseau_horaire, description, horaires_cultes
             FROM churches WHERE id = $1`,
          [req.session.churchId],
        );
        return reply.send({ member, church: churchRows[0] });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  async function memberIdDe(userId: string): Promise<string | null> {
    const { rows } = await db.query<{ member_id: string | null }>(
      `SELECT member_id FROM users WHERE id = $1`,
      [userId],
    );
    return rows[0]?.member_id ?? null;
  }
}
