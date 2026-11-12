/* Test local tranche B — attestations d'événement en PDF exclusivement.
 * Base PostgreSQL de test seulement, jamais Render.
 * Usage : DATABASE_URL=postgres://postgres@localhost:5432/esc_attest_test \
 *   node test-attestations-pdf.mjs
 * La base doit être créée vide avant ; le script applique db/schema.sql
 * puis les migrations 001 à 008 et 016, démarre l'API (tsx
 * server/src/index.ts, PORT 3122) et exerce les routes. Il supprime la
 * base à la fin (connexion de maintenance sur la base `postgres`).
 */
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3122";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const db = new Client({ connectionString: DB });
await db.connect();
// Schéma + migrations (même ordre que migrate.ts pour ce périmètre).
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of ["001_fonctionnalites_eglise.sql","001_transferts_membre.sql","002_vue_consolidee_recursive.sql","003_mot_de_passe_acces_fidele.sql","004_depenses_budget_stats.sql","005_modules_eglise.sql","005_rapports_nombres.sql","006_organisation_catalogues.sql","007_campagnes.sql","008_attestations.sql","016_types_attestations.sql"]) {
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const churchA = (await q(`INSERT INTO churches (code,code_fidele,name,status) VALUES ('ESC-TEST-A','ESC-F-TSTA01','Église Test A','active') RETURNING id`))[0].id;
const churchB = (await q(`INSERT INTO churches (code,code_fidele,name,status) VALUES ('ESC-TEST-B','ESC-F-TSTB01','Église Test B','active') RETURNING id`))[0].id;
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
const tresA = await user("tresorier-a@test.ci", churchA, "tresorier");
const membre1 = await user("membre1@test.ci", churchA, "membre", m1);
const tresB = await user("tresorier-b@test.ci", churchB, "tresorier");
async function contrib(church, memberId, type, amount, status, date) {
  await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status,created_at) VALUES ($1,$2,$3,$4,'especes',$5,$6)`, [church, memberId, type, amount, status, date]);
}
await contrib(churchA, m1, "dime", 10000, "confirme", "2026-03-01");

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3122", DATABASE_URL: DB, JWT_SECRET: "test-secret-pdf-32-caracteres-minimum" }, stdio: "ignore", detached: true });
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
  const emettre = (tok, body) => fetch(`${BASE}/attestations/emette`, { method: "POST", headers: H(tok), body: JSON.stringify(body) });
  const pdfDe = async (tok, id) => {
    const r = await fetch(`${BASE}/attestations/${id}/pdf`, { headers: H(tok) });
    return { r, buf: Buffer.from(await r.arrayBuffer()) };
  };

  console.log("Migration 016 :");
  const col = await q(`SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name='attestations' AND column_name IN ('type','total_fcfa','nb_dons') ORDER BY column_name`);
  check("colonne type TEXT, défaut 'don'", col.find((c) => c.column_name === "type")?.column_default === "'don'::text", JSON.stringify(col));
  check("total_fcfa et nb_dons nullables", col.filter((c) => c.column_name !== "type").every((c) => c.is_nullable === "YES"), JSON.stringify(col));
  let badType = false;
  try { await q(`INSERT INTO attestations (church_id,member_id,type,annee,numero) VALUES ($1,$2,'faux',2026,'XXX-2026-0001')`, [churchA, m1]); } catch { badType = true; }
  check("CHECK refuse un type hors liste", badType);
  const idx = await q(`SELECT indexdef FROM pg_indexes WHERE tablename='attestations' AND indexname='idx_attestations_une_emise'`);
  check("index partiel sur (church_id, member_id, type, annee)", /member_id, type, annee/.test(idx[0]?.indexdef ?? "") && /statut = 'emise'/.test(idx[0]?.indexdef ?? ""), idx[0]?.indexdef ?? "");

  console.log("Émission de chaque type :");
  let r = await emettre(tokA, { type: "mariage", member_id: m1, date_evenement: "2026-05-16", lieu: "Abidjan", officiant: "Pasteur Yao", conjoint_nom: "KOFFI MARIE" });
  let d = await j(r);
  check("mariage 201, MAR-2026-0001", r.status === 201 && d.numero === "MAR-2026-0001", JSON.stringify(d));
  check("mariage sans total ni nb_dons", d.total_fcfa === null && d.nb_dons === null, JSON.stringify(d));
  const mar1 = d;
  r = await emettre(tokA, { type: "naissance", member_id: m1, date_evenement: "2026-02-10", lieu: "Abidjan", pere_nom: "KOFFI PERE", mere_nom: "KOFFI MERE" });
  d = await j(r);
  check("naissance 201, NAI-2026-0001 (séquence propre au type)", r.status === 201 && d.numero === "NAI-2026-0001", JSON.stringify(d));
  const nai1 = d;
  r = await emettre(tokA, { type: "bapteme", member_id: m2, date_evenement: "2026-04-05", parrain_nom: "YAO PARRAIN", marraine_nom: "YAO MARRAINE" });
  d = await j(r);
  check("baptême 201, BAP-2026-0001", r.status === 201 && d.numero === "BAP-2026-0001", JSON.stringify(d));
  const bap1 = d;
  r = await emettre(tokA, { type: "mariage", member_id: m2, date_evenement: "2026-06-20", lieu: "Yamoussoukro" });
  d = await j(r);
  check("mariage m2 : MAR-2026-0002 (séquence partagée par église et type)", r.status === 201 && d.numero === "MAR-2026-0002", JSON.stringify(d));
  r = await emettre(tokA, { type: "mariage", member_id: m1, date_evenement: "2025-05-16" });
  d = await j(r);
  check("mariage m1 en 2025 : MAR-2025-0001 (autre année autorisée)", r.status === 201 && d.numero === "MAR-2025-0001", JSON.stringify(d));

  console.log("Refus d'émission :");
  r = await emettre(tokA, { type: "mariage", member_id: m1, date_evenement: "2026-07-01" });
  check("deuxième mariage m1 en 2026 : 409", r.status === 409, String(r.status));
  r = await emettre(tokA, { type: "faux", member_id: m1, date_evenement: "2026-07-01" });
  check("type invalide : 400", r.status === 400, String(r.status));
  r = await emettre(tokA, { type: "mariage", member_id: m1, date_evenement: "2026-02-30" });
  check("date inexistante (30 février) : 400", r.status === 400, String(r.status));
  r = await emettre(tokA, { type: "mariage", member_id: "00000000-0000-0000-0000-000000000000", date_evenement: "2026-07-01" });
  check("membre inexistant : 404", r.status === 404, String(r.status));
  r = await emettre(tokM1, { type: "mariage", member_id: m1, date_evenement: "2026-07-01" });
  check("membre ne peut pas émettre : 403", r.status === 403, String(r.status));

  console.log("Liste et PDF :");
  r = await fetch(`${BASE}/attestations?type=mariage&annee=2026`, { headers: H(tokA) });
  d = await j(r);
  check("liste filtrée type=mariage 2026 : 2", d.attestations?.length === 2, JSON.stringify(d));
  r = await fetch(`${BASE}/attestations?annee=2026`, { headers: H(tokA) });
  d = await j(r);
  check("liste 2026 tous types : 4", d.attestations?.length === 4, JSON.stringify(d));
  let p = await pdfDe(tokA, mar1.id);
  check("PDF mariage 200, %PDF", p.r.status === 200 && p.buf.subarray(0, 5).toString().startsWith("%PDF"), String(p.r.status));
  check("PDF mariage : application/pdf", (p.r.headers.get("content-type") ?? "").includes("application/pdf"));
  const txtMar = p.buf.toString("latin1");
  check("PDF mariage : libellé, numéro, conjoint, lieu, signature, cachet", txtMar.includes("Attestation de mariage") && txtMar.includes("MAR-2026-0001") && txtMar.includes("KOFFI MARIE") && txtMar.includes("Abidjan") && txtMar.includes("Signature") && txtMar.includes("Cachet de l"), txtMar.slice(0, 400));
  p = await pdfDe(tokA, nai1.id);
  check("PDF naissance : parents", p.buf.toString("latin1").includes("KOFFI PERE") && p.buf.toString("latin1").includes("KOFFI MERE"));
  p = await pdfDe(tokA, bap1.id);
  check("PDF baptême : parrain et marraine", p.buf.toString("latin1").includes("YAO PARRAIN") && p.buf.toString("latin1").includes("YAO MARRAINE"));

  console.log("Contenu figé :");
  await q(`UPDATE members SET full_name='KOFFI JEAN MODIFIE' WHERE id=$1`, [m1]);
  p = await pdfDe(tokA, mar1.id);
  check("PDF inchangé après modification du membre (KOFFI JEAN, pas MODIFIE)", p.buf.toString("latin1").includes("KOFFI JEAN") && !p.buf.toString("latin1").includes("MODIFIE"));

  console.log("Correction d'un événement :");
  r = await fetch(`${BASE}/attestations/${mar1.id}/corriger`, { method: "POST", headers: H(tokA), body: JSON.stringify({ motif: "Lieu corrigé", lieu: "Bouaké" }) });
  d = await j(r);
  check("correction 201, MAR-2026-0003, remplace l'ancienne", r.status === 201 && d.numero === "MAR-2026-0003" && d.remplace_id === mar1.id, JSON.stringify(d));
  const mar2 = d;
  r = await fetch(`${BASE}/attestations/${mar1.id}/corriger`, { method: "POST", headers: H(tokA), body: JSON.stringify({ motif: "encore" }) });
  check("correction d'une annulée : 409", r.status === 409, String(r.status));
  r = await fetch(`${BASE}/attestations/${mar2.id}/corriger`, { method: "POST", headers: H(tokA), body: JSON.stringify({}) });
  check("correction sans motif : 400", r.status === 400, String(r.status));
  p = await pdfDe(tokA, mar1.id);
  check("PDF ancienne annulée 409", p.r.status === 409, String(p.r.status));
  p = await pdfDe(tokA, mar2.id);
  check("PDF nouvelle : nouveau lieu Bouaké, conjoint conservé", p.buf.toString("latin1").includes("Bouaké") && p.buf.toString("latin1").includes("KOFFI MARIE"));

  console.log("Isolation membre et église :");
  r = await fetch(`${BASE}/moi/attestations`, { headers: H(tokM1) });
  d = await j(r);
  check("membre voit les siennes, tous types (mariage corrigé, naissance, mariage 2025)", d.attestations?.length === 3 && d.attestations.every((a) => a.numero.startsWith("MAR") || a.numero.startsWith("NAI")), JSON.stringify(d));
  r = await fetch(`${BASE}/attestations/${bap1.id}/pdf`, { headers: H(tokM1) });
  check("membre : PDF d'un autre membre 403", r.status === 403, String(r.status));
  r = await fetch(`${BASE}/attestations?annee=2026`, { headers: H(tokB) });
  d = await j(r);
  check("autre église : liste vide", d.attestations?.length === 0, JSON.stringify(d));
  r = await fetch(`${BASE}/attestations/${mar2.id}/pdf`, { headers: H(tokB) });
  check("autre église : PDF 403", r.status === 403, String(r.status));

  console.log("Non-régression dons US3 :");
  r = await fetch(`${BASE}/attestations/generer`, { method: "POST", headers: H(tokA), body: JSON.stringify({ annee: 2026 }) });
  d = await j(r);
  const a1 = d.creees?.find((a) => a.member_id === m1);
  check("génération dons 201, M1 total 10000", r.status === 201 && a1?.total_fcfa === 10000 && a1?.nb_dons === 1, JSON.stringify(d));
  check("numéro don ATT-2026-0001 (séquence dons indépendante)", a1?.numero === "ATT-2026-0001", a1?.numero ?? "");
  check("type don renvoyé", a1?.type === "don", JSON.stringify(a1));
  p = await pdfDe(tokA, a1.id);
  check("PDF don : total figé 10 000 FCFA, mention fiscale", p.buf.toString("latin1").includes("10 000 FCFA") && p.buf.toString("latin1").includes("aucune valeur fiscale"));
  await contrib(churchA, m1, "don", 5000, "confirme", "2026-07-01");
  r = await fetch(`${BASE}/attestations/${a1.id}/corriger`, { method: "POST", headers: H(tokA), body: JSON.stringify({ motif: "Don de juillet ajouté" }) });
  d = await j(r);
  check("correction don 201, ATT-2026-0002, total 15000", r.status === 201 && d.numero === "ATT-2026-0002" && d.total_fcfa === 15000, JSON.stringify(d));
  const audit = await q(`SELECT action FROM audit_logs WHERE church_id=$1 AND action LIKE 'attestation.%' ORDER BY created_at`, [churchA]);
  const acts = audit.map((x) => x.action);
  check("audit : generee et corrige tracées", acts.includes("attestation.generee") && acts.includes("attestation.corrige"), acts.join(","));
  console.log(`\n${ok} OK, ${ko} KO`);
  process.exitCode = ko === 0 ? 0 : 1;
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch { server.kill(); }
  await db.end();
  // Suppression de la base de test, après l'arrêt du serveur.
  try {
    const maintUrl = new URL(DB);
    maintUrl.pathname = "/postgres";
    const maint = new Client({ connectionString: maintUrl.toString() });
    await maint.connect();
    await maint.query(`DROP DATABASE IF EXISTS esc_attest_test`);
    await maint.end();
    console.log("base esc_attest_test supprimée.");
  } catch (e) {
    console.log(`base esc_attest_test non supprimée : ${e.message}`);
  }
}
