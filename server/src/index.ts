import { config } from "dotenv";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// Charge server/.env (à la racine de server/)
config({ path: join(dirname(fileURLToPath(import.meta.url)), "..", ".env") });

import Fastify from "fastify";
import type { Pool } from "pg";
import { getDb } from "./db.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerEglisesRoutes } from "./routes/eglises.js";
import { registerRattachementsRoutes } from "./routes/rattachements.js";
import { registerTransfertsRoutes } from "./routes/transferts.js";
import { registerMembresRoutes } from "./routes/membres.js";
import { registerContributionsRoutes } from "./routes/contributions.js";
import { registerRapportsRoutes } from "./routes/rapports.js";
import { registerAnnoncesRoutes } from "./routes/annonces.js";

export function buildApp(db: Pool) {
  const app = Fastify({ logger: true });

  app.get("/sante", async () => ({
    status: "ok",
    service: "e-system-church-api",
    time: new Date().toISOString(),
  }));

  registerAuthRoutes(app, db);
  registerEglisesRoutes(app, db);
  registerRattachementsRoutes(app, db);
  registerTransfertsRoutes(app, db);
  registerMembresRoutes(app, db);
  registerContributionsRoutes(app, db);
  registerRapportsRoutes(app, db);
  registerAnnoncesRoutes(app, db);

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
