import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog, generateChurchCode, generateFideleCode } from "../auth.js";
import { dbError, estAnnexe, requireAuth, requireRole } from "../middleware.js";
import { seedPostesPrevisibles } from "../postes_previsibles.js";

/**
 * Églises : création de sous-églises et arborescence.
 * POST /eglises        — l'admin de l'église de la session crée une sous-église
 *                        (il en devient l'admin initial). Réservé aux églises
 *                        mères : une annexe ne peut pas avoir d'annexe (règle
 *                        du 11/11/2026, 403 `annexe_sans_annexe`).
 * GET  /eglises/arbre  — mon arborescence (mon église + descendances), avec les
 *                        effectifs et les demandes de rattachement en attente.
 * POST /eglises/moi/codes/regenerer — régénère le code de tutelle de mon
 *                        église (ESC-…, bouton « Régénérer » dans
 *                        « Mon église ») ; l'ancien code cesse de
 *                        fonctionner immédiatement. Le rattachement
 *                        résout le code au moment de l'usage : seul
 *                        l'usage futur de l'ancien code est affecté.
 *                        Attention : le code de tutelle est aussi la clé
 *                        de la présentation publique
 *                        (`GET /eglises/:code/presentation`) — un lien de
 *                        présentation partagé avec l'ancien code ne
 *                        fonctionne plus après régénération. Le code
 *                        fidèle (ESC-F-…), lui, ne se régénère jamais
 *                        (décision de Bouf, 13/11/2026).
 */

const createEgliseSchema = z.object({
  name: z.string().min(2).max(200),
  city: z.string().min(2).max(120),
  phone: z.string().min(8).max(30).optional(),
  email: z.string().email().max(254).optional(),
});

const regenererCodeSchema = z.object({
  // Seul le code de tutelle se régénère : le code fidèle (ESC-F-…),
  // largement partagé pour l'inscription des membres, reste fixe pour
  // toujours (décision de Bouf, 13/11/2026) — « fidele » répond 400.
  type: z.enum(["tutelle"]),
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
      // Seule une église mère crée une sous-église.
      if (await estAnnexe(db, req.session.churchId)) {
        return reply.code(403).send({
          error: "annexe_sans_annexe",
          message: "Une église annexe ne peut pas avoir d'église annexe.",
        });
      }
      const client = await db.connect();
      try {
        await client.query("BEGIN");

        // Deux codes uniques : tutelle (ESC-…) et fidèle (ESC-F-…).
        // 4 chiffres = 10 000 valeurs possibles : 50 tentatives.
        // Garantie de Bouf : un même nombre à 4 chiffres ne sert qu'une
        // seule fois, dans un seul rôle — le suffixe est vérifié entre
        // les deux colonnes `code` et `code_fidele` uniquement (les
        // matricules portent désormais leurs propres initiales + date de
        // naissance, M-LA-171268-01, et ne croisent plus les codes).
        let code = "";
        for (let attempt = 0; attempt < 50; attempt++) {
          code = generateChurchCode();
          const clash = await client.query(
            `SELECT 1 FROM churches WHERE right(code, 4) = $1 OR right(code_fidele, 4) = $1`,
            [code.slice(-4)],
          );
          if (clash.rowCount === 0) break;
          if (attempt === 49) throw new Error("Impossible de générer un code d'église unique.");
        }
        let codeFidele = "";
        for (let attempt = 0; attempt < 50; attempt++) {
          codeFidele = generateFideleCode();
          const clash = await client.query(
            `SELECT 1 FROM churches WHERE right(code, 4) = $1 OR right(code_fidele, 4) = $1`,
            [codeFidele.slice(-4)],
          );
          // Même nombre que le code de tutelle généré juste avant pour
          // cette église (pas encore inséré, donc invisible ci-dessus).
          if (clash.rowCount === 0 && codeFidele.slice(-4) !== code.slice(-4)) break;
          if (attempt === 49) throw new Error("Impossible de générer un code fidèle unique.");
        }

        const { rows } = await client.query(
          `INSERT INTO churches (code, code_fidele, name, city, phone, email, parent_church_id, status)
           VALUES ($1, $2, $3, $4, $5, $6, $7, 'active')
           RETURNING id, code, code_fidele, name, parent_church_id, city, status`,
          [code, codeFidele, name, city, phone ?? null, email ?? null, req.session.churchId],
        );
        const sub = rows[0];

        // Le créateur devient l'admin initial de la sous-église.
        await client.query(
          `INSERT INTO church_users (user_id, church_id, role)
           VALUES ($1, $2, 'admin_eglise')`,
          [req.session.userId, sub.id],
        );

        // Postes de dépense prévisibles, déjà prêts pour la trésorerie.
        await seedPostesPrevisibles(client, sub.id);

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

  // -- Régénération du code de tutelle de mon église ----------------------
  // Bouton « Régénérer » dans « Mon église » (code de tutelle
  // seulement : le code fidèle, largement partagé pour l'inscription
  // des membres, ne se régénère jamais — décision de Bouf, 13/11/2026).
  // Réutilise le générateur existant et sa boucle anti-collision
  // (50 tentatives, suffixe à 4 chiffres vérifié entre les deux colonnes
  // `code` et `code_fidele`, anciens codes 6 caractères inclus). La ligne
  // de l'église est verrouillée (FOR UPDATE) : deux régénérations
  // concurrentes de la même église ne peuvent pas produire le même code ;
  // la contrainte UNIQUE sur `code` reste le filet de sécurité.
  // Journalisé : le type seulement, JAMAIS les valeurs des
  // codes (ancien ou nouveau).
  app.post(
    "/eglises/moi/codes/regenerer",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = regenererCodeSchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Type de code invalide (seul le code de tutelle peut être régénéré).",
        });
      }
      const { type } = parsed.data;
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        const { rows: verrouillees } = await client.query<{
          id: string;
          code: string;
          code_fidele: string | null;
        }>(
          `SELECT id, code, code_fidele FROM churches WHERE id = $1 FOR UPDATE`,
          [req.session.churchId],
        );
        const courante = verrouillees[0];
        if (!courante) {
          await client.query("ROLLBACK");
          return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        }
        let nouveau = "";
        for (let attempt = 0; attempt < 50; attempt++) {
          nouveau = generateChurchCode();
          const clash = await client.query(
            `SELECT 1 FROM churches WHERE right(code, 4) = $1 OR right(code_fidele, 4) = $1`,
            [nouveau.slice(-4)],
          );
          // La requête couvre aussi cette église : le nouveau code diffère
          // donc de l'ancien code de tutelle et du code fidèle.
          if (clash.rowCount === 0) break;
          if (attempt === 49) throw new Error("Impossible de générer un code unique.");
        }
        const { rows } = await client.query(
          `UPDATE churches SET code = $1 WHERE id = $2
           RETURNING id, code, code_fidele`,
          [nouveau, req.session.churchId],
        );
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "eglise.code_regenere",
          details: { type },
        });
        await client.query("COMMIT");
        const maj = rows[0];
        return reply.send({
          id: maj.id as string,
          code: maj.code as string,
          code_fidele: maj.code_fidele as string | null,
          type,
          nouveau_code: nouveau,
        });
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
