import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { z } from "zod";
import {
  lireChapitre,
  listerLivres,
  listerVersions,
  livreExiste,
  normaliserVersion,
  rechercher,
} from "../bible.js";
import { READ_ALL } from "../crud.js";
import {
  chercherArticle,
  compterArticles,
  normaliserLangueDictionnaire,
  rechercherDictionnaire,
} from "../dictionnaire.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";
import {
  chercherStrong,
  normaliserNumeroStrong,
  rechercherStrong,
} from "../strong.js";

/**
 * Lecture de la Bible (Louis Segond 1910 et King James Version, domaine
 * public), concordance Strong et dictionnaire biblique.
 * Les textes sont servis depuis les JSON par livre, jamais inventés.
 * Lecture ouverte à tous les rôles (admin, trésorier, responsable de
 * culte, membre) : la Bible se lit, elle ne se modifie pas.
 * Sources et licences : server/src/data/bible/SOURCES.md.
 *
 * Versions : `?version=lsg1910` (défaut, français) ou `?version=kjv`
 * (anglais). Une version inconnue -> 400, jamais de remplacement
 * silencieux. La concordance Strong est un lexique consultable (aucun
 * lien mot à mot avec les versets : la LS1910 n'a pas de numéros Strong
 * natifs). Le dictionnaire suit la langue de la version biblique
 * (`?langue=fra` par défaut, `eng` pour l'anglais).
 */

const codeLivre = z
  .string()
  .regex(/^[A-Za-z0-9]{2,3}$/, "Code de livre invalide.")
  .transform((s) => s.toUpperCase());

const requeteVersion = z.object({ version: z.string().optional() });

/** Version demandée dans la requête, ou réponse 400 si inconnue. */
function versionDemandee(req: { query: unknown }, reply: any): string | null {
  const parsed = requeteVersion.safeParse(req.query);
  const version = normaliserVersion(parsed.success ? parsed.data.version : undefined);
  if (version === null) {
    reply.code(400).send({
      error: "invalid_input",
      message: "Version biblique inconnue (lsg1910 ou kjv).",
    });
    return null;
  }
  return version;
}

export function registerBibleRoutes(app: FastifyInstance, db: Pool): void {
  const lecture = [requireAuth(db), requireRole(...READ_ALL)];

  // -- Versions disponibles (id, nom, langue, livres, versets). -----------
  app.get("/bible/versions", { preHandler: lecture }, async (_req, reply) => {
    try {
      return reply.send({ versions: listerVersions() });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Canon : les 66 livres (code, nom, testament, chapitres). --------
  app.get("/bible/livres", { preHandler: lecture }, async (req, reply) => {
    const version = versionDemandee(req, reply);
    if (version === null) return;
    try {
      return reply.send({ version, livres: listerLivres(version) });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Un chapitre : ses versets numérotés. -----------------------------
  app.get(
    "/bible/livres/:code/chapitres/:chapitre",
    { preHandler: lecture },
    async (req, reply) => {
      const version = versionDemandee(req, reply);
      if (version === null) return;
      const params = z
        .object({ code: codeLivre, chapitre: z.coerce.number().int().min(1) })
        .safeParse(req.params);
      if (!params.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Livre ou chapitre invalide.",
        });
      }
      const { code, chapitre } = params.data;
      try {
        if (!livreExiste(code, version)) {
          return reply.code(404).send({
            error: "not_found",
            message: "Livre introuvable.",
          });
        }
        const versets = lireChapitre(code, chapitre, version);
        if (!versets) {
          return reply.code(404).send({
            error: "not_found",
            message: "Chapitre introuvable dans ce livre.",
          });
        }
        const meta = listerLivres(version).find((l) => l.code === code);
        return reply.send({
          version,
          livre: meta?.nom ?? code,
          code,
          chapitre,
          chapitres: meta?.chapitres ?? versets.length,
          versets,
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Recherche plein texte (insensible à la casse et aux accents). -----
  app.get("/bible/recherche", { preHandler: lecture }, async (req, reply) => {
    const version = versionDemandee(req, reply);
    if (version === null) return;
    const query = z
      .object({ q: z.string().min(2).max(200) })
      .safeParse(req.query);
    if (!query.success) {
      return reply.code(400).send({
        error: "invalid_input",
        message: "Recherche : au moins 2 caractères.",
      });
    }
    try {
      return reply.send({
        version,
        resultats: rechercher(query.data.q, version, 50),
      });
    } catch (e) {
      return dbError(reply, e);
    }
  });

  // -- Concordance Strong : recherche par mot ou par numéro. ------------
  // (Enregistrée avant /bible/strong/:numero : « recherche » ne doit
  // pas être lue comme un numéro.)
  app.get(
    "/bible/strong/recherche",
    { preHandler: lecture },
    async (req, reply) => {
      const query = z
        .object({ q: z.string().min(2).max(200) })
        .safeParse(req.query);
      if (!query.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Recherche : au moins 2 caractères.",
        });
      }
      try {
        return reply.send({ resultats: rechercherStrong(query.data.q, 50) });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Concordance Strong : une entrée par son numéro (G1234, H1234). ----
  app.get(
    "/bible/strong/:numero",
    { preHandler: lecture },
    async (req, reply) => {
      const params = z.object({ numero: z.string() }).safeParse(req.params);
      if (!params.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Numéro Strong invalide.",
        });
      }
      const numero = normaliserNumeroStrong(params.data.numero);
      if (numero === null) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Numéro Strong invalide (G1234 ou H1234).",
        });
      }
      try {
        const entree = chercherStrong(numero);
        if (!entree) {
          return reply.code(404).send({
            error: "not_found",
            message: "Entrée Strong introuvable.",
          });
        }
        return reply.send({ entree });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Dictionnaire : recherche par mot. ----------------------------------
  // (Enregistrée avant /bible/dictionnaire/:titre pour la même raison.)
  app.get(
    "/bible/dictionnaire/recherche",
    { preHandler: lecture },
    async (req, reply) => {
      const query = z
        .object({ q: z.string().min(2).max(200), langue: z.string().optional() })
        .safeParse(req.query);
      if (!query.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Recherche : au moins 2 caractères.",
        });
      }
      const langue = normaliserLangueDictionnaire(query.data.langue);
      if (langue === null) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Langue du dictionnaire inconnue (fra ou eng).",
        });
      }
      try {
        return reply.send({
          langue,
          articles: compterArticles(langue),
          resultats: rechercherDictionnaire(query.data.q, langue, 50),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Dictionnaire : un article par son titre exact. --------------------
  app.get(
    "/bible/dictionnaire/:titre",
    { preHandler: lecture },
    async (req, reply) => {
      const params = z.object({ titre: z.string().min(1) }).safeParse(req.params);
      if (!params.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Titre d'article invalide.",
        });
      }
      const query = z
        .object({ langue: z.string().optional() })
        .safeParse(req.query);
      const langue = normaliserLangueDictionnaire(
        query.success ? query.data.langue : undefined,
      );
      if (langue === null) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Langue du dictionnaire inconnue (fra ou eng).",
        });
      }
      try {
        const article = chercherArticle(params.data.titre, langue);
        if (!article) {
          return reply.code(404).send({
            error: "not_found",
            message: "Article introuvable.",
          });
        }
        return reply.send({ langue, article });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
