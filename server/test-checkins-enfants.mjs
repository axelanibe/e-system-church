/* Test local ECODIM double QR — base PostgreSQL 16 de test seulement, jamais Render.
 * Usage : DATABASE_URL=<redacted>
 *   node test-checkins-enfants.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations, démarre l'API (tsx server/src/index.ts, PORT 3103) et exerce
 * les routes. Il ne supprime pas la base : la supprimer après, à la main.
 */
import { spawn } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3103";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const db = new Client({ connectionString: DB });
await db.connect();
// Schéma + migrations (même ordre que migrate.ts, sans toucher à Render).
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of readdirSync("../db/migrations").sort()) {
  if (f.endsWith(".sql")) await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const churchA = (await q(`INSERT INTO churches (code,code_fidele,name,status) VALUES ('ESC-TEST-A','ESC-F-TESTA','Église Test A','active') RETURNING id`))[0].id;
const churchB = (await q(`INSERT INTO churches (code,code_fidele,name,status) VALUES ('ESC-TEST-B','ESC-F-TESTB','Église Test B','active') RETURNING id`))[0].id;
// Plus besoin d'activer le module enfants : tous les modules sont actifs
// pour toutes les églises (règle du 11/11/2026).
async function user(email, church, role) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name) VALUES ($1,$2,$3) RETURNING id`, [email, hash, email]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [u, church, role]);
  return u;
}
async function member(church, matricule, nom) {
  return (await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,$2,$3,'actif') RETURNING id`, [church, matricule, nom]))[0].id;
}
const parentA = await member(churchA, "P-0001", "KOFFI JEAN");
const enfantA = await member(churchA, "E-0001", "KOFFI MARIE");
const enfantB = await member(churchB, "E-0002", "YAO LUC");
await q(`INSERT INTO liens_parent_enfant (church_id,parent_member_id,enfant_member_id,lien,statut) VALUES ($1,$2,$3,'pere','valide')`, [churchA, parentA, enfantA]);
await user("admin-a@test.ci", churchA, "admin_eglise");
await user("admin-b@test.ci", churchB, "admin_eglise");

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3103", DATABASE_URL: DB, JWT_SECRET: "test-secret-ecodim-32-caracteres-min" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokA = await login("admin-a@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };

  console.log("Check-in jumelé :");
  let r = await fetch(`${BASE}/checkins-enfants/checkin`, { method: "POST", headers: H(tokA), body: JSON.stringify({ enfant_member_id: enfantA, parent_member_id: parentA, code_parent: "P-0001", code_enfant: "KIDS-AB12", salle: "Salle 2", allergie: "Arachides" }) });
  let d = await j(r);
  check("check-in jumelé 201", r.status === 201, `${r.status} ${JSON.stringify(d)}`);
  check("statut IN_CLASS, code et salle conservés", d.statut === "IN_CLASS" && d.code_enfant === "KIDS-AB12" && d.salle === "Salle 2", JSON.stringify(d));
  const id = d.id;
  r = await fetch(`${BASE}/checkins-enfants/checkin`, { method: "POST", headers: H(tokA), body: JSON.stringify({ enfant_member_id: enfantA, parent_member_id: parentA, code_parent: "P-0001", code_enfant: "KIDS-CD34" }) });
  check("deuxième check-in le même jour refusé (409)", r.status === 409, String(r.status));

  console.log("Autre église :");
  r = await fetch(`${BASE}/checkins-enfants/checkin`, { method: "POST", headers: H(tokA), body: JSON.stringify({ enfant_member_id: enfantB, parent_member_id: parentA, code_parent: "P-0001", code_enfant: "KIDS-EF56" }) });
  check("enfant d'une autre église 403", r.status === 403, String(r.status));

  console.log("Alerte silencieuse :");
  r = await fetch(`${BASE}/checkins-enfants/${id}/alerte`, { method: "POST", headers: H(tokA), body: JSON.stringify({ message: "Votre enfant vous attend." }) });
  d = await j(r);
  check("alerte 200, drapeau posé", r.status === 200 && d.alerte === true, `${r.status} ${JSON.stringify(d)}`);

  console.log("Liste du jour :");
  r = await fetch(`${BASE}/checkins-enfants/jour`, { headers: H(tokA) });
  d = await j(r);
  check("1 présent du jour, noms joints", r.status === 200 && d.total === 1 && d.items[0].enfant_nom === "KOFFI MARIE", JSON.stringify(d));

  console.log("Sortie sécurisée :");
  r = await fetch(`${BASE}/checkins-enfants/${id}/sortie`, { method: "POST", headers: H(tokA), body: JSON.stringify({ code_enfant: "KIDS-ZZ99", code_parent: "P-0001" }) });
  check("sortie avec mauvais code refusée (403)", r.status === 403, String(r.status));
  r = await fetch(`${BASE}/checkins-enfants/${id}/sortie`, { method: "POST", headers: H(tokA), body: JSON.stringify({ code_enfant: "KIDS-AB12", code_parent: "P-0001" }) });
  d = await j(r);
  check("sortie avec le bon code 200, CHECKED_OUT", r.status === 200 && d.statut === "CHECKED_OUT", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/checkins-enfants/${id}/sortie`, { method: "POST", headers: H(tokA), body: JSON.stringify({ code_enfant: "KIDS-AB12", code_parent: "P-0001" }) });
  check("sortie deux fois refusée (409)", r.status === 409, String(r.status));

  const audit = await q(`SELECT action FROM audit_logs WHERE church_id=$1 AND action LIKE 'checkin_enfant.%' ORDER BY created_at`, [churchA]);
  const acts = audit.map((x) => x.action);
  check("audit : check-in, alerte et sortie tracés", acts.includes("checkin_enfant.cree") && acts.includes("checkin_enfant.alerte") && acts.includes("checkin_enfant.sortie"), acts.join(","));

  console.log(`\n${ok} OK, ${ko} KO`);
  process.exitCode = ko === 0 ? 0 : 1;
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch { server.kill(); }
  await db.end();
}
