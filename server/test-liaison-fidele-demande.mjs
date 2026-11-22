/* Test tranche 2 — liaison fidèle : plus de liaison immédiate sur simple
 * concordance d'e-mail (audit sécurité, moyenne).
 * Base PostgreSQL de test seulement, jamais Render.
 * Usage :
 *   sudo -u postgres psql -c "CREATE DATABASE esc_liaison_test;"
 *   DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/esc_liaison_test \
 *     node test-liaison-fidele.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations par le vrai lanceur (`npm run migrate`), démarre l'API
 * (tsx server/src/index.ts, PORT 3114) et exerce la route.
 * Il ne supprime pas la base : la supprimer après, à la main.
 */
import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3114";
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
await db.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`);
const mig = spawnSync("npx", ["tsx", "src/migrate.ts"], {
  cwd: process.cwd(),
  env: { ...process.env, DATABASE_URL: DB },
  encoding: "utf8",
});
check("migrations appliquées", mig.status === 0, `status=${mig.status} ${(mig.stdout + mig.stderr).slice(0, 300)}`);

const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const egliseId = (await q(`INSERT INTO churches (code, code_fidele, name, city, status) VALUES ('ESC-LIA', 'ESC-F-1001', 'Église Liaison', 'Abidjan', 'active') RETURNING id`))[0].id;
const hashAdmin = await argon2.hash("Admin1234!");
const adminId = (await q(`INSERT INTO users (email, password_hash, full_name, phone) VALUES ('admin-liaison@example.ci', $1, 'Admin Liaison', '+225747123400') RETURNING id`, [hashAdmin]))[0].id;
await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'admin_eglise')`, [adminId, egliseId]);
// Fiche membre victime, active, non liée, avec e-mail connu.
const membreId = (await q(`INSERT INTO members (church_id, matricule, full_name, email, status) VALUES ($1, 'M-LK-155390-01', 'Katia Laurent', 'victime@example.ci', 'actif') RETURNING id`, [egliseId]))[0].id;

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3114", DATABASE_URL: DB, JWT_SECRET: "test-secret-liaison-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const post = async (path, body, token) => {
    const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
    return { status: r.status, d: await j(r) };
  };

  console.log("Inscription avec l'e-mail et le matricule de la victime :");
  let r = await post("/auth/inscription-fidele", { email: "victime@example.ci", mot_de_passe: "Attaquant1!", matricule: "M-LK-155390-01", channel: "web" });
  check("201 lie:false + demande_id (pas de liaison immédiate)", r.status === 201 && r.d.lie === false && !!r.d.demande_id, JSON.stringify(r.d).slice(0, 200));
  check("aucun jeton renvoyé", !r.d.token && !r.d.refresh_token, JSON.stringify(r.d).slice(0, 200));
  const demandeId = r.d.demande_id;
  const membre = (await q(`SELECT user_id FROM members WHERE id = $1`, [membreId]))[0];
  check("fiche membre toujours non liée", membre.user_id === null, `user_id=${membre.user_id}`);
  const demande = (await q(`SELECT status FROM member_link_requests WHERE id = $1`, [demandeId]))[0];
  check("demande en attente en base", demande?.status === "en_attente", JSON.stringify(demande));

  console.log("Connexion avant validation :");
  r = await post("/auth/login", { identifiant: "victime@example.ci", password: "Attaquant1!", channel: "web" });
  check("login refusé (no_church)", r.status !== 200 && r.d.error === "no_church", JSON.stringify(r.d).slice(0, 200));

  console.log("Validation par l'admin, puis connexion :");
  r = await post("/auth/login", { identifiant: "admin-liaison@example.ci", password: "Admin1234!", channel: "web" });
  check("login admin 200", r.status === 200 && !!r.d.token, `status=${r.status}`);
  const tokenAdmin = r.d.token;
  r = await post(`/membres/demandes-liaison/${demandeId}/valider`, {}, tokenAdmin);
  check("validation 200, statut valide", r.status === 200 && r.d.status === "valide", JSON.stringify(r.d).slice(0, 200));
  const membreApres = (await q(`SELECT user_id FROM members WHERE id = $1`, [membreId]))[0];
  check("fiche liée après validation admin", membreApres.user_id !== null, `user_id=${membreApres.user_id}`);
  r = await post("/auth/login", { identifiant: "victime@example.ci", password: "Attaquant1!", channel: "web" });
  check("login possible après validation", r.status === 200 && !!r.d.token, `status=${r.status}`);
} finally {
  try { process.kill(-server.pid); } catch {}
  await db.end();
}
console.log(`\nLiaison fidèle : ${ok} OK, ${ko} KO.`);
process.exit(ko > 0 ? 1 : 0);
