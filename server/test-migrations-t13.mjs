// Test des migrations (T13, P0-3) : garde-fou contre le bug de la
// migration 028 (PR #89) — 3 CREATE INDEX placés avant leurs CREATE
// TABLE dans le même fichier, qui ont fait échouer la migration en
// production (« relation "mandats" does not exist », 42P01), parce que
// la procédure Render exécute le fichier seul, sans le schéma préalable.
//
// Ce que vérifie ce test :
//   1. Statique, sans base : aucun CREATE INDEX ne vise une table créée
//      après lui dans l'ordre global (db/schema.sql puis migrations
//      triées). C'est le motif exact du bug 028.
//   2. Statique, sans base : les numéros en double sont exactement
//      001, 005 et 011, et les numéros manquants exactement 017 et 027
//      (voir db/migrations/README.md). Tout nouveau doublon ou trou
//      fait échouer le test : il faut alors le documenter dans le
//      README avant de fusionner.
//   3. Sur base fraîche : `migrate.ts` appliqué deux fois = no-op — la
//      deuxième exécution n'applique rien et le nombre de lignes de
//      `schema_migrations` ne change pas.
//   4. Sur base fraîche : après migrate.ts, chaque fichier de migration
//      est enregistré dans `schema_migrations` (un par fichier).
//
// Usage (depuis server/, comme les autres tests) :
//   DATABASE_URL=<redacted>
//     node test-migrations-t13.mjs
// Sans DATABASE_URL, la base locale ci-dessous est utilisée (créée
// puis vidée par le test lui-même, comme test-sycebnl-p6.mjs).
// Base locale : PostgreSQL est nécessaire. Sans base locale, la partie
// base est signalée comme non vérifiée et le test échoue : la CI
// (workflow Server, service postgres) est alors la vérification.
//
// Limite assumée : l'exécution d'un fichier seul, sur une base vide
// après schema.sql uniquement, n'est PAS exigée ici — la migration 025
// vise légitimement des tables de la 001 (caisse_mouvements) et du
// schéma (contributions). La procédure retenue est donc : toujours
// `npm run migrate` complet, jamais un fichier seul (voir
// db/migrations/README.md). Le garde-fou contre le bug 028 est le
// contrôle statique (1), pas l'exécution isolée.
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Client } from "pg";

const DB =
  process.env.DATABASE_URL ??
  "postgres://postgres:postgres@127.0.0.1:5432/esc_migrations_t13_test";
const ADMIN_DB = DB.replace(/\/[^/]*$/, "/postgres");
const DB_NAME = "esc_migrations_t13_test";
const MIGRATIONS_DIR = fileURLToPath(new URL("../db/migrations", import.meta.url));
const SCHEMA_SQL = fileURLToPath(new URL("../db/schema.sql", import.meta.url));
const TSX = fileURLToPath(new URL("node_modules/.bin/tsx", import.meta.url));

let ok = 0;
let ko = 0;
function check(nom, cond, extra = "") {
  if (cond) {
    ok++;
    console.log(`  OK  ${nom}`);
  } else {
    ko++;
    console.log(`  KO  ${nom} ${extra}`);
  }
}

// ---------------------------------------------------------------------------
// 1 + 2. Contrôles statiques (sans base).
// ---------------------------------------------------------------------------
function sansCommentaires(sql) {
  return sql
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !l.trim().startsWith("--"))
    .join("\n");
}

// Ordre global de création : schema.sql puis migrations triées, dans
// l'ordre des instructions de chaque fichier.
const ordre = [];
function scanner(sql, ou) {
  const re =
    /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:\"?[\w]+\"?\.)?\"?([\w]+)\"?|CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?\"?[\w]+\"?\s+ON\s+(?:\"?[\w]+\"?\.)?\"?([\w]+)\"?/gi;
  let m;
  while ((m = re.exec(sql))) {
    if (m[1]) ordre.push({ genre: "table", table: m[1].toLowerCase(), ou });
    else if (m[2]) ordre.push({ genre: "index", table: m[2].toLowerCase(), ou });
  }
}
scanner(sansCommentaires(readFileSync(SCHEMA_SQL, "utf8")), "schema.sql");
const fichiers = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.endsWith(".sql"))
  .sort();
for (const f of fichiers) {
  scanner(
    sansCommentaires(readFileSync(`${MIGRATIONS_DIR}/${f}`, "utf8")),
    f,
  );
}

