/* Test local Session gardée (migration 014) — base PostgreSQL de test
 * seulement, jamais Render.
 * Usage :
 *   sudo -u postgres psql -c "CREATE DATABASE esc_session_test;"
 *   DATABASE_URL=<redacted> \
 *   node test-session-gardee.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations 001 à 011, puis 012 et 014 par le vrai lanceur
 * (`npm run migrate`, la 013 est réservée à Phoenix et n'existe pas
 * encore), démarre l'API (tsx server/src/index.ts, PORT 3112) et exerce
 * les routes. Il ne supprime pas la base : la supprimer après, à la main.
 */
import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3112";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const MIGRATIONS_AVANT_012 = ["001_fonctionnalites_eglise.sql", "001_transferts_membre.sql", "002_vue_consolidee_recursive.sql", "003_mot_de_passe_acces_fidele.sql", "004_depenses_budget_stats.sql", "005_modules_eglise.sql", "005_rapports_nombres.sql", "006_organisation_catalogues.sql", "007_campagnes.sql", "008_attestations.sql", "009_codes_tutelle.sql", "010_codes_invitation.sql", "011_ajout_sexe_membre.sql", "011_checkins_enfants.sql"];

function decodeJwt(token) {
  const part = token.split(".")[1];
  return JSON.parse(Buffer.from(part.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString());
}

const db = new Client({ connectionString: DB });
await db.connect();
await db.query(readFileSync("../db/schema.sql", "utf8"));
await db.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`);
for (const f of MIGRATIONS_AVANT_012) {
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
  await db.query(`INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING`, [f.replace(/\.sql$/, "")]);
}
const mig = spawnSync("npx", ["tsx", "src/migrate.ts"], {
  cwd: process.cwd(),
  env: { ...process.env, DATABASE_URL: DB },
  encoding: "utf8",
});
console.log("Migration 014 :");
check("migrate applique la 012 et la 014", mig.status === 0 && mig.stdout.includes("012_connexion_telephone") && mig.stdout.includes("014_jetons_rafraichissement"), `status=${mig.status} sortie=${(mig.stdout + mig.stderr).slice(0, 300)}`);
const table = await db.query(`SELECT 1 FROM information_schema.tables WHERE table_name = 'refresh_tokens'`);
check("table refresh_tokens créée", table.rowCount === 1);

const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const egliseA = (await q(`INSERT INTO churches (code, code_fidele, name, city, status) VALUES ('ESC-SES-A', 'ESC-F-1001', 'Église Session A', 'Abidjan', 'active') RETURNING id`))[0].id;
const egliseB = (await q(`INSERT INTO churches (code, code_fidele, name, city, status) VALUES ('ESC-SES-B', 'ESC-F-1002', 'Église Session B', 'Abidjan', 'active') RETURNING id`))[0].id;
const userId = (await q(`INSERT INTO users (email, password_hash, full_name, phone) VALUES ('session-test@example.ci', $1, 'Session Test', '+225747123499') RETURNING id`, [hash]))[0].id;
await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'admin_eglise'), ($1, $3, 'admin_eglise')`, [userId, egliseA, egliseB]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3112", DATABASE_URL: DB, JWT_SECRET: "test-secret-session-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  async function login(body) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    return { status: r.status, d: await j(r) };
  }
  async function refresh(refreshToken) {
    const r = await fetch(`${BASE}/auth/refresh`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refresh_token: refreshToken }) });
    return { status: r.status, d: await j(r) };
  }
  const nbJetons = async () => (await q(`SELECT count(*)::int AS n FROM refresh_tokens WHERE user_id = $1`, [userId]))[0].n;
  const nbJetonsUtilises = async () => (await q(`SELECT count(*)::int AS n FROM refresh_tokens WHERE user_id = $1 AND used_at IS NOT NULL`, [userId]))[0].n;

  console.log("Connexion et durées JWT :");
  let r = await login({ identifiant: "session-test@example.ci", password: "Test1234!", channel: "web" });
  check("login web 200 + refresh_token", r.status === 200 && !!r.d.token && !!r.d.refresh_token, JSON.stringify(r.d).slice(0, 200));
  const jwtWeb = r.d.token;
  const refreshWeb = r.d.refresh_token;
  const payloadWeb = decodeJwt(jwtWeb);
  check("JWT web dure 30 min", payloadWeb.exp - payloadWeb.iat === 1800, `exp-iat=${payloadWeb.exp - payloadWeb.iat}`);
  r = await login({ identifiant: "session-test@example.ci", password: "Test1234!", channel: "mobile" });
  check("login mobile 200 + refresh_token", r.status === 200 && !!r.d.refresh_token, JSON.stringify(r.d).slice(0, 200));
  const payloadMobile = decodeJwt(r.d.token);
  check("JWT mobile dure 2 h", payloadMobile.exp - payloadMobile.iat === 7200, `exp-iat=${payloadMobile.exp - payloadMobile.iat}`);

  console.log("Rotation :");
  r = await fetch(`${BASE}/moi/eglise`, { headers: { Authorization: `Bearer ${jwtWeb}` } });
  check("JWT web accepté sur /moi/eglise", r.status === 200, `status=${r.status}`);
  r = await refresh(refreshWeb);
  check("refresh 200 + nouveau couple", r.status === 200 && !!r.d.token && !!r.d.refresh_token && r.d.refresh_token !== refreshWeb, JSON.stringify(r.d).slice(0, 200));
  const jwtWeb2 = r.d.token;
  const refreshWeb2 = r.d.refresh_token;
  r = await fetch(`${BASE}/moi/eglise`, { headers: { Authorization: `Bearer ${jwtWeb2}` } });
  check("nouveau JWT accepté", r.status === 200, `status=${r.status}`);
  check("ancien jeton marqué utilisé", (await nbJetonsUtilises()) === 1, `utilisés=${await nbJetonsUtilises()}`);
  check("3 jetons en base (mobile + ancien + nouveau)", (await nbJetons()) === 3, `total=${await nbJetons()}`);

  console.log("Vol détecté : réutilisation de l'ancien jeton :");
  r = await refresh(refreshWeb);
  check("ancien jeton réutilisé, 401", r.status === 401, JSON.stringify(r.d));
  check("tous les jetons de l'utilisateur révoqués", (await nbJetons()) === 0, `total=${await nbJetons()}`);

  console.log("Déconnexion :");
  r = await login({ identifiant: "session-test@example.ci", password: "Test1234!", channel: "web" });
  check("nouveau login 200", r.status === 200 && !!r.d.refresh_token, `status=${r.status}`);
  const jwtLogout = r.d.token;
  const refreshLogout = r.d.refresh_token;
  r = await fetch(`${BASE}/auth/logout`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${jwtLogout}` }, body: JSON.stringify({ refresh_token: refreshLogout }) });
  check("logout 200", r.status === 200, `status=${r.status} ${JSON.stringify(r.d)}`);
  r = await refresh(refreshLogout);
  check("refresh après logout, 401", r.status === 401, JSON.stringify(r.d));

  console.log("Changement de mot de passe :");
  r = await login({ identifiant: "session-test@example.ci", password: "Test1234!", channel: "web" });
  check("login avant changement 200", r.status === 200 && !!r.d.refresh_token, `status=${r.status}`);
  const jwtMdp = r.d.token;
  const refreshMdp = r.d.refresh_token;
  r = await fetch(`${BASE}/auth/changer-mot-de-passe`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${jwtMdp}` }, body: JSON.stringify({ ancien: "Test1234!", nouveau: "Nouveau1234!" }) });
  check("changement de mot de passe 200", r.status === 200, `status=${r.status} ${JSON.stringify(r.d)}`);
  r = await refresh(refreshMdp);
  check("refresh après changement de mot de passe, 401", r.status === 401, JSON.stringify(r.d));
  r = await fetch(`${BASE}/moi/eglise`, { headers: { Authorization: `Bearer ${jwtMdp}` } });
  check("ancien JWT refusé après changement", r.status === 401, `status=${r.status}`);
  r = await login({ identifiant: "session-test@example.ci", password: "Nouveau1234!", channel: "web" });
  check("login avec le nouveau mot de passe 200", r.status === 200 && !!r.d.refresh_token, `status=${r.status}`);

  console.log("Changement d'église active :");
  const jwtSwitch = r.d.token;
  const refreshSwitch = r.d.refresh_token;
  r = await fetch(`${BASE}/auth/eglise-active`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${jwtSwitch}` }, body: JSON.stringify({ church_id: egliseB, channel: "web", refresh_token: refreshSwitch }) });
  const dSwitch = await j(r);
  check("eglise-active 200 + jeton tourné", r.status === 200 && !!dSwitch.token && !!dSwitch.refresh_token && dSwitch.refresh_token !== refreshSwitch, JSON.stringify(dSwitch).slice(0, 200));
  check("nouveau JWT pour l'église B", decodeJwt(dSwitch.token).churchId === egliseB, `churchId=${decodeJwt(dSwitch.token).churchId}`);
  r = await refresh(dSwitch.refresh_token);
  check("refresh avec le jeton tourné 200", r.status === 200 && !!r.d.token, `status=${r.status}`);
  check("JWT rafraîchi toujours pour l'église B", decodeJwt(r.d.token).churchId === egliseB, `churchId=${decodeJwt(r.d.token).churchId}`);
  r = await refresh(refreshSwitch);
  check("ancien jeton (avant bascule) réutilisé, 401", r.status === 401, JSON.stringify(r.d));

  console.log("Cas d'erreur :");
  r = await refresh("jeton-inexistant");
  check("jeton inconnu, 401", r.status === 401, JSON.stringify(r.d));
  r = await fetch(`${BASE}/auth/refresh`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({}) });
  check("refresh sans jeton, 400", r.status === 400, `status=${r.status}`);
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
}
await db.end();

console.log(`\n${ok} OK, ${ko} KO`);
if (ko > 0) process.exit(1);
