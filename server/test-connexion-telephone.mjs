/* Test local Connexion par téléphone (migration 012) — base PostgreSQL
 * de test seulement, jamais Render.
 * Usage :
 *   sudo -u postgres psql -c "CREATE DATABASE esc_tel_test;"
 *   sudo -u postgres psql -c "CREATE DATABASE esc_tel_doublons;"
 *   DATABASE_URL=<redacted> \
 *   DATABASE_URL_DOUBLONS=<redacted> \
 *   node test-connexion-telephone.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations 001 à 011, insère des téléphones non normalisés, applique la
 * 012 par le vrai lanceur (`npm run migrate`), démarre l'API (tsx
 * server/src/index.ts, PORT 3111) et exerce les routes. Il ne supprime
 * pas les bases : les supprimer après, à la main.
 */
import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const DB2 = process.env.DATABASE_URL_DOUBLONS;
const BASE = "http://127.0.0.1:3111";
if (!DB || !DB2) throw new Error("DATABASE_URL et DATABASE_URL_DOUBLONS manquants");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const MIGRATIONS_AVANT_012 = ["001_fonctionnalites_eglise.sql", "001_transferts_membre.sql", "002_vue_consolidee_recursive.sql", "003_mot_de_passe_acces_fidele.sql", "004_depenses_budget_stats.sql", "005_modules_eglise.sql", "005_rapports_nombres.sql", "006_organisation_catalogues.sql", "007_campagnes.sql", "008_attestations.sql", "009_codes_tutelle.sql", "010_codes_invitation.sql", "011_ajout_sexe_membre.sql", "011_checkins_enfants.sql"];

async function preparer(dbUrl) {
  const db = new Client({ connectionString: dbUrl });
  await db.connect();
  await db.query(readFileSync("../db/schema.sql", "utf8"));
  await db.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`);
  for (const f of MIGRATIONS_AVANT_012) {
    await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
    await db.query(`INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING`, [f.replace(/\.sql$/, "")]);
  }
  return db;
}

function lancerMigrate(dbUrl) {
  const r = spawnSync("npx", ["tsx", "src/migrate.ts"], {
    cwd: process.cwd(),
    env: { ...process.env, DATABASE_URL: dbUrl },
    encoding: "utf8",
  });
  return r;
}

// -- Cas des doublons : la migration 012 doit échouer en les nommant. -----
console.log("Doublons (base séparée) :");
const db2 = await preparer(DB2);
// En production la contrainte n'existe pas encore, elle arrive avec la
// 012 : on la retire pour reproduire cet état avant de semer les doublons.
await db2.query(`ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_unique`);
const hash2 = await argon2.hash("Test1234!");
await db2.query(`INSERT INTO users (email, password_hash, full_name, phone) VALUES ('a@test.ci', $1, 'A', '07 47 12 34 01'), ('b@test.ci', $1, 'B', '+225747123401')`, [hash2]);
const mig2 = lancerMigrate(DB2);
check(
  "migration 012 refusée, numéro en double nommé",
  mig2.status !== 0 && (mig2.stdout + mig2.stderr).includes("+225747123401"),
  `status=${mig2.status} sortie=${(mig2.stdout + mig2.stderr).slice(0, 300)}`,
);
const contrainteApresEchec = await db2.query(`SELECT 1 FROM pg_constraint WHERE conname = 'users_phone_unique'`);
check("aucune contrainte UNIQUE posée après l'échec", contrainteApresEchec.rowCount === 0);
await db2.end();

// -- Base principale : téléphones non normalisés avant la 012. -------------
console.log("Migration 012 :");
const db = await preparer(DB);
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const egliseId = (await q(`INSERT INTO churches (code, code_fidele, name, city, status) VALUES ('ESC-TEL01', 'ESC-F-0001', 'Église Test Téléphone', 'Abidjan', 'active') RETURNING id`))[0].id;
async function user(email, phone, role) {
  const u = (await q(`INSERT INTO users (email, password_hash, full_name, phone) VALUES ($1, $2, $3, $4) RETURNING id`, [email, hash, email, phone]))[0].id;
  await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`, [u, egliseId, role]);
  return u;
}
await user("admin-test@example.ci", "07 47 12 34 01", "admin_eglise");
await user("membre-test@example.ci", "+225 07 47 12 34 02", "membre");
await user("lock-test@example.ci", "225747123403", "membre");
await user("sans-tel@example.ci", null, "membre");
const mig = lancerMigrate(DB);
check("migrate applique la 012", mig.status === 0 && mig.stdout.includes("012_connexion_telephone"), `status=${mig.status} sortie=${(mig.stdout + mig.stderr).slice(0, 300)}`);
const tels = await q(`SELECT email, phone FROM users ORDER BY email`);
const tel = (e) => tels.find((t) => t.email === e)?.phone;
check("07 47 12 34 01 -> +225747123401", tel("admin-test@example.ci") === "+225747123401", tel("admin-test@example.ci"));
check("+225 07 47 12 34 02 -> +225747123402", tel("membre-test@example.ci") === "+225747123402", tel("membre-test@example.ci"));
check("225747123403 -> +225747123403", tel("lock-test@example.ci") === "+225747123403", tel("lock-test@example.ci"));
check("NULL reste NULL", tel("sans-tel@example.ci") === null);
const contrainte = await q(`SELECT 1 FROM pg_constraint WHERE conname = 'users_phone_unique'`);
check("contrainte users_phone_unique posée", contrainte.length === 1);
const mig2x = lancerMigrate(DB);
check("migrate relancé : à jour, 012 non réappliquée", mig2x.status === 0 && !mig2x.stdout.includes("012_connexion_telephone"));

