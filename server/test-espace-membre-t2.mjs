/* Test local Espace membre T2 (migration 018) — base PostgreSQL de test
 * seulement, jamais Render.
 * Usage :
 *   sudo -u postgres psql -c "CREATE DATABASE esc_t2_test;"
 *   DATABASE_URL=postgres://postgres@127.0.0.1:5432/esc_t2_test \
 *   node test-espace-membre-t2.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations 001 à 011 par le vrai lanceur (`npm run migrate`, la 013 et
 * la 017 sont réservées à Phoenix et n'existent pas), démarre l'API
 * (tsx server/src/index.ts, PORT 3113) et exerce les routes T2. Il ne
 * supprime pas la base : la supprimer après, à la main.
 */
import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3113";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const MIGRATIONS_AVANT_012 = ["001_fonctionnalites_eglise.sql", "001_transferts_membre.sql", "002_vue_consolidee_recursive.sql", "003_mot_de_passe_acces_fidele.sql", "004_depenses_budget_stats.sql", "005_modules_eglise.sql", "005_rapports_nombres.sql", "006_organisation_catalogues.sql", "007_campagnes.sql", "008_attestations.sql", "009_codes_tutelle.sql", "010_codes_invitation.sql", "011_ajout_sexe_membre.sql", "011_checkins_enfants.sql"];

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
console.log("Migrations :");
for (const n of ["012_connexion_telephone", "014_jetons_rafraichissement", "015_import_membres", "016_types_attestations", "018_espace_membre"]) {
  check(`migrate applique la ${n}`, mig.status === 0 && mig.stdout.includes(n), `status=${mig.status} sortie=${(mig.stdout + mig.stderr).slice(0, 200)}`);
}
const table = await db.query(`SELECT 1 FROM information_schema.tables WHERE table_name = 'annonces_lectures'`);
check("table annonces_lectures créée", table.rowCount === 1);
const colPhoto = await db.query(`SELECT 1 FROM information_schema.columns WHERE table_name = 'members' AND column_name = 'photo_url'`);
check("colonne members.photo_url créée", colPhoto.rowCount === 1);
const colBanniere = await db.query(`SELECT 1 FROM information_schema.columns WHERE table_name = 'churches' AND column_name = 'banniere_url'`);
check("colonne churches.banniere_url créée", colBanniere.rowCount === 1);

