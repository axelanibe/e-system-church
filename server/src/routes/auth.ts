import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { login, registerChurch } from "../auth.js";
import { dbError, requireAuth } from "../middleware.js";

/**
 * Authentification + « moi ».
 * POST /auth/register — crée l'église + son admin (inscription libre : église ACTIVE).
 * POST /auth/login    — JWT bearer (église + rôle dans le jeton).
 * GET  /moi/eglise    — mon église active, mon rôle, mes autres églises.
 * GET  /moi/eglises   — mes églises, paginées + recherche (nom, code, ville) :
 *                        le sélecteur d'églises ne renvoie jamais 500 églises
 *                        d'un coup ; 50 par page par défaut, 100 au maximum.
 */
const mesEglisesQuerySchema = z.object({
  recherche: z.string().max(200).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limite: z.coerce.number().int().min(1).max(100).default(50),
});
export function registerAuthRoutes(app: FastifyInstance, db: Pool) {
  app.post("/auth/register", async (req, reply) => {
    try {
      const result = await registerChurch(db, req.body);
      if (!result.ok) {
        const status =
          result.reason === "invalid_input"
            ? 400
            : result.reason === "email_taken"
              ? 409
              : 400;
        const message =
          result.reason === "invalid_input"
            ? "Données d'inscription invalides."
            : result.reason === "email_taken"
              ? "Cet e-mail est déjà utilisé."
              : "Code d'invitation de l'église mère invalide.";
        return reply.code(status).send({ error: result.reason, message });
      }
      return reply.code(201).send({
        token: result.token,
        user: result.user,
        church: result.church,
        rattachement: result.rattachement,
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  app.post("/auth/login", async (req, reply) => {
    try {
      const result = await login(db, req.body);
      if (!result.ok) {
        const status =
          result.reason === "invalid_input"
            ? 400
            : result.reason === "locked"
              ? 423
              : result.reason === "invalid_church" || result.reason === "no_church"
                ? 400
                : 401;
        const message =
          result.reason === "invalid_input"
            ? "Données de connexion invalides."
            : result.reason === "locked"
              ? "Compte verrouillé 15 minutes après 5 échecs de connexion."
              : result.reason === "invalid_church"
                ? "Cette église ne fait pas partie de vos églises."
                : result.reason === "password_not_set"
                  ? "Pour vous connecter, initialisez d'abord votre mot de passe via le lien reçu."
                  : result.reason === "no_church"
                    ? "Votre demande de liaison n'a pas encore été validée par votre église."
                    : "E-mail ou mot de passe incorrect.";
        return reply.code(status).send({ error: result.reason, message });
      }
      return reply.send({
        token: result.token,
        user: result.user,
        church: result.church,
        eglises: result.eglises,
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  app.get("/moi/eglise", { preHandler: [requireAuth(db)] }, async (req, reply) => {
    try {
      const { rows: churchRows } = await db.query(
        `SELECT id, code, name, parent_church_id, city, country, phone, email, status,
                logo_url, couleur_principale, devise, fuseau_horaire,
                description, horaires_cultes
           FROM churches WHERE id = $1`,
        [req.session.churchId],
      );
      const church = churchRows[0];
      if (!church) return reply.code(404).send({ error: "not_found", message: "Église introuvable." });

      const { rows: userRows } = await db.query(
        `SELECT id, full_name, email, phone FROM users WHERE id = $1`,
        [req.session.userId],
      );

      // Toutes les églises de l'utilisateur (pour changer d'église active).
      const { rows: memberships } = await db.query(
        `SELECT cu.role, c.id, c.code, c.name, c.parent_church_id, c.status,
                c.logo_url, c.couleur_principale, c.devise, c.fuseau_horaire,
                c.description, c.horaires_cultes
           FROM church_users cu
           JOIN churches c ON c.id = cu.church_id
          WHERE cu.user_id = $1
          ORDER BY cu.created_at ASC`,
        [req.session.userId],
      );

      return reply.send({
        user: userRows[0],
        church,
        role: req.session.role,
        eglises: memberships.map((m) => ({
          role: m.role,
          church: {
            id: m.id,
            code: m.code,
            name: m.name,
            parent_church_id: m.parent_church_id,
            status: m.status,
            logo_url: m.logo_url,
            couleur_principale: m.couleur_principale,
            devise: m.devise,
            fuseau_horaire: m.fuseau_horaire,
            description: m.description,
            horaires_cultes: m.horaires_cultes,
          },
        })),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // Mes églises, paginées + recherche : l'écran « Mes églises » charge
  // 50 églises par page et ne demande la suite qu'au défilement. L'église
  // active est toujours en tête de la première page, pour être visible
  // sans recherche. `GET /moi/eglise` reste inchangé (compatibilité).
  app.get("/moi/eglises", { preHandler: [requireAuth(db)] }, async (req, reply) => {
    const parsed = mesEglisesQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Paramètres de recherche invalides.",
        details: parsed.error.issues.map((i) => i.message),
      });
    }
    const { recherche, page, limite } = parsed.data;
    const offset = (page - 1) * limite;
    try {
      const conditions = [`cu.user_id = $1`];
      const values: unknown[] = [req.session.userId];
      if (recherche != null && recherche.trim() !== '') {
        values.push(`%${recherche.trim()}%`);
        conditions.push(
          `(c.name ILIKE $${values.length} OR c.code ILIKE $${values.length} OR c.city ILIKE $${values.length})`,
        );
      }
      const where = `WHERE ${conditions.join(" AND ")}`;
      const total = await db.query<{ n: string }>(
        `SELECT count(*)::text AS n
           FROM church_users cu
           JOIN churches c ON c.id = cu.church_id
          ${where}`,
        values,
      );
      const { rows: memberships } = await db.query(
        `SELECT cu.role, c.id, c.code, c.name, c.parent_church_id, c.status,
                c.city, c.logo_url, c.couleur_principale, c.devise,
                c.fuseau_horaire, c.description, c.horaires_cultes
           FROM church_users cu
           JOIN churches c ON c.id = cu.church_id
          ${where}
          ORDER BY (c.id = $${values.length + 1}) DESC, cu.created_at ASC
          LIMIT $${values.length + 2} OFFSET $${values.length + 3}`,
        [...values, req.session.churchId, limite, offset],
      );
      return reply.send({
        eglises: memberships.map((m) => ({
          role: m.role,
          church: {
            id: m.id,
            code: m.code,
            name: m.name,
            parent_church_id: m.parent_church_id,
            status: m.status,
            logo_url: m.logo_url,
            couleur_principale: m.couleur_principale,
            devise: m.devise,
            fuseau_horaire: m.fuseau_horaire,
            description: m.description,
            horaires_cultes: m.horaires_cultes,
          },
        })),
        total: Number(total.rows[0]?.n ?? 0),
        page,
        limite,
        pages: Math.ceil(Number(total.rows[0]?.n ?? 0) / limite),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });
}
