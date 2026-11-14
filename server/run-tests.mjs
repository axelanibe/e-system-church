// Boucle locale des tests serveur (T13, P0-2) : `npm test` depuis server/.
// Même périmètre que .github/workflows/server.yml — tenir les deux
// listes d'exclusion à jour ensemble. Les tests exclus échouent déjà
// sur main (dérive des scripts face à l'API actuelle) ; leur réparation
// est prévue dans une tranche à part, ne pas les réintroduire
// silencieusement dans la boucle.
//
// Usage :
//   DATABASE_URL=<redacted>
//     npm test
// Les tests qui créent leur propre base tournent sans DATABASE_URL ;
// ceux qui l'exigent échouent avec leur propre message clair.
// Base locale : PostgreSQL est nécessaire pour la plupart des tests.
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// Scripts exclus : échecs préexistants au 14 nov. 2026, sur main comme
// sur la branche T13 (aucune source serveur touchée en T13). Même liste
// que .github/workflows/server.yml.
const EXCLUS = new Set([
  "test-abonnements-p3.mjs",
  "test-espace-fidele-p1.mjs",
  "test-lot-b-t1-rbac.mjs",
  "test-nettoyage-test.mjs",
  "test-plan-comptable.mjs",
  "test-rattachement-body-json.mjs",
  "test-rendez-vous-p4.mjs",
  "test-suppression-eglise.mjs",
  "test-sycebnl-p6.mjs",
]);

const RACINE = fileURLToPath(new URL("..", import.meta.url));
const SERVEUR = fileURLToPath(new URL(".", import.meta.url));

const tests = readdirSync(SERVEUR)
  .filter((f) => f.startsWith("test-") && f.endsWith(".mjs"))
  .sort();

let ok = 0;
let ko = 0;
for (const test of tests) {
  if (EXCLUS.has(test)) {
    console.log(`exclu (échec préexistant) : server/${test}`);
    continue;
  }
  console.log(`== server/${test}`);
  const contenu = readFileSync(`${SERVEUR}/${test}`, "utf8");
  // Même règle que le workflow : les scripts qui démarrent l'API avec
  // cwd 'server' se lancent depuis la racine du dépôt, les autres
  // depuis server/.
  const depuisRacine = /cwd:\s*['"]server['"]/.test(contenu);
  const r = spawnSync("node", [test], {
    cwd: depuisRacine ? RACINE : SERVEUR,
    env: process.env,
    stdio: "inherit",
  });
  if (r.status === 0) {
    ok++;
  } else {
    ko++;
    console.log(`ÉCHEC : server/${test} (code ${r.status}) — arrêt.`);
    break;
  }
}
console.log(`\nTests serveur : ${ok} OK, ${ko} KO (${EXCLUS.size} exclus).`);
process.exit(ko > 0 ? 1 : 0);