const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const egliseA = (await q(`INSERT INTO churches (code, code_fidele, name, city, status) VALUES ('ESC-T2-A', 'ESC-F-2001', 'Église T2 A', 'Abidjan', 'active') RETURNING id`))[0].id;
const egliseB = (await q(`INSERT INTO churches (code, code_fidele, name, city, status) VALUES ('ESC-T2-B', 'ESC-F-2002', 'Église T2 B', 'Abidjan', 'active') RETURNING id`))[0].id;
const adminId = (await q(`INSERT INTO users (email, password_hash, full_name, phone) VALUES ('admin-t2@example.ci', $1, 'Admin T2', '+225747100001') RETURNING id`, [hash]))[0].id;
await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'admin_eglise')`, [adminId, egliseA]);
const membreA = (await q(`INSERT INTO members (church_id, matricule, full_name, phone, email, status) VALUES ($1, 'M-T2-0001', 'Membre T2 A', '+225747100002', 'membre-t2-a@example.ci', 'actif') RETURNING id`, [egliseA]))[0].id;
const userMembreA = (await q(`INSERT INTO users (email, password_hash, full_name, phone, member_id) VALUES ('membre-t2-a@example.ci', $1, 'Membre T2 A', '+225747100002', $2) RETURNING id`, [hash, membreA]))[0].id;
await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'membre')`, [userMembreA, egliseA]);
const membreB = (await q(`INSERT INTO members (church_id, matricule, full_name, phone, email, status) VALUES ($1, 'M-T2-0001', 'Membre T2 B', '+225747100003', 'membre-t2-b@example.ci', 'actif') RETURNING id`, [egliseB]))[0].id;
const userMembreB = (await q(`INSERT INTO users (email, password_hash, full_name, phone, member_id) VALUES ('membre-t2-b@example.ci', $1, 'Membre T2 B', '+225747100003', $2) RETURNING id`, [hash, membreB]))[0].id;
await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'membre')`, [userMembreB, egliseB]);
const userSansMembre = (await q(`INSERT INTO users (email, password_hash, full_name, phone) VALUES ('sans-membre-t2@example.ci', $1, 'Sans Membre T2', '+225747100004') RETURNING id`, [hash]))[0].id;
await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'membre')`, [userSansMembre, egliseA]);
const annonce1 = (await q(`INSERT INTO announcements (church_id, title, body, broadcast) VALUES ($1, 'Annonce T2 1', 'Première annonce', FALSE) RETURNING id`, [egliseA]))[0].id;
const annonce2 = (await q(`INSERT INTO announcements (church_id, title, body, broadcast) VALUES ($1, 'Annonce T2 2', 'Deuxième annonce', FALSE) RETURNING id`, [egliseA]))[0].id;

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3113", DATABASE_URL: DB, JWT_SECRET: "test-secret-t2-espace-membre-2026" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ identifiant: email, password: "Test1234!", channel: "web" }) });
    return { status: r.status, d: await j(r) };
  }
  async function appel(token, method, chemin, corps) {
    const r = await fetch(`${BASE}${chemin}`, { method, headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` }, body: corps ? JSON.stringify(corps) : undefined });
    return { status: r.status, d: await j(r) };
  }

  console.log("Connexion :");
  let r = await login("admin-t2@example.ci");
  check("login admin 200", r.status === 200 && !!r.d.token, `status=${r.status}`);
  const jwtAdmin = r.d.token;
  r = await login("membre-t2-a@example.ci");
  check("login membre 200", r.status === 200 && !!r.d.token, `status=${r.status}`);
  const jwtMembreA = r.d.token;
  r = await login("membre-t2-b@example.ci");
  check("login membre église B 200", r.status === 200 && !!r.d.token, `status=${r.status}`);
  const jwtMembreB = r.d.token;
  r = await login("sans-membre-t2@example.ci");
  check("login membre sans membre lié 200", r.status === 200 && !!r.d.token, `status=${r.status}`);
  const jwtSansMembre = r.d.token;

  console.log("Photo et bannière, valeurs nulles au départ :");
  r = await appel(jwtMembreA, "GET", "/moi");
  check("GET /moi membre, photo_url null", r.status === 200 && r.d.user && r.d.user.photo_url === null, `status=${r.status} ${JSON.stringify(r.d.user || r.d).slice(0, 150)}`);
  check("GET /moi membre, banniere_url null", r.status === 200 && r.d.church && r.d.church.banniere_url === null, `status=${r.status}`);
  r = await appel(jwtMembreA, "GET", "/moi/carte");
  check("GET /moi/carte membre, photo_url null", r.status === 200 && r.d.member && r.d.member.photo_url === null, `status=${r.status}`);

  console.log("PATCH photo_url du membre :");
  r = await appel(jwtAdmin, "PATCH", `/membres/${membreA}`, { photo_url: "https://exemple.ci/photos/membre-t2-a.jpg" });
  check("PATCH photo_url valide 200", r.status === 200 && r.d.photo_url === "https://exemple.ci/photos/membre-t2-a.jpg", `status=${r.status} ${JSON.stringify(r.d).slice(0, 150)}`);
  r = await appel(jwtAdmin, "PATCH", `/membres/${membreA}`, { photo_url: "pas-une-url" });
  check("PATCH photo_url invalide 400", r.status === 400, `status=${r.status}`);
  r = await appel(jwtMembreA, "GET", "/moi");
  check("GET /moi membre, photo_url renseignée", r.status === 200 && r.d.user && r.d.user.photo_url === "https://exemple.ci/photos/membre-t2-a.jpg", `status=${r.status}`);
  r = await appel(jwtAdmin, "GET", `/membres/${membreA}`);
  check("GET /membres/:id admin, photo_url présente", r.status === 200 && r.d.photo_url === "https://exemple.ci/photos/membre-t2-a.jpg", `status=${r.status}`);

  console.log("PATCH banniere_url de l'église :");
  r = await appel(jwtAdmin, "PATCH", `/eglises/${egliseA}/profil`, { banniere_url: "https://exemple.ci/bannieres/eglise-t2-a.jpg" });
  check("PATCH banniere_url valide 200", r.status === 200 && r.d.banniere_url === "https://exemple.ci/bannieres/eglise-t2-a.jpg", `status=${r.status} ${JSON.stringify(r.d).slice(0, 150)}`);
  r = await appel(jwtAdmin, "PATCH", `/eglises/${egliseA}/profil`, { banniere_url: "pas-une-url" });
  check("PATCH banniere_url invalide 400", r.status === 400, `status=${r.status}`);
  r = await appel(jwtMembreA, "GET", "/moi");
  check("GET /moi membre, banniere_url renseignée", r.status === 200 && r.d.church && r.d.church.banniere_url === "https://exemple.ci/bannieres/eglise-t2-a.jpg", `status=${r.status}`);
  r = await appel(jwtMembreA, "GET", "/moi/carte");
  check("GET /moi/carte membre, banniere_url renseignée", r.status === 200 && r.d.church && r.d.church.banniere_url === "https://exemple.ci/bannieres/eglise-t2-a.jpg", `status=${r.status}`);

  console.log("Annonces, compteur de non lues :");
  r = await appel(jwtMembreA, "GET", "/moi/annonces");
  check("GET /moi/annonces, 2 annonces, non_lues 2", r.status === 200 && Array.isArray(r.d.annonces) && r.d.annonces.length === 2 && r.d.non_lues === 2, `status=${r.status} ${JSON.stringify(r.d).slice(0, 150)}`);
  r = await appel(jwtMembreA, "POST", `/moi/annonces/${annonce1}/lue`);
  check("POST lue annonce 1, 200", r.status === 200 && r.d.lue === true, `status=${r.status} ${JSON.stringify(r.d).slice(0, 150)}`);
  r = await appel(jwtMembreA, "GET", "/moi/annonces");
  check("après lecture, non_lues 1", r.status === 200 && r.d.non_lues === 1, `status=${r.status} non_lues=${r.d.non_lues}`);
  r = await appel(jwtMembreA, "POST", `/moi/annonces/${annonce1}/lue`);
  check("POST lue deux fois, idempotent 200", r.status === 200 && r.d.lue === true, `status=${r.status}`);
  r = await appel(jwtMembreA, "GET", "/moi/annonces");
  check("après double lecture, non_lues toujours 1", r.status === 200 && r.d.non_lues === 1, `status=${r.status} non_lues=${r.d.non_lues}`);
  r = await appel(jwtMembreA, "POST", "/moi/annonces/00000000-0000-0000-0000-000000000000/lue");
  check("POST lue annonce inexistante, 404", r.status === 404, `status=${r.status}`);
  r = await appel(jwtAdmin, "POST", `/moi/annonces/${annonce2}/lue`);
  check("POST lue par admin, 403 rôle membre requis", r.status === 403, `status=${r.status}`);

  console.log("Cloisonnement :");
  r = await appel(jwtMembreB, "POST", `/moi/annonces/${annonce1}/lue`);
  check("membre église B, annonce église A, 404", r.status === 404, `status=${r.status}`);
  r = await appel(jwtMembreB, "GET", "/moi/annonces");
  check("membre église B, 0 annonce, non_lues 0", r.status === 200 && Array.isArray(r.d.annonces) && r.d.annonces.length === 0 && r.d.non_lues === 0, `status=${r.status} ${JSON.stringify(r.d).slice(0, 150)}`);

  console.log("Membre sans membre lié :");
  r = await appel(jwtSansMembre, "GET", "/moi/annonces");
  check("sans membre lié, non_lues = toutes les annonces", r.status === 200 && r.d.non_lues === 2, `status=${r.status} non_lues=${r.d.non_lues}`);
  r = await appel(jwtSansMembre, "POST", `/moi/annonces/${annonce1}/lue`);
  check("sans membre lié, POST lue 404", r.status === 404, `status=${r.status} ${JSON.stringify(r.d).slice(0, 150)}`);
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
  await db.end();
}
console.log(`\nRésultat : ${ok} OK, ${ko} KO`);
process.exit(ko ? 1 : 0);
