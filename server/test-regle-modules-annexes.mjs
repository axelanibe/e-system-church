/* Test local de la règle modules et annexes (11/11/2026) — base
 * PostgreSQL de test seulement, jamais Render.
 * Usage : DATABASE_URL=<redacted>
 *   node test-regle-modules-annexes.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations, démarre l'API (tsx server/src/index.ts, PORT 3106) et exerce
 * les routes. Il ne supprime pas la base : la supprimer après, à la main.
 *
 * Règle 1 : tous les modules sont affichés pour toutes les églises, plus
 * de choix d'activation US1, plus de garde 403 `module_desactive`, les
 * routes GET /modules et PATCH /modules/:code n'existent plus.
 * Règle 2 : une annexe ne peut pas avoir d'annexe. Seule une église mère
 * crée une sous-église, génère un code de tutelle ou accepte un
 * rattachement (403 `annexe_sans_annexe`). Les cellules restent possibles
 * pour une annexe.
 */
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3106";
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
for (const f of ["001_fonctionnalites_eglise.sql","001_transferts_membre.sql","002_vue_consolidee_recursive.sql","003_mot_de_passe_acces_fidele.sql","004_depenses_budget_stats.sql","005_modules_eglise.sql","005_rapports_nombres.sql","006_organisation_catalogues.sql","007_campagnes.sql","008_attestations.sql","009_codes_tutelle.sql","010_codes_invitation.sql","011_checkins_enfants.sql","011_ajout_sexe_membre.sql"]) {
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const church = async (code, name, parent = null) =>
  (await q(`INSERT INTO churches (code,code_fidele,name,city,status,parent_church_id) VALUES ($1,$2,$3,'Abidjan','active',$4) RETURNING id`, [code, `${code}-F`, name, parent]))[0].id;
const mere = await church("ESC-MERE01", "Église Mère Test");
const annexeA = await church("ESC-ANNX01", "Annexe de Yopougon", mere);
const egliseB = await church("ESC-EGLB01", "Église Indépendante B");
const egliseC = await church("ESC-EGLC01", "Église Étrangère C");
async function admin(email, ch) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name) VALUES ($1,$2,$3) RETURNING id`, [email, hash, email]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,'admin_eglise')`, [u, ch]);
  return u;
}
await admin("admin-mere@test.ci", mere);
await admin("admin-annexe@test.ci", annexeA);
await admin("admin-b@test.ci", egliseB);
await admin("admin-c@test.ci", egliseC);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3106", DATABASE_URL: DB, JWT_SECRET: "test-secret-regle-modules-32-car" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokM = await login("admin-mere@test.ci");
  const tokA = await login("admin-annexe@test.ci");
  const tokB = await login("admin-b@test.ci");
  const tokC = await login("admin-c@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };

  console.log("Règle 1 : tous les modules actifs, plus de garde :");
  let r = await fetch(`${BASE}/annonces`, { headers: H(tokB) });
  check("GET /annonces B (jamais activé) : 200, pas 403", r.status === 200, String(r.status));
  r = await fetch(`${BASE}/cultes`, { headers: H(tokB) });
  check("GET /cultes B (jamais activé) : 200, pas 403", r.status === 200, String(r.status));
  r = await fetch(`${BASE}/cellules`, { headers: H(tokB) });
  check("GET /cellules B (jamais activé) : 200, pas 403", r.status === 200, String(r.status));
  r = await fetch(`${BASE}/modules`, { headers: H(tokB) });
  check("GET /modules : 404, route supprimée", r.status === 404, String(r.status));
  r = await fetch(`${BASE}/modules/cultes`, { method: "PATCH", headers: H(tokB), body: JSON.stringify({ actif: false }) });
  check("PATCH /modules/cultes : 404, route supprimée", r.status === 404, String(r.status));

  console.log("Règle 2 : une annexe ne crée pas de sous-église :");
  r = await fetch(`${BASE}/eglises`, { method: "POST", headers: H(tokA), body: JSON.stringify({ name: "Sous-annexe Test", city: "Abidjan" }) });
  let d = await j(r);
  check("POST /eglises par l'annexe : 403 annexe_sans_annexe", r.status === 403 && d.error === "annexe_sans_annexe", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/eglises`, { method: "POST", headers: H(tokM), body: JSON.stringify({ name: "Sous-église Test", city: "Abidjan" }) });
  d = await j(r);
  check("POST /eglises par la mère : 201", r.status === 201, `${r.status} ${JSON.stringify(d)}`);
  const sousEgliseM = d.id;

  console.log("Règle 2 : une annexe ne génère pas de code de tutelle :");
  r = await fetch(`${BASE}/codes-tutelle`, { method: "POST", headers: H(tokA), body: JSON.stringify({}) });
  d = await j(r);
  check("POST /codes-tutelle par l'annexe : 403 annexe_sans_annexe", r.status === 403 && d.error === "annexe_sans_annexe", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/codes-tutelle`, { method: "POST", headers: H(tokM), body: JSON.stringify({}) });
  d = await j(r);
  check("POST /codes-tutelle par la mère : 201", r.status === 201, `${r.status} ${JSON.stringify(d)}`);

  console.log("Règle 2 : on ne se rattache pas à une annexe :");
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokB), body: JSON.stringify({ parent_code: "ESC-ANNX01" }) });
  d = await j(r);
  check("demande vers l'annexe A : 403 annexe_sans_annexe", r.status === 403 && d.error === "annexe_sans_annexe", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokB), body: JSON.stringify({ parent_code: "ESC-MERE01" }) });
  d = await j(r);
  check("demande vers la mère : 201 en_attente", r.status === 201 && d.status === "en_attente", `${r.status} ${JSON.stringify(d)}`);
  const demandeB = d.id;

  console.log("Règle 2 : une annexe n'accepte pas de rattachement :");
  // Demande adressée à l'annexe, créée directement en base (la route
  // refuse désormais de la créer) : l'acceptation doit être refusée.
  const demandeVersA = (await q(`INSERT INTO rattachements (church_id,parent_church_id,status) VALUES ($1,$2,'en_attente') RETURNING id`, [egliseC, annexeA]))[0].id;
  r = await fetch(`${BASE}/rattachements/${demandeVersA}/accepter`, { method: "POST", headers: H(tokA), body: JSON.stringify({}) });
  d = await j(r);
  check("acceptation par l'annexe : 403 annexe_sans_annexe", r.status === 403 && d.error === "annexe_sans_annexe", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/rattachements/${demandeVersA}/refuser`, { method: "POST", headers: H(tokA), body: JSON.stringify({}) });
  d = await j(r);
  check("refus par l'annexe : 200 refusee", r.status === 200 && d.status === "refusee", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/rattachements/${demandeB}/accepter`, { method: "POST", headers: H(tokM), body: JSON.stringify({}) });
  d = await j(r);
  check("acceptation par la mère : 200 acceptee", r.status === 200 && d.status === "acceptee", `${r.status} ${JSON.stringify(d)}`);
  const parentB = (await q(`SELECT parent_church_id FROM churches WHERE id=$1`, [egliseB]))[0];
  check("B rattachée à la mère", parentB.parent_church_id === mere, JSON.stringify(parentB));

  console.log("Cellules : toujours possibles pour une annexe :");
  r = await fetch(`${BASE}/cellules`, { method: "POST", headers: H(tokA), body: JSON.stringify({ nom: "Cellule Yopougon" }) });
  d = await j(r);
  check("POST /cellules par l'annexe : 201", r.status === 201, `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/cellules`, { headers: H(tokA) });
  d = await j(r);
  check("GET /cellules de l'annexe : 1 cellule", d.total === 1, JSON.stringify(d).slice(0, 200));

  console.log("Arbre : la sous-église de la mère est bien là, pas de sous-annexe :");
  r = await fetch(`${BASE}/eglises/arbre`, { headers: H(tokM) });
  d = await j(r);
  const noms = JSON.stringify(d.arbre);
  check("arbre mère : sous-église créée présente", noms.includes("Sous-église Test"), noms.slice(0, 200));
  check("arbre mère : aucune sous-annexe", !noms.includes("Sous-annexe Test"), noms.slice(0, 200));

  console.log(`\n${ok} OK, ${ko} KO`);
  process.exitCode = ko === 0 ? 0 : 1;
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch { server.kill(); }
  await db.end();
}
