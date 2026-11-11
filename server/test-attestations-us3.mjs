/* Test local US3 — base PostgreSQL de test seulement, jamais Render.
 * Usage : DATABASE_URL=postgres://postgres@localhost:5432/esc_us3_test \
 *   node test-attestations-us3.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations, démarre l'API (tsx server/src/index.ts, PORT 3101) et exerce
 * les routes. Il ne supprime pas la base : la supprimer après, à la main.
 */
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3101";
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
for (const f of ["001_fonctionnalites_eglise.sql","001_transferts_membre.sql","002_vue_consolidee_recursive.sql","003_mot_de_passe_acces_fidele.sql","004_depenses_budget_stats.sql","005_modules_eglise.sql","005_rapports_nombres.sql","006_organisation_catalogues.sql","007_attestations.sql"]) {
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const churchA = (await q(`INSERT INTO churches (code,name,status) VALUES ('ESC-TEST-A','Église Test A','active') RETURNING id`))[0].id;
const churchB = (await q(`INSERT INTO churches (code,name,status) VALUES ('ESC-TEST-B','Église Test B','active') RETURNING id`))[0].id;
async function user(email, church, role, memberId = null) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name,member_id) VALUES ($1,$2,$3,$4) RETURNING id`, [email, hash, email, memberId]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [u, church, role]);
  return u;
}
async function member(church, matricule, nom) {
  return (await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,$2,$3,'actif') RETURNING id`, [church, matricule, nom]))[0].id;
}
const m1 = await member(churchA, "M-0001", "KOFFI JEAN");
const m2 = await member(churchA, "M-0002", "KOUASSI AMINATA");
const m3 = await member(churchA, "M-0003", "YAO SERGE");
const tresA = await user("tresorier-a@test.ci", churchA, "tresorier");
const membre1 = await user("membre1@test.ci", churchA, "membre", m1);
const tresB = await user("tresorier-b@test.ci", churchB, "tresorier");
async function contrib(church, memberId, type, amount, status, date) {
  await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status,created_at) VALUES ($1,$2,$3,$4,'especes',$5,$6)`, [church, memberId, type, amount, status, date]);
}
await contrib(churchA, m1, "dime", 10000, "confirme", "2026-03-01");
await contrib(churchA, m1, "offrande", 5000, "confirme", "2026-05-10");
await contrib(churchA, m1, "don", 2000, "en_attente", "2026-06-01");
await contrib(churchA, m1, "depense", 99999, "confirme", "2026-06-02");
await contrib(churchA, m2, "don", 30000, "confirme", "2026-04-15");
await contrib(churchA, m2, "don", 40000, "confirme", "2025-12-20");
await contrib(churchA, null, "don", 15000, "confirme", "2026-02-01"); // anonyme
await contrib(churchA, m3, "don", 7000, "annule", "2026-03-03");

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3101", DATABASE_URL: DB, JWT_SECRET: "test-secret-us3-32-caracteres-minimum" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokA = await login("tresorier-a@test.ci");
  const tokM1 = await login("membre1@test.ci");
  const tokB = await login("tresorier-b@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };

  console.log("Génération 2026 :");
  let r = await fetch(`${BASE}/attestations/generer`, { method: "POST", headers: H(tokA), body: JSON.stringify({ annee: 2026 }) });
  let d = await j(r);
  check("génération 201", r.status === 201, String(r.status));
  check("2 attestations créées (anonyme, en attente, dépense, annulé, 2025 exclus)", (d.creees?.length ?? -1) === 2, JSON.stringify(d));
  const a1 = d.creees.find((a) => a.member_id === m1);
  const a2 = d.creees.find((a) => a.member_id === m2);
  check("M1 total 15000, 2 dons", a1?.total_fcfa === 15000 && a1?.nb_dons === 2, JSON.stringify(a1));
  check("M2 total 30000, 1 don", a2?.total_fcfa === 30000 && a2?.nb_dons === 1, JSON.stringify(a2));
  check("numéros uniques ATT-2026-0001/0002", new Set([a1?.numero, a2?.numero]).size === 2 && /^ATT-2026-000\d$/.test(a1?.numero ?? ""), `${a1?.numero} ${a2?.numero}`);
  r = await fetch(`${BASE}/attestations/generer`, { method: "POST", headers: H(tokA), body: JSON.stringify({ annee: 2026 }) });
  d = await j(r);
  check("régénération : 0 créée, 2 ignorées", d.creees?.length === 0 && d.ignorees === 2, JSON.stringify(d));

  console.log("Liste et PDF :");
  r = await fetch(`${BASE}/attestations?annee=2026`, { headers: H(tokA) });
  d = await j(r);
  check("liste trésorier : 2", d.attestations?.length === 2, JSON.stringify(d));
  r = await fetch(`${BASE}/attestations/${a1.id}/pdf`, { headers: H(tokA) });
  const pdf = Buffer.from(await r.arrayBuffer());
  check("PDF 200, commence par %PDF", r.status === 200 && pdf.subarray(0, 5).toString().startsWith("%PDF"), String(r.status));
  check("PDF mention sans valeur fiscale", pdf.toString("latin1").includes("aucune valeur fiscale"));
  check("PDF total figé 15 000 FCFA", pdf.toString("latin1").includes("15 000 FCFA"));

  console.log("Isolation membre et église :");
  r = await fetch(`${BASE}/moi/attestations`, { headers: H(tokM1) });
  d = await j(r);
  check("membre ne voit que la sienne (1)", d.attestations?.length === 1 && d.attestations[0].id === a1.id, JSON.stringify(d));
  r = await fetch(`${BASE}/attestations/${a2.id}/pdf`, { headers: H(tokM1) });
  check("membre : PDF d'un autre membre 403", r.status === 403, String(r.status));
  r = await fetch(`${BASE}/attestations/${a1.id}/pdf`, { headers: H(tokM1) });
  check("membre : son propre PDF 200", r.status === 200, String(r.status));
  r = await fetch(`${BASE}/attestations?annee=2026`, { headers: H(tokB) });
  d = await j(r);
  check("autre église : liste vide", d.attestations?.length === 0, JSON.stringify(d));
  r = await fetch(`${BASE}/attestations/${a1.id}/pdf`, { headers: H(tokB) });
  check("autre église : PDF 403", r.status === 403, String(r.status));

  console.log("Correction :");
  await contrib(churchA, m1, "don", 5000, "confirme", "2026-07-01");
  r = await fetch(`${BASE}/attestations/${a1.id}/corriger`, { method: "POST", headers: H(tokA), body: JSON.stringify({ motif: "Don de juillet ajouté" }) });
  d = await j(r);
  check("correction 201, nouveau numéro", r.status === 201 && d.numero === "ATT-2026-0003", JSON.stringify(d));
  check("nouvelle total 20000, 3 dons, remplace l'ancienne", d.total_fcfa === 20000 && d.nb_dons === 3 && d.remplace_id === a1.id, JSON.stringify(d));
  r = await fetch(`${BASE}/attestations?annee=2026`, { headers: H(tokA) });
  d = await j(r);
  const old = d.attestations.find((a) => a.id === a1.id);
  check("ancienne annulée", old?.statut === "annulee", JSON.stringify(old));
  check("PDF ancienne annulée 409", (await fetch(`${BASE}/attestations/${a1.id}/pdf`, { headers: H(tokA) })).status === 409);
  r = await fetch(`${BASE}/moi/attestations`, { headers: H(tokM1) });
  d = await j(r);
  check("membre voit la nouvelle (total 20000)", d.attestations?.length === 1 && d.attestations[0].total_fcfa === 20000, JSON.stringify(d));
  const audit = await q(`SELECT action FROM audit_logs WHERE church_id=$1 AND action LIKE 'attestation.%' ORDER BY created_at`, [churchA]);
  const acts = audit.map((x) => x.action);
  check("audit : generee et corrige tracées", acts.includes("attestation.generee") && acts.includes("attestation.corrige"), acts.join(","));
  console.log(`\n${ok} OK, ${ko} KO`);
  process.exitCode = ko === 0 ? 0 : 1;
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch { server.kill(); }
  await db.end();
}
