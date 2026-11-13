import { randomBytes } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog, issueTokenForChurch, rotateRefreshTokenForChurch } from "../auth.js";
import { invalidInput } from "../crud.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Module 13 — Identité visuelle, présentation et simplicité.
 *
 * POST  /eglises/:id/logo        — téléversement du logo (PNG/JPG, ≤ 2 Mo),
 *                                   stocké côté serveur sous server/uploads/logos/.
 * GET   /logos/:fichier          — service du fichier logo (public).
 * GET   /eglises/:code/presentation — page publique de l'église (par code unique).
 * PATCH /eglises/:id/profil      — nom, description, horaires, contacts, devise…
 *                                  (le code ESC-… ne change jamais).
 * POST  /auth/eglise-active      — changement d'église active (sélecteur).
 */

const LOGOS_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "uploads", "logos");
const MAX_LOGO_BYTES = 2 * 1024 * 1024; // 2 Mo

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const JPG_MAGIC = Buffer.from([0xff, 0xd8, 0xff]);

function detectImage(buffer: Buffer): "png" | "jpg" | null {
  if (buffer.length >= 8 && buffer.subarray(0, 8).equals(PNG_MAGIC)) return "png";
  if (buffer.length >= 3 && buffer.subarray(0, 3).equals(JPG_MAGIC)) return "jpg";
  return null;
}

const logoSchema = z.object({
  image_base64: z.string().min(100).max(4 * 1024 * 1024),
  filename: z.string().max(120).optional(),
});

const horaireSchema = z.object({
  jour: z.string().min(2).max(30),
  heure: z.string().min(2).max(20),
  titre: z.string().max(120).optional(),
});

const profilSchema = z.object({
  // Nom de l'église : corrigeable par l'admin après l'inscription (le code
  // ESC-… ne change jamais : il n'est pas dans ce schéma).
  name: z.string().min(2).max(200).optional(),
  description: z.string().max(2000).optional(),
  horaires_cultes: z.array(horaireSchema).max(20).optional(),
  couleur_principale: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/, "Couleur au format hexadécimal (#RRVVBB).")
    .optional(),
  devise: z.string().trim().toUpperCase().regex(/^[A-Z]{3,4}$/, "Devise : code de 3 ou 4 lettres (FCFA, XOF, EUR, USD…).").optional(),
  fuseau_horaire: z.string().min(3).max(60).optional(),
  logo_url: z.string().url().max(500).optional(),
  // Bannière de l'église (migration 018) : emplacement seulement, fournie
  // par l'église, jamais inventée. URL externe ou /bannieres/ servi plus tard.
  banniere_url: z.string().url().max(500).optional(),
  address: z.string().max(300).optional(),
  phone: z.string().min(8).max(30).optional(),
  email: z.string().email().max(254).optional(),
  city: z.string().min(2).max(120).optional(),
});

const egliseActiveSchema = z.object({
  church_id: z.string().uuid(),
  channel: z.enum(["web", "mobile"]).default("mobile"),
  refresh_token: z.string().min(1).max(256).optional(),
});