// -- API. -------------------------------------------------------------------
const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3111", DATABASE_URL: DB, JWT_SECRET: "test-secret-telephone-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  async function login(body) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    return { status: r.status, d: await j(r) };
  }

  console.log("Connexion par téléphone :");
  let r = await login({ identifiant: "07 47 12 34 01", password: "Test1234!" });
  check("téléphone avec espaces, 200", r.status === 200 && !!r.d.token, JSON.stringify(r.d));
  r = await login({ identifiant: "+225 74 71 23 40 1", password: "Test1234!" });
  check("téléphone +225 avec espaces, 200", r.status === 200 && !!r.d.token, JSON.stringify(r.d));
  r = await login({ identifiant: "225747123402", password: "Test1234!" });
  check("téléphone 225 sans +, 200", r.status === 200 && !!r.d.token, JSON.stringify(r.d));
  r = await login({ identifiant: "ADMIN-TEST@EXAMPLE.CI", password: "Test1234!" });
  check("e-mail en majuscules, 200 (bug corrigé)", r.status === 200 && !!r.d.token, JSON.stringify(r.d));
  r = await login({ email: "admin-test@example.ci", password: "Test1234!" });
  check("ancien champ email, 200 (compatibilité)", r.status === 200 && !!r.d.token, JSON.stringify(r.d));
  r = await login({ identifiant: "07 47 12 34 01", password: "mauvais" });
  check("mauvais mot de passe, 401", r.status === 401, JSON.stringify(r.d));
  r = await login({ identifiant: "07 47 99 99 99", password: "Test1234!" });
  check("téléphone inconnu, 401 générique", r.status === 401 && r.d.message === "Identifiant ou mot de passe incorrect.", JSON.stringify(r.d));
  r = await login({ identifiant: "abc", password: "Test1234!" });
  check("identifiant invalide, 401 générique", r.status === 401, JSON.stringify(r.d));

  console.log("Verrouillage par téléphone :");
  for (let i = 0; i < 4; i++) await login({ identifiant: "225747123403", password: "mauvais" });
  r = await login({ identifiant: "225747123403", password: "mauvais" });
  check("5e échec par téléphone, 423 verrouillé", r.status === 423, JSON.stringify(r.d));
  r = await login({ identifiant: "225747123403", password: "Test1234!" });
  check("compte verrouillé, bon mot de passe refusé", r.status === 423, JSON.stringify(r.d));

  console.log("Inscription église avec téléphone admin :");
  r = await fetch(`${BASE}/auth/register`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ eglise: { name: "Église Test Tél 2", city: "Abidjan", phone: "07 47 12 34 07" }, admin: { full_name: "Admin Tél", email: "admin-tel2@example.ci", phone: "07 47 12 34 05", password: "Test1234!" }, channel: "web" }) });
  let d = await j(r);
  check("inscription 201", r.status === 201 && !!d.token, JSON.stringify(d));
  const tokAdmin2 = d.token;
  const codeFidele = d.church.code_fidele;
  const moi = await j(await fetch(`${BASE}/moi/eglise`, { headers: { Authorization: `Bearer ${tokAdmin2}` } }));
  check("téléphone admin normalisé en base", moi.user?.phone === "+225747123405", JSON.stringify(moi.user));
  const eglise2 = (await q(`SELECT phone FROM churches WHERE code = $1`, [d.church.code]))[0];
  check("téléphone église normalisé en base", eglise2.phone === "+225747123407", eglise2.phone);
  r = await fetch(`${BASE}/auth/register`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ eglise: { name: "Église Test Tél 3", city: "Abidjan" }, admin: { full_name: "Admin Tél 3", email: "admin-tel3@example.ci", phone: "07 47 12 34 05", password: "Test1234!" }, channel: "web" }) });
  d = await j(r);
  check("même téléphone admin, 409 phone_taken", r.status === 409 && d.error === "phone_taken", JSON.stringify(d));
  r = await fetch(`${BASE}/auth/register`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ eglise: { name: "Église Test Tél 4", city: "Abidjan" }, admin: { full_name: "Admin Tél 4", email: "ADMIN-TEL2@EXAMPLE.CI", phone: "07 47 12 34 08", password: "Test1234!" }, channel: "web" }) });
  d = await j(r);
  check("même e-mail en majuscules, 409 email_taken", r.status === 409 && d.error === "email_taken", JSON.stringify(d));

  console.log("Inscription membre par code, téléphone normalisé :");
  r = await fetch(`${BASE}/auth/inscription-par-code`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ nom_prenom: "Membre Tél", email: "membre-tel@example.ci", telephone: "07 47 12 34 06", mot_de_passe: "Test1234!", code_eglise: codeFidele, channel: "web" }) });
  d = await j(r);
  check("inscription membre 201", r.status === 201 && !!d.token, JSON.stringify(d));
  const membreTel = (await q(`SELECT u.phone AS uphone, m.phone AS mphone FROM users u JOIN members m ON m.user_id = u.id WHERE u.email = 'membre-tel@example.ci'`))[0];
  check("téléphone membre normalisé (users et members)", membreTel?.uphone === "+225747123406" && membreTel?.mphone === "+225747123406", JSON.stringify(membreTel));
  r = await fetch(`${BASE}/auth/inscription-par-code`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ nom_prenom: "Membre Tél 2", email: "membre-tel2@example.ci", telephone: "07 47 12 34 06", mot_de_passe: "Test1234!", code_eglise: codeFidele, channel: "web" }) });
  d = await j(r);
  check("même téléphone membre, 409 phone_taken", r.status === 409 && d.error === "phone_taken", JSON.stringify(d));
  r = await fetch(`${BASE}/auth/inscription-par-code`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ nom_prenom: "Membre Tél 3", email: "membre-tel3@example.ci", telephone: "abc", mot_de_passe: "Test1234!", code_eglise: codeFidele, channel: "web" }) });
  d = await j(r);
  check("téléphone invalide, 400", r.status === 400, JSON.stringify(d));
  r = await login({ identifiant: "07 47 12 34 06", password: "Test1234!" });
  check("nouveau membre connecté par téléphone, 200", r.status === 200 && !!r.d.token, JSON.stringify(r.d));
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
}
await db.end();

console.log(`\n${ok} OK, ${ko} KO`);
if (ko > 0) process.exit(1);
