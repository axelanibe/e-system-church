/* Test local T4 membres et familles (migration 019) — base PostgreSQL de
 * test seulement, jamais Render.
 * Usage :
 *   sudo -u postgres psql -c "CREATE DATABASE esc_membres_t4_test;"
 *   DATABASE_URL=<redacted> \
 *   node test-membres-t4.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations 001 à 018 par le vrai lanceur (`npm run migrate`, les 013 et
 * 017 sont réservées à Phoenix et n'existent pas encore), démarre l'API
 * (tsx server/src/index.ts, PORT 3113) et exerce les routes T4. Il ne
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

const db = new Client({ connectionString: DB });
await db.connect();
await db.query(readFileSync("../db/schema.sql", "utf8"));
await db.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`);
const MIGRATIONS_AVANT_019 = ["001_fonctionnalites_eglise.sql", "001_transferts_membre.sql", "002_vue_consolidee_recursive.sql", "003_mot_de_passe_acces_fidele.sql", "004_depenses_budget_stats.sql", "005_modules_eglise.sql", "005_rapports_nombres.sql", "006_organisation_catalogues.sql", "007_campagnes.sql", "008_attestations.sql", "009_codes_tutelle.sql", "010_codes_invitation.sql", "011_ajout_sexe_membre.sql", "011_checkins_enfants.sql", "012_connexion_telephone.sql", "014_jetons_rafraichissement.sql", "015_import_membres.sql", "016_types_attestations.sql", "018_espace_membre.sql"];
for (const f of MIGRATIONS_AVANT_019) {
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
  await db.query(`INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING`, [f.replace(/\.sql$/, "")]);
}
const mig = spawnSync("npx", ["tsx", "src/migrate.ts"], {
  cwd: process.cwd(),
  env: { ...process.env, DATABASE_URL: DB },
  encoding: "utf8",
});
console.log("Migration 019 :");
check("migrate applique la 019", mig.status === 0 && mig.stdout.includes("019_dates_evenements_vie"), `status=${mig.status} sortie=${(mig.stdout + mig.stderr).slice(0, 300)}`);
const colonnes = await db.query(`SELECT column_name FROM information_schema.columns WHERE table_name = 'members' AND column_name IN ('date_mariage', 'date_conversion')`);
check("colonnes date_mariage et date_conversion créées", colonnes.rowCount === 2, `trouvées=${colonnes.rowCount}`);

const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const egliseId = (await q(`INSERT INTO churches (code, code_fidele, name, city, status) VALUES ('ESC-T4-A', 'ESC-F-2001', 'Église T4 A', 'Abidjan', 'active') RETURNING id`))[0].id;
const userId = (await q(`INSERT INTO users (email, password_hash, full_name, phone) VALUES ('t4-test@example.ci', $1, 'T4 Test', '+225747123400') RETURNING id`, [hash]))[0].id;
await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'admin_eglise')`, [userId, egliseId]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3113", DATABASE_URL: DB, JWT_SECRET: "test-secret-t4-membres-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const login = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ identifiant: "t4-test@example.ci", password: "Test1234!", channel: "web" }) });
  const session = await j(login);
  check("login admin 200", login.status === 200 && !!session.token, `status=${login.status}`);
  const H = { "Content-Type": "application/json", Authorization: `Bearer ${session.token}` };
  const post = async (chemin, corps) => { const r = await fetch(`${BASE}${chemin}`, { method: "POST", headers: H, body: JSON.stringify(corps) }); return { status: r.status, d: await j(r) }; };
  const patch = async (chemin, corps) => { const r = await fetch(`${BASE}${chemin}`, { method: "PATCH", headers: H, body: JSON.stringify(corps) }); return { status: r.status, d: await j(r) }; };
  const get = async (chemin) => { const r = await fetch(`${BASE}${chemin}`, { headers: H }); return { status: r.status, d: await j(r) }; };

  // Anniversaire dans 5 jours, année 1990 : date calculée, jamais inventée
  // comme fait réel, c'est une donnée de test.
  const dans5 = new Date(Date.now() + 5 * 86400000);
  const mois = String(dans5.getMonth() + 1).padStart(2, "0");
  const jour = String(dans5.getDate()).padStart(2, "0");
  const naissance = `1990-${mois}-${jour}`;

  console.log("Création avec dates d'événements de vie :");
  let r = await post("/membres", { full_name: "Jean T4", phone: "+22507000001", birth_date: naissance, date_mariage: "2015-06-14", date_conversion: "2010-03-02" });
  check("POST /membres 201", r.status === 201, `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);
  const membreId = r.d.id;
  // Les colonnes DATE reviennent en ISO complet (« 2015-06-14T00:00:00.000Z »),
  // comme birth_date depuis toujours : on compare le préfixe.
  check("dates renvoyées", String(r.d.date_mariage).startsWith("2015-06-14") && String(r.d.date_conversion).startsWith("2010-03-02"), JSON.stringify(r.d).slice(0, 200));

  r = await post("/membres", { full_name: "Marie T4", phone: "+22507000002" });
  check("membre sans dates 201", r.status === 201, `status=${r.status}`);
  const membreSansDates = r.d.id;
  check("dates nulles, jamais inventées", r.d.date_mariage == null && r.d.date_conversion == null, JSON.stringify(r.d).slice(0, 200));

  console.log("Modification des dates :");
  r = await patch(`/membres/${membreSansDates}`, { full_name: "Marie T4", phone: "+22507000002", date_mariage: "2018-12-01", date_conversion: null });
  check("PATCH dates 200", r.status === 200 && String(r.d.date_mariage).startsWith("2018-12-01") && r.d.date_conversion == null, `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);

  console.log("Statut ancien :");
  r = await post(`/membres/${membreId}/statut`, { statut: "ancien", motif: "Déménagement" });
  check("POST /membres/:id/statut ancien 200", r.status === 200, `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);
  r = await get(`/membres/${membreId}`);
  check("statut riche ancien, statut simple inactif", r.d.statut_riche === "ancien" && r.d.status === "inactif", JSON.stringify(r.d).slice(0, 200));
  r = await get("/membres?status=ancien");
  const liste = r.d.membres ?? [];
  check("filtre status=ancien retrouve le membre", liste.some((m) => m.id === membreId), `trouvés=${liste.length}`);
  r = await get("/membres?status=actif");
  const actifs = r.d.membres ?? [];
  check("filtre status=actif ne retrouve pas l'ancien", !actifs.some((m) => m.id === membreId), `trouvés=${actifs.length}`);

  console.log("Anniversaires proches :");
  r = await get("/membres/anniversaires?jours=30");
  const annivs = r.d.anniversaires ?? [];
  const cible = annivs.find((a) => a.id === membreId);
  check("anniversaire dans 5 jours listé", !!cible && cible.jours_restants === 5 && cible.age_atteint === dans5.getFullYear() - 1990, cible ? JSON.stringify(cible).slice(0, 200) : "absent");
  r = await get("/membres/anniversaires?jours=2");
  const annivs2 = r.d.anniversaires ?? [];
  check("anniversaire hors fenêtre absent", !annivs2.some((a) => a.id === membreId), `trouvés=${annivs2.length}`);

  console.log("Fréquentation :");
  const culteId = (await q(`INSERT INTO cultes (church_id, titre, date_heure, lieu) VALUES ($1, 'Culte du dimanche', now() - interval '2 days', 'Abidjan') RETURNING id`, [egliseId]))[0].id;
  r = await post("/presences", { culte_id: culteId, member_id: membreId, statut: "present", mode: "scan_qr" });
  check("POST /presences 201", r.status === 201, `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);
  r = await get(`/membres/${membreId}/frequentation`);
  check("fréquentation 1 pointage, 1 présent", r.status === 200 && r.d.total === 1 && r.d.presents === 1, `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);
  check("pointage titré Culte du dimanche", r.d.items?.[0]?.titre === "Culte du dimanche" && r.d.items?.[0]?.mode === "scan_qr", JSON.stringify(r.d.items).slice(0, 200));
  r = await get(`/membres/${membreSansDates}/frequentation`);
  check("fréquentation vide : 0 sur 0", r.status === 200 && r.d.total === 0 && r.d.presents === 0 && Array.isArray(r.d.items) && r.d.items.length === 0, `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);

  console.log("Cas d'erreur :");
  r = await post(`/membres/${membreId}/statut`, { statut: "inexistant" });
  check("statut invalide rejeté", r.status === 400, `status=${r.status}`);
  r = await get("/membres/anniversaires?jours=200");
  check("jours=200 plafonné à 90", r.status === 200 && r.d.jours === 90, `status=${r.status} jours=${r.d.jours}`);
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
}
await db.end();

console.log(`\n${ok} OK, ${ko} KO`);
if (ko > 0) process.exit(1);