const premiereCreation = {};
for (const e of ordre) {
  if (e.genre === "table" && !(e.table in premiereCreation)) {
    premiereCreation[e.table] = e;
  }
}
const ordreIndex = new Map(ordre.map((e, i) => [e, i]));
let violations = 0;
for (const e of ordre) {
  if (e.genre !== "index") continue;
  const creee = premiereCreation[e.table];
  if (!creee) {
    violations++;
    console.log(`  KO  index sur table jamais créée : ${e.table} (${e.ou})`);
  } else if (ordreIndex.get(creee) > ordreIndex.get(e)) {
    violations++;
    console.log(
      `  KO  index avant sa table : ${e.table} (index dans ${e.ou}, ` +
        `table créée dans ${creee.ou})`,
    );
  }
}
check("aucun index avant sa table (motif du bug 028)", violations === 0);

const numeros = fichiers.map((f) => parseInt(f.slice(0, 3), 10));
const parNumero = {};
for (const f of fichiers) {
  const n = parseInt(f.slice(0, 3), 10);
  (parNumero[n] = parNumero[n] || []).push(f);
}
const doublons = Object.entries(parNumero)
  .filter(([, v]) => v.length > 1)
  .map(([k]) => Number(k))
  .sort((a, b) => a - b);
check(
  "numéros en double exactement 001, 005, 011 (documentés)",
  JSON.stringify(doublons) === JSON.stringify([1, 5, 11]),
  `trouvés : ${doublons.join(", ") || "aucun"}`,
);
const max = Math.max(...numeros);
const manquants = [];
for (let i = 1; i <= max; i++) {
  if (!parNumero[i]) manquants.push(i);
}
check(
  "numéros manquants exactement 017, 027 (documentés)",
  JSON.stringify(manquants) === JSON.stringify([17, 27]),
  `trouvés : ${manquants.join(", ") || "aucun"}`,
);

// ---------------------------------------------------------------------------
// 3 + 4. migrate.ts deux fois sur base fraîche = no-op.
// ---------------------------------------------------------------------------
function lancerMigrate() {
  return spawnSync(TSX, ["src/migrate.ts"], {
    cwd: fileURLToPath(new URL(".", import.meta.url)),
    env: { ...process.env, DATABASE_URL: DB },
    encoding: "utf8",
  });
}

let baseIndisponible = false;
let db = null;
try {
  const admin = new Client({ connectionString: ADMIN_DB });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS "${DB_NAME}"`);
  await admin.query(`CREATE DATABASE "${DB_NAME}"`);
  await admin.end();
  db = new Client({ connectionString: DB });
  await db.connect();
} catch (e) {
  baseIndisponible = true;
  console.log(
    "  KO  base PostgreSQL indisponible — partie base non vérifiée, " +
      `à valider en CI : ${e.message}`,
  );
  ko++;
}

if (!baseIndisponible) {
  const r1 = lancerMigrate();
  check(
    "migrate.ts, 1re exécution : code 0",
    r1.status === 0,
    r1.stderr || r1.error?.message || "",
  );
  const lignes1 = await db.query("SELECT name FROM schema_migrations ORDER BY name");
  const noms1 = lignes1.rows.map((r) => r.name);
  check(
    "migrate.ts : baseline 000_baseline enregistrée",
    noms1.includes("000_baseline"),
  );
  const attendus = fichiers.map((f) => f.replace(/\.sql$/, ""));
  const manquantes = attendus.filter((n) => !noms1.includes(n));
  check(
    `migrate.ts : ${attendus.length} migrations enregistrées`,
    manquantes.length === 0,
    manquantes.length > 0 ? `manquantes : ${manquantes.join(", ")}` : "",
  );

  const r2 = lancerMigrate();
  check(
    "migrate.ts, 2e exécution : code 0",
    r2.status === 0,
    r2.stderr || r2.error?.message || "",
  );
  check(
    "migrate.ts, 2e exécution : aucune migration réappliquée",
    !/^migration .*…$/m.test(r2.stdout),
    `sortie : ${JSON.stringify(r2.stdout)}`,
  );
  const lignes2 = await db.query("SELECT name FROM schema_migrations ORDER BY name");
  const noms2 = lignes2.rows.map((r) => r.name);
  check(
    "migrate.ts, 2e exécution : schema_migrations inchangé",
    JSON.stringify(noms1) === JSON.stringify(noms2),
    `${noms1.length} → ${noms2.length} lignes`,
  );
  await db.end();
}

console.log(`\nMigrations T13 : ${ok} OK, ${ko} KO.`);
process.exit(ko > 0 ? 1 : 0);
