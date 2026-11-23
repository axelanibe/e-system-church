import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import { auditLog } from "../auth.js";
import { invalidInput } from "../crud.js";
import {
  identiteInstitutionnelle,
  synchroniserParametresIdentite,
  type ChampsParametresIdentite,
} from "../identite.js";
import { dbError, estAnnexe, requireAuth, requireRole } from "../middleware.js";

/**
 * Module — Identité institutionnelle (Phase 2).
 *
 * GET   /identite — identité résolue de mon église (héritée de la mère
 *                   si je suis une annexe et que la mère a publié).
 * PATCH /identite — église mère seulement : modifie son identité
 *                   (nom, sigle, slogan, logo, couleurs, contacts,
 *                   devise, fuseau, enregistrement, documents, statut).
 *                   Les deux magasins restent synchronisés pendant la
 *                   transition (`churches` en lecture seule transitoire).
 */

const READ_ROLES = ["admin_eglise", "tresorier", "responsable_culte"];

const identiteSchema = z.object({
  nom_officiel: z.string().min(2).max(200).optional(),
  sigle: z.string().max(20).optional(),
  slogan: z.string().max(200).optional(),
  logo_url: z.string().url().max(500).optional(),
  couleur_principale: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/, "Couleur au format hexadécimal (#RRVVBB).")
    .optional(),
  couleurs: z.record(z.unknown()).optional(),
  adresse: z.string().max(300).optional(),
  ville: z.string().max(120).optional(),
  pays: z.string().max(120).optional(),
  telephone: z.string().min(8).max(30).optional(),
  email: z.string().email().max(254).optional(),
  site_web: z.string().url().max(500).optional(),
  devise: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{3,4}$/, "Devise : code de 3 ou 4 lettres (FCFA, XOF, EUR, USD…).")
    .optional(),
  fuseau_horaire: z.string().max(60).optional(),
  numero_enregistrement: z.string().max(100).optional(),
  ncc: z.string().max(50).optional(),
  infos_legales: z.record(z.unknown()).optional(),
  parametres_documents: z.record(z.unknown()).optional(),
  description: z.string().max(2000).optional(),
  statut: z.enum(["brouillon", "publié"]).optional(),
});

const MESSAGE_ANNEXE =
  "Seule l’église mère modifie son identité institutionnelle.";

export function registerIdentiteRoutes(app: FastifyInstance, db: Pool) {
  app.get(
    "/identite",
    { preHandler: [requireAuth(db), requireRole(...READ_ROLES)] },
    async (req, reply) => {
      try {
        const identite = await identiteInstitutionnelle(db, req.session.churchId);
        if (!identite) {
          return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        }
        return reply.send(identite);
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  app.patch(
    "/identite",
    { preHandler: [requireAuth(db), requireRole("admin_eglise")] },
    async (req, reply) => {
      const parsed = identiteSchema.safeParse(req.body);
      if (!parsed.success) {
        invalidInput(reply, parsed.error);
        return;
      }
      const data = parsed.data;
      const champs = Object.keys(data) as (keyof typeof data)[];
      if (champs.length === 0) {
        return reply.code(400).send({ error: "invalid_input", message: "Rien à modifier." });
      }
      const client = await db.connect();
      try {
        await client.query("BEGIN");
        if (await estAnnexe(client, req.session.churchId)) {
          await client.query("ROLLBACK");
          return reply.code(403).send({ error: "forbidden", message: MESSAGE_ANNEXE });
        }
        // `churches` (lecture seule transitoire) : nom, pays, description,
        // couleur principale et logo y restent synchronisés.
        const eglisesMaj: Record<string, unknown> = {};
        if (data.nom_officiel !== undefined) eglisesMaj.name = data.nom_officiel;
        if (data.pays !== undefined) eglisesMaj.country = data.pays;
        if (data.description !== undefined) eglisesMaj.description = data.description;
        if (data.couleur_principale !== undefined) {
          eglisesMaj.couleur_principale = data.couleur_principale;
        }
        if (data.logo_url !== undefined) eglisesMaj.logo_url = data.logo_url;
        const clesEglises = Object.keys(eglisesMaj);
        if (clesEglises.length > 0) {
          const sets = clesEglises.map((c, i) => `${c} = $${i + 2}`).join(", ");
          await client.query(
            `UPDATE churches SET ${sets} WHERE id = $1`,
            [req.session.churchId, ...clesEglises.map((c) => eglisesMaj[c])],
          );
        }
        // `eglise_parametres` (source de référence) : le reste, avec
        // fusion de `couleurs.principale` quand une couleur est donnée.
        const parametresChamps: ChampsParametresIdentite = {};
        if (data.logo_url !== undefined) parametresChamps.logo_url = data.logo_url;
        if (data.couleur_principale !== undefined) {
          parametresChamps.couleurs = { principale: data.couleur_principale };
        }
        if (data.couleurs !== undefined) {
          parametresChamps.couleurs = {
            ...((parametresChamps.couleurs as Record<string, unknown> | undefined) ?? {}),
            ...(data.couleurs as Record<string, unknown>),
          };
        }
        for (const k of [
          "sigle",
          "slogan",
          "adresse",
          "ville",
          "telephone",
          "email",
          "site_web",
          "devise",
          "fuseau_horaire",
          "numero_enregistrement",
          "ncc",
          "infos_legales",
          "parametres_documents",
          "statut",
        ] as const) {
          if (data[k] !== undefined) parametresChamps[k] = data[k];
        }
        await synchroniserParametresIdentite(client, req.session.churchId, parametresChamps);
        await auditLog(client, {
          churchId: req.session.churchId,
          userId: req.session.userId,
          action: "identite.modifiee",
          details: { champs },
        });
        const identite = await identiteInstitutionnelle(client, req.session.churchId);
        await client.query("COMMIT");
        if (!identite) {
          return reply.code(404).send({ error: "not_found", message: "Église introuvable." });
        }
        return reply.send(identite);
      } catch (e) {
        await client.query("ROLLBACK").catch(() => undefined);
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );
}
