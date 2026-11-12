import { config } from "dotenv";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// Charge server/.env (à la racine de server/)
config({ path: join(dirname(fileURLToPath(import.meta.url)), "..", ".env") });

import Fastify from "fastify";
import cors from "@fastify/cors";
import type { Pool } from "pg";
import { getDb } from "./db.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerMotDePasseRoutes } from "./routes/mot_de_passe.js";
import { registerFideleRoutes } from "./routes/fidele.js";
import { registerEglisesRoutes } from "./routes/eglises.js";
import { registerRattachementsRoutes } from "./routes/rattachements.js";
import { registerMembresRoutes } from "./routes/membres.js";
import { registerMembresComplementRoutes } from "./routes/membres_complement.js";
import { registerContributionsRoutes } from "./routes/contributions.js";
import { registerRapportsRoutes } from "./routes/rapports.js";
import { registerPlateformeRoutes } from "./routes/plateforme.js";
import { registerAnnoncesRoutes } from "./routes/annonces.js";
import { registerCultesRoutes } from "./routes/cultes.js";
import { registerPresencesRoutes } from "./routes/presences.js";
import { registerFinancesRoutes } from "./routes/finances.js";
import { registerPrieresRoutes } from "./routes/prieres.js";
import { registerPastoralRoutes } from "./routes/pastoral.js";
import { registerServiteursRoutes } from "./routes/serviteurs.js";
import { registerEnfantsRoutes } from "./routes/enfants.js";
import { registerMediasRoutes } from "./routes/medias.js";
import { registerBiensRoutes } from "./routes/biens.js";
import { registerStatsRoutes } from "./routes/stats.js";
import { registerParametresRoutes } from "./routes/parametres.js";
import { registerProfilEgliseRoutes } from "./routes/profil_eglise.js";
import { registerPaiementsRoutes } from "./routes/paiements.js";
import { registerTransfertsRoutes } from "./routes/transferts.js";
import { registerCodesTutelleRoutes } from "./routes/codes_tutelle.js";
import { registerAnnexesRoutes } from "./routes/annexes.js";
import { registerCampagnesRoutes } from "./routes/campagnes.js";
import { registerAttestationsRoutes } from "./routes/attestations.js";
import { registerNettoyageTestRoutes } from "./routes/nettoyage_test.js";
import { registerImportMembresRoutes } from "./routes/import_membres.js";

export function buildApp(db: Pool) {
  const app = Fastify({ logger: true });

  // CORS : le site web et l'API sont sur deux origines différentes, sans
  // ces en-têtes le navigateur bloque chaque appel, dont POST /auth/login
  // (« ClientException: Load failed »). Authentification par jeton Bearer,
  // pas de cookie, donc credentials: false. Seules les origines listées
  // ici et localhost (développement local) sont autorisées.
  const ORIGINES_AUTORISEES = new Set([
    "https://e-system-church-web.onrender.com",
  ]);
  app.register(cors, {
    origin: (origin, cb) => {
      if (origin === undefined) return cb(null, true); // curl, mobile, tests
      if (ORIGINES_AUTORISEES.has(origin)) return cb(null, true);
      try {
        const url = new URL(origin);
        if (
          (url.hostname === "localhost" || url.hostname === "127.0.0.1") &&
          (url.protocol === "http:" || url.protocol === "https:")
        ) {
          return cb(null, true);
        }
      } catch {
        // Origine invalide : refusée.
      }
      return cb(null, false);
    },
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
    credentials: false,
  });

  app.get("/sante", async () => ({
    status: "ok",
    service: "e-system-church-api",
    time: new Date().toISOString(),
  }));

  // Corps JSON vide toléré : certains appels POST n'ont pas de corps (ex.
  // accepter ou refuser un rattachement) ; le client envoyait
  // `Content-Type: application/json` avec un corps vide, et le parseur
  // par défaut de Fastify rejette ce cas (« Body cannot be empty when
  // content-type is set to 'application/json' »). Un corps vide vaut {}.
  // Les anciennes versions de l'application, déjà installées, envoient
  // encore ce cas : la tolérance côté serveur les répare sans mise à jour.
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (req, body, done) => {
      const text = typeof body === "string" ? body : body.toString();
      if (text === "") return done(null, {});
      try {
        done(null, JSON.parse(text));
      } catch (e) {
        const err = e as Error & { statusCode?: number };
        err.statusCode = 400;
        done(err, undefined);
      }
    },
  );

  registerAuthRoutes(app, db);
  registerMotDePasseRoutes(app, db);
  registerFideleRoutes(app, db);
  registerEglisesRoutes(app, db);
  registerRattachementsRoutes(app, db);
  registerMembresRoutes(app, db);
  registerMembresComplementRoutes(app, db);
  registerContributionsRoutes(app, db);
  registerRapportsRoutes(app, db);
  registerPlateformeRoutes(app, db);
  registerAnnoncesRoutes(app, db);
  registerCultesRoutes(app, db);
  registerPresencesRoutes(app, db);
  registerFinancesRoutes(app, db);
  registerPrieresRoutes(app, db);
  registerPastoralRoutes(app, db);
  registerServiteursRoutes(app, db);
  registerEnfantsRoutes(app, db);
  registerMediasRoutes(app, db);
  registerBiensRoutes(app, db);
  registerStatsRoutes(app, db);
  registerParametresRoutes(app, db);
  registerProfilEgliseRoutes(app, db);
  registerPaiementsRoutes(app, db);
  registerTransfertsRoutes(app, db);
  registerCodesTutelleRoutes(app, db);
  registerAnnexesRoutes(app, db);
  registerCampagnesRoutes(app, db);
  registerAttestationsRoutes(app, db);
  registerNettoyageTestRoutes(app, db);
  registerImportMembresRoutes(app, db);

  app.setNotFoundHandler((_req, reply) => {
    reply.code(404).send({ error: "not_found", message: "Route inconnue." });
  });

  return app;
}

// Ne démarre le serveur que si ce fichier est le point d'entrée.
const isEntryPoint =
  process.argv[1] !== undefined &&
  fileURLToPath(import.meta.url) === process.argv[1];
if (isEntryPoint) {
  const db = getDb();
  const app = buildApp(db);
  const port = Number(process.env.PORT ?? 3000);
  app.listen({ port, host: "0.0.0.0" }).catch((err) => {
    app.log.error(err);
    process.exit(1);
  });
}
