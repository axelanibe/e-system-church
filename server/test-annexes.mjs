/* Test local Mes annexes + codes de tutelle (migration 009) — base
 * PostgreSQL de test seulement, jamais Render.
 * Usage : DATABASE_URL=<redacted>
 *   node test-annexes.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis les
 * migrations, démarre l'API (tsx server/src/index.ts, PORT 3102) et exerce
 * les routes. Il ne supprime pas la base : la supprimer après, à la main.
 */
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3105";
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
for (const f of ["001_fonctionnalites_eglise.sql","001_transferts_membre.sql","002_vue_consolidee_recursive.sql","003_mot_de_passe_acces_fidele.sql","004_depenses_budget_stats.sql","005_modules_eglise.sql","005_rapports_nombres.sql","006_organisation_catalogues.sql","007_campagnes.sql","008_attestations.sql","009_codes_tutelle.sql"]) {
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const church = async (code, name) =>
  (await q(`INSERT INTO churches (code,name,city,status) VALUES ($1,$2,'Abidjan','active') RETURNING id`, [code, name]))[0].id;
const mere = await church("ESC-MERE01", "Église Mère Test");
const annexeA = await church("ESC-ANNX01", "Annexe de Yopougon");
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
const mA = (await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,'M-0001','KOFFI JEAN','actif') RETURNING id`, [annexeA]))[0].id;
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status) VALUES ($1,$2,'dime',10000,'especes','confirme')`, [annexeA, mA]);
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status) VALUES ($1,$2,'depense',2000,'especes','confirme')`, [annexeA, mA]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3105", DATABASE_URL: DB, JWT_SECRET: "test-secret-annexes-32-caracteres-min" }, stdio: "ignore", detached: true });
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
  const modulesActifs = async (ch) => (await q(`SELECT count(*)::int AS n FROM eglise_modules WHERE church_id=$1 AND actif=true`, [ch]))[0].n;

  console.log("Codes de tutelle :");
  let r = await fetch(`${BASE}/codes-tutelle`, { method: "POST", headers: H(tokM), body: JSON.stringify({}) });
  let d = await j(r);
  check("création 201, code ESC-T-…", r.status === 201 && /^ESC-T-[A-Z0-9]{6}$/.test(d.code ?? ""), JSON.stringify(d));
  const code1 = d.code, code1Id = d.id;
  r = await fetch(`${BASE}/codes-tutelle`, { headers: H(tokM) });
  d = await j(r);
  check("liste : 1 code actif", d.codes?.length === 1 && d.codes[0].status === "actif", JSON.stringify(d));

  console.log("Demande par code de tutelle :");
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokA), body: JSON.stringify({ code_tutelle: code1 }) });
  d = await j(r);
  check("demande 201 en_attente", r.status === 201 && d.status === "en_attente", JSON.stringify(d));
  const demandeId = d.id;
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokB), body: JSON.stringify({ code_tutelle: code1 }) });
  check("deuxième usage pendant attente : 409", r.status === 409, String(r.status));
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokB), body: JSON.stringify({ code_tutelle: "ESC-T-XXXXXX" }) });
  d = await j(r);
  check("code inconnu : 400 code_tutelle_invalide", r.status === 400 && d.error === "code_tutelle_invalide", JSON.stringify(d));

  console.log("Acceptation : invalidation + modules automatiques :");
  check("modules de A avant : 0 actif", (await modulesActifs(annexeA)) === 0);
  r = await fetch(`${BASE}/rattachements/${demandeId}/accepter`, { method: "POST", headers: H(tokM), body: JSON.stringify({}) });
  d = await j(r);
  check("acceptation 200 acceptee", r.status === 200 && d.status === "acceptee", JSON.stringify(d));
  check("modules de A après : 13 actifs", (await modulesActifs(annexeA)) === 13, String(await modulesActifs(annexeA)));
  const codeRow = (await q(`SELECT status, used_by FROM codes_tutelle WHERE id=$1`, [code1Id]))[0];
  check("code passé utilise, used_by = A", codeRow.status === "utilise" && codeRow.used_by === annexeA, JSON.stringify(codeRow));
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokB), body: JSON.stringify({ code_tutelle: code1 }) });
  d = await j(r);
  check("deuxième usage après acceptation : 400 code_tutelle_invalide", r.status === 400 && d.error === "code_tutelle_invalide", JSON.stringify(d));
  const auditA = (await q(`SELECT action FROM audit_logs WHERE church_id=$1`, [annexeA])).map((x) => x.action);
  check("audit A : modules.actives_tutelle", auditA.includes("modules.actives_tutelle"), auditA.join(","));
  const auditM = (await q(`SELECT action FROM audit_logs WHERE church_id=$1`, [mere])).map((x) => x.action);
  check("audit mère : codes_tutelle.cree et utilise", auditM.includes("codes_tutelle.cree") && auditM.includes("codes_tutelle.utilise"), auditM.join(","));

  console.log("Mes annexes :");
  r = await fetch(`${BASE}/annexes`, { headers: H(tokM) });
  d = await j(r);
  check("liste : 1 annexe, chiffres A", d.annexes?.length === 1 && d.annexes[0].eglise_code === "ESC-ANNX01" && d.annexes[0].membres_actifs === 1 && d.annexes[0].total_fcfa === 10000, JSON.stringify(d));
  r = await fetch(`${BASE}/annexes?q=Yopougon`, { headers: H(tokM) });
  d = await j(r);
  check("recherche Yopougon : 1", d.annexes?.length === 1, JSON.stringify(d));
  r = await fetch(`${BASE}/annexes?q=Bouaké`, { headers: H(tokM) });
  d = await j(r);
  check("recherche Bouaké : 0", d.annexes?.length === 0, JSON.stringify(d));
  r = await fetch(`${BASE}/annexes/${annexeA}`, { headers: H(tokM) });
  d = await j(r);
  check("détail A : 1 membre, 10000 entrées, 2000 dépenses, 16 modules dont 13 actifs + 3 noyau", r.status === 200 && d.membres_actifs === 1 && d.total_fcfa === 10000 && d.depenses_fcfa === 2000 && d.modules?.length === 16 && d.modules.filter((m) => m.actif).length === 16, JSON.stringify(d).slice(0, 300));
  r = await fetch(`${BASE}/annexes/${egliseC}`, { headers: H(tokM) });
  check("détail d'une non-annexe : 403", r.status === 403, String(r.status));
  r = await fetch(`${BASE}/annexes`, { headers: H(tokB) });
  d = await j(r);
  check("B sans annexe : liste vide", d.annexes?.length === 0, JSON.stringify(d));

  console.log("US1 préservé pour les indépendantes, sous-église directe :");
  check("modules de B : 0 actif", (await modulesActifs(egliseB)) === 0);
  r = await fetch(`${BASE}/modules`, { headers: H(tokB) });
  d = await j(r);
  check("GET /modules B : 13 activables inactifs", d.modules?.filter((m) => !m.noyau && m.actif).length === 0, JSON.stringify(d).slice(0, 200));
  r = await fetch(`${BASE}/eglises`, { method: "POST", headers: H(tokM), body: JSON.stringify({ name: "Sous-église Test", city: "Abidjan" }) });
  d = await j(r);
  check("création sous-église 201", r.status === 201, JSON.stringify(d));
  check("modules de la sous-église : 13 actifs", (await modulesActifs(d.id)) === 13, String(await modulesActifs(d.id)));

  console.log("Refus : le code reste actif :");
  r = await fetch(`${BASE}/codes-tutelle`, { method: "POST", headers: H(tokM), body: JSON.stringify({}) });
  d = await j(r);
  const code2 = d.code, code2Id = d.id;
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokB), body: JSON.stringify({ code_tutelle: code2 }) });
  d = await j(r);
  const demandeB = d.id;
  r = await fetch(`${BASE}/rattachements/${demandeB}/refuser`, { method: "POST", headers: H(tokM), body: JSON.stringify({}) });
  d = await j(r);
  check("refus 200 refusee", r.status === 200 && d.status === "refusee", `${r.status} ${JSON.stringify(d)}`);
  const code2Row = (await q(`SELECT status FROM codes_tutelle WHERE id=$1`, [code2Id]))[0];
  check("code2 toujours actif après refus", code2Row.status === "actif", JSON.stringify(code2Row));
  check("modules de B toujours 0 après refus", (await modulesActifs(egliseB)) === 0);
  r = await fetch(`${BASE}/codes-tutelle/${code2Id}/annuler`, { method: "POST", headers: H(tokM), body: JSON.stringify({}) });
  d = await j(r);
  check("annulation code2 200 annule", r.status === 200 && d.status === "annule", JSON.stringify(d));
  r = await fetch(`${BASE}/rattachements`, { method: "POST", headers: H(tokB), body: JSON.stringify({ code_tutelle: code2 }) });
  d = await j(r);
  check("code annulé : 400 code_tutelle_invalide", r.status === 400 && d.error === "code_tutelle_invalide", JSON.stringify(d));

  console.log(`\n${ok} OK, ${ko} KO`);
  process.exitCode = ko === 0 ? 0 : 1;
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch { server.kill(); }
  await db.end();
}