export function registerProfilEgliseRoutes(app: FastifyInstance, db: Pool) {
  // -- Téléversement du logo de MON église (admin seulement). ---------------
  app.post(
    "/eglises/:id/logo",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const churchId = (req.params as { id: string }).id;
      if (churchId !== req.session.churchId) {
        return reply.code(403).send({
          error: "forbidden",
          message: "On ne modifie le logo que de sa propre église.",
        });
      }
      const parsed = logoSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      try {
        const buffer = Buffer.from(parsed.data.image_base64, "base64");
        if (buffer.length === 0 || buffer.length > MAX_LOGO_BYTES) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Image invalide ou trop lourde (2 Mo maximum).",
          });
        }
        const ext = detectImage(buffer);
        if (!ext) {
          return reply.code(400).send({
            error: "invalid_input",
            message: "Image non reconnue : PNG ou JPG uniquement.",
          });
        }
        await mkdir(LOGOS_DIR, { recursive: true });
        const filename = `${churchId}-${randomBytes(4).toString("hex")}.${ext}`;
        await writeFile(join(LOGOS_DIR, filename), buffer);
        const logoUrl = `/logos/${filename}`;
        await db.query(`UPDATE churches SET logo_url = $2 WHERE id = $1`, [churchId, logoUrl]);
        await auditLog(db, {
          churchId,
          userId: req.session.userId,
          action: "eglise.logo_televerse",
          details: { logo_url: logoUrl, taille_octets: buffer.length },
        });
        return reply.send({ logo_url: logoUrl });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Service des logos (public ; nom de fichier nettoyé contre les
  //    traversées de chemin). ----------------------------------------------
  app.get("/logos/:fichier", async (req, reply) => {
    const fichier = (req.params as { fichier: string }).fichier;
    if (fichier !== basename(fichier) || !/^[A-Za-z0-9._-]+$/.test(fichier)) {
      return reply.code(400).send({ error: "invalid_input", message: "Nom de fichier invalide." });
    }
    try {
      const buffer = await readFile(join(LOGOS_DIR, fichier));
      const type = extname(fichier).toLowerCase() === ".png" ? "image/png" : "image/jpeg";
      return reply.type(type).send(buffer);
    } catch {
      return reply.code(404).send({ error: "not_found", message: "Logo introuvable." });
    }
  });

  // -- Présentation publique d'une église, par son code unique. -------------
  app.get("/eglises/:code/presentation", async (req, reply) => {
    const code = (req.params as { code: string }).code;
    try {
      const { rows } = await db.query(
        `SELECT id, code, name, city, country, address, phone, email, status,
                logo_url, banniere_url, couleur_principale, devise, fuseau_horaire,
                description, horaires_cultes
           FROM churches WHERE code = $1`,
        [code],
      );
      if (rows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
      }
      const eglise = rows[0];
      const { rows: pasteurRows } = await db.query(
        `SELECT u.full_name FROM church_users cu
           JOIN users u ON u.id = cu.user_id
          WHERE cu.church_id = $1 AND cu.role = 'admin_eglise'
          ORDER BY cu.created_at ASC LIMIT 1`,
        [eglise.id],
      );
      const { rows: antennes } = await db.query(
        `SELECT id, code, name, city, logo_url, couleur_principale
           FROM churches
          WHERE parent_church_id = $1 AND status = 'active'
          ORDER BY name ASC`,
        [eglise.id],
      );
      return reply.send({
        eglise,
        pasteur_principal: pasteurRows[0]?.full_name ?? null,
        antennes,
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Mise à jour du profil d'une église : la sienne, une de ses annexes
  //    directes (mère), ou n'importe quelle annexe (super admin). Le code
  //    ESC-… ne change jamais. ---------------------------------------------
  app.patch(
    "/eglises/:id/profil",
    { preHandler: [requireAuth(db), requireRole("admin_eglise", "super_admin")] },
    async (req, reply) => {
      const churchId = (req.params as { id: string }).id;
      const { rows: cibleRows } = await db.query<{ parent_church_id: string | null }>(
        `SELECT parent_church_id FROM churches WHERE id = $1`,
        [churchId],
      );
      if (cibleRows.length === 0) {
        return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
      }
      const parent = cibleRows[0].parent_church_id;
      const autorise =
        (req.session.role === "admin_eglise" && churchId === req.session.churchId) ||
        (req.session.role === "admin_eglise" && parent === req.session.churchId) ||
        (req.session.role === "super_admin" && parent !== null);
      if (!autorise) {
        return reply.code(403).send({
          error: "forbidden",
          message: "On ne modifie que le profil de sa propre église ou d'une de ses annexes directes.",
        });
      }
      const parsed = profilSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data as Record<string, unknown>;
      const columns = [
        "name",
        "description",
        "horaires_cultes",
        "couleur_principale",
        "devise",
        "fuseau_horaire",
        "logo_url",
        "banniere_url",
        "address",
        "phone",
        "email",
        "city",
      ];
      const keys = columns.filter((c) => data[c] !== undefined);
      if (keys.length === 0) {
        return reply.code(400).send({ error: "invalid_input", message: "Rien à modifier." });
      }
      try {
        const sets = keys.map((c, i) => `${c} = $${i + 2}`).join(", ");
        const values: unknown[] = [churchId, ...keys.map((c) => data[c])];
        const { rows } = await db.query(
          `UPDATE churches SET ${sets} WHERE id = $1 RETURNING
             id, code, name, city, country, address, phone, email, status,
             logo_url, banniere_url, couleur_principale, devise, fuseau_horaire,
             description, horaires_cultes`,
          values,
        );
        if (rows.length === 0) {
          return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        }
        await auditLog(db, {
          churchId,
          userId: req.session.userId,
          action: "eglise.profil_modifie",
          details: { champs: keys },
        });
        return reply.send(rows[0]);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Changement d'église active (sélecteur d'église). ----------------------
  app.post("/auth/eglise-active", { preHandler: [requireAuth(db)] }, async (req, reply) => {
    const parsed = egliseActiveSchema.safeParse(req.body);
    if (!parsed.success) {
      invalidInput(reply, parsed.error);
      return;
    }
    try {
      const result = await issueTokenForChurch(
        db,
        req.session.userId,
        parsed.data.church_id,
        parsed.data.channel,
      );
      if (!result.ok) {
        return reply.code(400).send({
          error: "invalid_church",
          message: "Cette église ne fait pas partie de vos églises.",
        });
      }
      // Le jeton de rafraîchissement suit la nouvelle église active :
      // sans rotation, un rafraîchissement ultérieur réémettrait un JWT
      // pour l'ancienne église.
      const refreshToken = parsed.data.refresh_token
        ? await rotateRefreshTokenForChurch(
            db,
            parsed.data.refresh_token,
            req.session.userId,
            parsed.data.church_id,
          )
        : null;
      return reply.send({
        token: result.token,
        church: result.church,
        ...(refreshToken ? { refresh_token: refreshToken } : {}),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });
}
