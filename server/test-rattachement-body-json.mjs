/* Test local — rattachement, corps JSON vide et UUID invalide.
 * Base PostgreSQL de test seulement, jamais Render, jamais
 * CONNEXION PROPHÉTIQUE.
 * Usage : DATABASE_URL=<redacted>
 *   node test-rattachement-body-json.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations, démarre l'API (tsx server/src/index.ts, PORT 3110) et exerce
 * les routes. Il ne supprime pas la base : la supprimer après, à la main.
 */
import { spawn } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3110";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const db = new Client({ connectionString: DB });
await db.connect();
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of readdirSync("../db/migrations").sort()) {
  if (f.endsWith(".sql")) await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const mere = (await q(`INSERT INTO churches (code,name,city,status) VALUES ('ESC-TEST-M','Église Mère Test','Abidjan','active') RETURNING id`))[0].id;
const fille = (await q(`INSERT INTO churches (code,name,city,status) VALUES ('ESC-TEST-C','Église Fille Test','Bingerville','active') RETURNING id`))[0].id;
async function user(email, church, role) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name) VALUES ($1,$2,$3) RETURNING id`, [email, hash, email]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [u, church, role]);
  return u;
}
await user("admin-mere@test.ci", mere, "admin_eglise");
await user("admin-fille@test.ci", fille, "admin_eglise");
async function demande() {
  return (await q(`INSERT INTO rattachements (church_id,parent_church_id,status) VALUES ($1,$2,'en_attente') RETURNING id`, [fille, mere]))[0].id;
}

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3110", DATABASE_URL: DB, JWT_SECRET: "test-secret-rattachement-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokMere = await login("admin-mere@test.ci");
  const tokFille = await login("admin-fille@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });

  // 1. Reproduction du défaut d'Axel : POST accepter, content-type
  // application/json, corps vide (ancien client, déjà installé).
  const id1 = await demande();
  let r = await fetch(`${BASE}/rattachements/${id1}/accepter`, { method: "POST", headers: H(tokMere) });
  let j = await r.json().catch(() => ({}));
  check("accepter, corps vide + content-type json : 200", r.status === 200, `HTTP ${r.status} ${JSON.stringify(j)}`);
  check("accepter, statut acceptee", j.status === "acceptee");
  check("accepter, pas de bande « Body cannot be empty »", !JSON.stringify(j).includes("Body cannot be empty"));
  const liee = await q(`SELECT parent_church_id FROM churches WHERE id = $1`, [fille]);
  check("accepter, église fille rattachée à la mère", liee[0].parent_church_id === mere);

  // 2. Refuser, corps vide aussi.
  const id2 = await demande();
  r = await fetch(`${BASE}/rattachements/${id2}/refuser`, { method: "POST", headers: H(tokMere) });
  j = await r.json().catch(() => ({}));
  check("refuser, corps vide + content-type json : 200", r.status === 200, `HTTP ${r.status} ${JSON.stringify(j)}`);
  check("refuser, statut refusee", j.status === "refusee");

  // 3. Nouveau client : corps {} explicite.
  const id3 = await demande();
  r = await fetch(`${BASE}/rattachements/${id3}/accepter`, { method: "POST", headers: H(tokMere), body: "{}" });
  j = await r.json().catch(() => ({}));
  check("accepter, corps {} : 200", r.status === 200, `HTTP ${r.status} ${JSON.stringify(j)}`);

  // 4. Demande déjà traitée : 409, pas 500.
  r = await fetch(`${BASE}/rattachements/${id3}/accepter`, { method: "POST", headers: H(tokMere) });
  j = await r.json().catch(() => ({}));
  check("demande déjà traitée : 409", r.status === 409, `HTTP ${r.status}`);

  // 5. UUID invalide : 400, pas 500.
  r = await fetch(`${BASE}/rattachements/pas-un-uuid/accepter`, { method: "POST", headers: H(tokMere) });
  j = await r.json().catch(() => ({}));
  check("UUID invalide : 400", r.status === 400, `HTTP ${r.status} ${JSON.stringify(j)}`);
  r = await fetch(`${BASE}/rattachements/pas-un-uuid/refuser`, { method: "POST", headers: H(tokMere) });
  check("UUID invalide, refuser : 400", r.status === 400, `HTTP ${r.status}`);

  // 6. UUID valide mais inexistant : 404.
  r = await fetch(`${BASE}/rattachements/11111111-1111-1111-1111-111111111111/accepter`, { method: "POST", headers: H(tokMere) });
  check("UUID inexistant : 404", r.status === 404, `HTTP ${r.status}`);

  // 7. Une autre église que la mère sollicitée ne peut pas décider : 403.
  const id4 = await demande();
  r = await fetch(`${BASE}/rattachements/${id4}/accepter`, { method: "POST", headers: H(tokFille) });
  check("décision par une autre église : 403", r.status === 403, `HTTP ${r.status}`);

  // 8. JSON mal formé toujours rejeté en 400.
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokFille), body: "{pas du json" });
  check("JSON mal formé : 400", r.status === 400, `HTTP ${r.status}`);

  // 9. Création de demande, corps vide : 400 métier, pas l'erreur Fastify.
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokFille) });
  j = await r.json().catch(() => ({}));
  check("création, corps vide : 400 métier", r.status === 400 && !JSON.stringify(j).includes("Body cannot be empty"), `HTTP ${r.status} ${JSON.stringify(j)}`);
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
}
await db.end();
console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko ? 1 : 0);
