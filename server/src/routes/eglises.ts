import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog, generateChurchCode } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import { activerTousModules } from "./rattachements.js";

/**
 * Églises : création de sous-églises et arborescence.
 * POST /eglises        — l'admin de l'église de la session crée une sous-église
 *                        (il en devient l'admin initial).
 * GET  /eglises/arbre  — mon arborescence (mon église + descendances), avec les
 *                        effectifs et les demandes de rattachement en attente.
 */

const createEgliseSchema = z.object({
  name: z.string().min(2).max(200),
  city: z.string().min(2).max(120),
  phone: z.string().min(8).max(30).optional(),
  email: z.string().email().max(254).optional(),
});

interface TreeNode {
  id: string;
  code: string;
  name: string;
  city: string | null;
  status: string;
  parent_church_id: string | null;
  logo_url: string | null;
  couleur_principale: string | null;
  devise: string;
  fuseau_horaire: string;
  description: string | null;
  horaires_cultes: unknown;
  membres_actifs: number;
  children: TreeNode[];
}

export function registerEglisesRoutes(app: FastifyInstance, db: Pool) {
  app.post(
    "/eglises",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = createEgliseSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données de la sous-église invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const { name, city, phone, email } = parsed.data;
      const client = await db.connect();
      try {
        await client.query("BEGIN");

        let code = "";
        for (let attempt = 0; attempt < 5; attempt++) {
          code = generateChurchCode();
          const clash = await client.query(`SELECT 1 FROM churches WHERE code = $1`, [code]);
          if (clash.rowCount === 0) break;
          if (attempt === 4) throw new Error("Impossible de générer un code d'église unique.");
        }

        const { rows } = await client.query(
          `INSERT INTO churches (code, name, city, phone, email, parent_church_id, status)
           VALUES ($1, $2, $3, $4, $5, $6, 'active')
           RETURNING id, code, name, parent_church_id, city, status`,
          [code, name, city, phone ?? null, email ?? null, req.session.churchId],
        );
        const sub = rows[0];

        // Le créateur devient l'admin initial de la sous-église.
        await client.query(
          `INSERT INTO church_users (user_id, church_id, role)
           VALUES ($1, $2, 'admin_eglise')`,
          [req.session.userId, sub.id],
        );

        // Sous-église créée sous tutelle : tous ses modules sont activés
        // automatiquement, comme après un rattachement accepté.
        const modulesActives = await activerTousModules(client, sub.id);
        await auditLog(client, {
          churchId: sub.id,
          userId: req.session.userId,
          action: "modules.actives_tutelle",
          details: { par_mere: req.session.churchId, modules: modulesActives },
        });

        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "eglise.sous_eglise_creee",
          details: { sous_eglise_id: sub.id, sous_eglise_nom: sub.name },
        });

        await client.query("COMMIT");
        return reply.code(201).send(sub);
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  app.get("/eglises/arbre", { preHandler: [requireAuth(db)] }, async (req, reply) => {
    try {
      // Toute la descendance de l'église de la session (elle comprise).
      const { rows } = await db.query(
        `WITH RECURSIVE arbre AS (
           SELECT id, code, name, city, status, parent_church_id,
                  logo_url, couleur_principale, devise, fuseau_horaire,
                  description, horaires_cultes
             FROM churches WHERE id = $1
           UNION ALL
           SELECT c.id, c.code, c.name, c.city, c.status, c.parent_church_id,
                  c.logo_url, c.couleur_principale, c.devise, c.fuseau_horaire,
                  c.description, c.horaires_cultes
             FROM churches c
             JOIN arbre a ON c.parent_church_id = a.id
         )
         SELECT a.*,
                (SELECT count(*)::int FROM members m
                  WHERE m.church_id = a.id AND m.status = 'actif') AS membres_actifs
           FROM arbre a
          ORDER BY a.name`,
        [req.session.churchId],
      );

      // Reconstruction de l'arbre en mémoire.
      const byId = new Map<string, TreeNode>();
      for (const r of rows) {
        byId.set(r.id as string, {
          id: r.id as string,
          code: r.code as string,
          name: r.name as string,
          city: r.city as string | null,
          status: r.status as string,
          parent_church_id: r.parent_church_id as string | null,
          logo_url: r.logo_url as string | null,
          couleur_principale: r.couleur_principale as string | null,
          devise: r.devise as string,
          fuseau_horaire: r.fuseau_horaire as string,
          description: r.description as string | null,
          horaires_cultes: r.horaires_cultes as unknown,
          membres_actifs: r.membres_actifs as number,
          children: [],
        });
      }
      let root: TreeNode | null = null;
      for (const node of byId.values()) {
        if (node.parent_church_id && byId.has(node.parent_church_id)) {
          byId.get(node.parent_church_id)!.children.push(node);
        } else if (node.id === req.session.churchId) {
          root = node;
        }
      }
      if (!root) return reply.code(404).send({ error: "not_found", message: "Église introuvable." });

      // Demandes de rattachement en attente adressées à mon église (elle est la mère).
      const { rows: demandes } = await db.query(
        `SELECT r.id, r.status, r.created_at,
                c.id AS eglise_id, c.code AS eglise_code, c.name AS eglise_nom, c.city AS eglise_ville
           FROM rattachements r
           JOIN churches c ON c.id = r.church_id
          WHERE r.parent_church_id = $1 AND r.status = 'en_attente'
          ORDER BY r.created_at ASC`,
        [req.session.churchId],
      );

      return reply.send({ arbre: root, demandes_rattachement: demandes });
    } catch (e) {
      return dbError(reply, e);
    }
  });
}
