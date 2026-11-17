/* Test local signature électronique V1 (migration 036).
 * Base PostgreSQL de test seulement, jamais Render.
 * Usage : DATABASE_URL=postgres://postgres@localhost:5432/test_signatures_v1 \
 *   node test-signatures-v1.mjs
 * La base doit être créée vide avant ; le script applique db/schema.sql
 * puis les migrations 001 à 008, 016 et 036, démarre l'API (tsx
 * server/src/index.ts, PORT 3123) et exerce les routes. Il supprime la
 * base à la fin (connexion de maintenance sur la base `postgres`).
 */
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3123";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

// PNG 1x1 transparent, preuve de signature minimale.
const PNG_1X1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
const PNG_BUF = Buffer.from(PNG_1X1, "base64");
const EMPREINTE = createHash("sha256").update(PNG_BUF).digest("hex");
const POINTS = [
  { x: 0.1, y: 0.2 },
  { x: 0.4, y: 0.7 },
  { x: 0.7, y: 0.3 },
  { x: 0.9, y: 0.6 },
];
const TRACE_RE = /\d+(?:\.\d+)? \d+(?:\.\d+)? m \d+(?:\.\d+)? \d+(?:\.\d+)? l S/;

const db = new Client({ connectionString: DB });
await db.connect();
// Schéma + migrations (même ordre que migrate.ts pour ce périmètre).
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of ["001_fonctionnalites_eglise.sql","001_transferts_membre.sql","002_vue_consolidee_recursive.sql","003_mot_de_passe_acces_fidele.sql","004_depenses_budget_stats.sql","005_modules_eglise.sql","005_rapports_nombres.sql","006_organisation_catalogues.sql","007_campagnes.sql","008_attestations.sql","016_types_attestations.sql","036_signatures_electroniques.sql"]) {
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
const adminA = await user("admin-a@test.ci", churchA, "admin_eglise");
const tresA = await user("tresorier-a@test.ci", churchA, "tresorier");
const respA = await user("responsable-a@test.ci", churchA, "responsable_culte");
const membre1 = await user("membre1@test.ci", churchA, "membre", m1);
const membre2 = await user("membre2@test.ci", churchA, "membre", m2);
const tresB = await user("tresorier-b@test.ci", churchB, "tresorier");
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status,created_at) VALUES ($1,$2,'dime',10000,'especes','confirme','2026-03-01')`, [churchA, m1]);
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status,created_at) VALUES ($1,$2,'don',5000,'especes','confirme','2026-04-01')`, [churchA, m2]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3123", DATABASE_URL: DB, JWT_SECRET: "test-secret-sign-32-caracteres-min" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokAdmin = await login("admin-a@test.ci");
  const tokTres = await login("tresorier-a@test.ci");
  const tokResp = await login("responsable-a@test.ci");
  const tokM1 = await login("membre1@test.ci");
  const tokM2 = await login("membre2@test.ci");
  const tokB = await login("tresorier-b@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const signerAtt = (tok, id, body = { points: POINTS, image_png_base64: PNG_1X1 }) =>
    fetch(`${BASE}/attestations/${id}/signer`, { method: "POST", headers: H(tok), body: JSON.stringify(body) });
  const signerPv = (tok, id, body = { points: POINTS, image_png_base64: PNG_1X1 }) =>
    fetch(`${BASE}/proces-verbaux/${id}/signer`, { method: "POST", headers: H(tok), body: JSON.stringify(body) });
  const pdfDe = async (tok, url) => {
    const r = await fetch(`${BASE}${url}`, { headers: H(tok) });
    return { r, buf: Buffer.from(await r.arrayBuffer()) };
  };

  console.log("Migration 036 :");
  const col = await q(`SELECT column_name, data_type, column_default FROM information_schema.columns WHERE table_name='signatures' ORDER BY ordinal_position`);
  const noms = col.map((c) => c.column_name);
  check("table signatures : colonnes attendues", ["id","church_id","document_type","document_id","signataire_user_id","signataire_nom","signataire_fonction","points","image_png","empreinte_sha256","methode","date_signature"].every((c) => noms.includes(c)), noms.join(","));
  check("methode défaut 'dessin'", col.find((c) => c.column_name === "methode")?.column_default === "'dessin'::text", JSON.stringify(col.find((c) => c.column_name === "methode")));
  check("points JSONB, image_png BYTEA", col.find((c) => c.column_name === "points")?.data_type === "jsonb" && col.find((c) => c.column_name === "image_png")?.data_type === "bytea");
  const idx = await q(`SELECT indexdef FROM pg_indexes WHERE tablename='signatures' AND indexname='idx_signatures_document_unique'`);
  check("index unique (church_id, document_type, document_id)", /UNIQUE/.test(idx[0]?.indexdef ?? "") && /document_type, document_id/.test(idx[0]?.indexdef ?? ""), idx[0]?.indexdef ?? "");
  let badType = false;
  try { await q(`INSERT INTO signatures (church_id,document_type,document_id,signataire_nom,signataire_fonction,image_png,empreinte_sha256) VALUES ($1,'faux',gen_random_uuid(),'X','Y','\\x89504e470d0a1a0a','abc')`, [churchA]); } catch { badType = true; }
  check("CHECK refuse un document_type hors liste", badType);

  console.log("Préparation : attestation et procès-verbal :");
  let r = await fetch(`${BASE}/attestations/generer`, { method: "POST", headers: H(tokTres), body: JSON.stringify({ annee: 2026 }) });
  let d = await j(r);
  const a1 = d.creees?.find((a) => a.member_id === m1);
  const a2 = d.creees?.find((a) => a.member_id === m2);
  check("deux attestations de dons générées", r.status === 201 && !!a1 && !!a2, JSON.stringify(d));
  r = await fetch(`${BASE}/reunions-conseil`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ titre: "Conseil de janvier", date_reunion: "2026-01-15T18:00:00Z" }) });
  d = await j(r);
  check("réunion créée", r.status === 201 && !!d.id, JSON.stringify(d));
  const reunionId = d.id;
  r = await fetch(`${BASE}/proces-verbaux`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ reunion_id: reunionId, numero: "PV-2026-001", contenu: "Le conseil a adopté le budget 2026.", date_pv: "2026-01-15" }) });
  d = await j(r);
  check("PV créé, brouillon", r.status === 201 && d.statut === "brouillon", JSON.stringify(d));
  const pv1 = d;
  r = await fetch(`${BASE}/proces-verbaux`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ numero: "PV-2026-002", contenu: "Second procès-verbal, en attente.", date_pv: "2026-02-10" }) });
  d = await j(r);
  check("second PV créé, brouillon", r.status === 201 && d.statut === "brouillon", JSON.stringify(d));
  const pv2 = d;

  console.log("Signature d'une attestation :");
  r = await signerAtt(tokTres, a1.id);
  d = await j(r);
  check("signer 201, empreinte SHA-256 du PNG", r.status === 201 && d.empreinte_sha256 === EMPREINTE, JSON.stringify(d));
  check("signataire figé : nom du compte, fonction Trésorier", d.signataire_nom === "tresorier-a@test.ci" && d.signataire_fonction === "Trésorier", JSON.stringify(d));
  check("méthode dessin", d.methode === "dessin", JSON.stringify(d));
  r = await fetch(`${BASE}/signatures/attestation/${a1.id}`, { headers: H(tokAdmin) });
  d = await j(r);
  check("lecture signature 200, image base64 identique au PNG", r.status === 200 && Buffer.from(d.image_png_base64, "base64").equals(PNG_BUF) && d.empreinte_sha256 === EMPREINTE, JSON.stringify({ ...d, image_png_base64: (d.image_png_base64 ?? "").slice(0, 20) }));
  r = await fetch(`${BASE}/signatures/attestation/${a1.id}`, { headers: H(tokM1) });
  check("membre propriétaire lit la signature de son attestation", r.status === 200, String(r.status));
  r = await fetch(`${BASE}/signatures/attestation/${a1.id}`, { headers: H(tokM2) });
  check("autre membre : 403", r.status === 403, String(r.status));
  let p = await pdfDe(tokTres, `/attestations/${a1.id}/pdf`);
  const txtA1 = p.buf.toString("latin1");
  check("PDF attestation signée 200, %PDF", p.r.status === 200 && p.buf.subarray(0, 5).toString().startsWith("%PDF"), String(p.r.status));
  check("PDF attestation : bloc signature, nom, empreinte courte, tracé", txtA1.includes("Signature électronique") && txtA1.includes("tresorier-a@test.ci") && txtA1.includes("Empreinte SHA-256") && txtA1.includes(EMPREINTE.slice(0, 16)) && TRACE_RE.test(txtA1), txtA1.slice(0, 300));
  check("PDF attestation : total après lequel vient la signature, toujours là", txtA1.includes("10 000 FCFA"));

  console.log("Refus sur attestation :");
  r = await signerAtt(tokTres, a1.id);
  check("déjà signée : 409", r.status === 409, String(r.status));
  r = await signerAtt(tokM1, a2.id);
  check("membre ne signe jamais : 403", r.status === 403, String(r.status));
  r = await signerAtt(tokB, a2.id);
  check("autre église : 403", r.status === 403, String(r.status));
  r = await signerAtt(tokTres, "00000000-0000-0000-0000-000000000000");
  check("attestation inexistante : 404", r.status === 404, String(r.status));
  r = await signerAtt(tokTres, a2.id, { points: [], image_png_base64: PNG_1X1 });
  check("tracé vide : 400", r.status === 400, String(r.status));
  r = await signerAtt(tokTres, a2.id, { points: POINTS, image_png_base64: "" });
  check("image vide : 400", r.status === 400, String(r.status));
  r = await signerAtt(tokTres, a2.id, { points: POINTS, image_png_base64: Buffer.from("bonjour").toString("base64") });
  check("image non PNG : 400", r.status === 400, String(r.status));
  const gros = Buffer.concat([PNG_BUF, Buffer.alloc(200 * 1024, 0)]);
  r = await signerAtt(tokTres, a2.id, { points: POINTS, image_png_base64: gros.toString("base64") });
  check("image trop lourde (> 200 Ko) : 400", r.status === 400, String(r.status));
  r = await signerAtt(tokTres, a2.id, { points: [{ x: 2, y: 0.5 }], image_png_base64: PNG_1X1 });
  check("point hors cadre 0..1 : 400", r.status === 400, String(r.status));

  console.log("Invalidation attestation :");
  r = await fetch(`${BASE}/attestations/${a1.id}/corriger`, { method: "POST", headers: H(tokTres), body: JSON.stringify({ motif: "Correction après signature" }) });
  check("correction d'une attestation signée : 409", r.status === 409, String(r.status));
  r = await fetch(`${BASE}/attestations/${a2.id}/corriger`, { method: "POST", headers: H(tokTres), body: JSON.stringify({ motif: "Montant corrigé" }) });
  d = await j(r);
  check("correction d'une non signée : 201, nouveau numéro", r.status === 201 && d.remplace_id === a2.id, JSON.stringify(d));
  const a2b = d;
  r = await fetch(`${BASE}/signatures/attestation/${a2b.id}`, { headers: H(tokAdmin) });
  check("nouvelle attestation non signée : signature 404 (ne suit pas)", r.status === 404, String(r.status));
  r = await signerAtt(tokTres, a2b.id, { points: POINTS, image_png_base64: PNG_1X1, nom_affiche: "Trésorier Principal" });
  d = await j(r);
  check("nouvelle attestation signable, nom affiché figé", r.status === 201 && d.signataire_nom === "Trésorier Principal", JSON.stringify(d));

  console.log("Signature d'une attestation d'événement :");
  r = await fetch(`${BASE}/attestations/emette`, { method: "POST", headers: H(tokTres), body: JSON.stringify({ type: "mariage", member_id: m1, date_evenement: "2026-05-16", lieu: "Abidjan", conjoint_nom: "KOFFI MARIE" }) });
  d = await j(r);
  check("mariage émis 201", r.status === 201 && !!d.id, JSON.stringify(d));
  const mar1 = d;
  r = await signerAtt(tokTres, mar1.id);
  check("mariage signé 201", r.status === 201, String(r.status));
  p = await pdfDe(tokTres, `/attestations/${mar1.id}/pdf`);
  const txtMar = p.buf.toString("latin1");
  check("PDF mariage signé : bloc signature remplace la ligne vierge, tracé présent", p.r.status === 200 && txtMar.includes("Signature électronique") && !txtMar.includes("Signature : ____") && TRACE_RE.test(txtMar), txtMar.slice(0, 300));

  console.log("Signature d'un procès-verbal :");
  r = await fetch(`${BASE}/proces-verbaux/${pv2.id}/pdf`, { headers: H(tokAdmin) });
  p = { r, buf: Buffer.from(await r.arrayBuffer()) };
  const txtPv2Avant = p.buf.toString("latin1");
  check("PDF PV non signé : ligne vierge, pas de bloc signature", p.r.status === 200 && txtPv2Avant.includes("Signature :") && !txtPv2Avant.includes("Signature électronique"), txtPv2Avant.slice(0, 200));
  r = await signerPv(tokTres, pv1.id);
  check("trésorier ne signe pas un PV : 403", r.status === 403, String(r.status));
  r = await signerPv(tokM1, pv1.id);
  check("membre ne signe pas un PV : 403", r.status === 403, String(r.status));
  r = await signerPv(tokResp, pv1.id);
  d = await j(r);
  check("responsable de culte signe le PV : 201", r.status === 201 && d.signataire_fonction === "Responsable de culte", JSON.stringify(d));
  r = await fetch(`${BASE}/proces-verbaux/${pv1.id}`, { headers: H(tokAdmin) });
  d = await j(r);
  check("PV passé à 'signe', signataire renseigné", r.status === 200 && d.statut === "signe" && d.signataire === "responsable-a@test.ci", JSON.stringify(d));
  r = await signerPv(tokResp, pv1.id);
  check("PV déjà signé : 409", r.status === 409, String(r.status));
  p = await pdfDe(tokAdmin, `/proces-verbaux/${pv1.id}/pdf`);
  const txtPv1 = p.buf.toString("latin1");
  check("PDF PV signé 200, %PDF", p.r.status === 200 && p.buf.subarray(0, 5).toString().startsWith("%PDF"), String(p.r.status));
  check("PDF PV : contenu, réunion, bloc signature, tracé", txtPv1.includes("Le conseil a adopté le budget 2026.") && txtPv1.includes("Conseil de janvier") && txtPv1.includes("Signature électronique") && txtPv1.includes("responsable-a@test.ci") && TRACE_RE.test(txtPv1), txtPv1.slice(0, 300));
  p = await pdfDe(tokM1, `/proces-verbaux/${pv1.id}/pdf`);
  check("membre lit le PDF du PV", p.r.status === 200, String(p.r.status));
  r = await fetch(`${BASE}/signatures/proces_verbal/${pv1.id}`, { headers: H(tokM1) });
  check("membre lit la signature du PV", r.status === 200, String(r.status));
  r = await fetch(`${BASE}/proces-verbaux/${pv1.id}/pdf`, { headers: H(tokB) });
  check("autre église : PDF PV 403", r.status === 403, String(r.status));

  console.log("Invalidation procès-verbal :");
  r = await fetch(`${BASE}/proces-verbaux/${pv1.id}`, { method: "PATCH", headers: H(tokAdmin), body: JSON.stringify({ contenu: "Contenu modifié après signature." }) });
  check("modification du contenu d'un PV signé : 409", r.status === 409, String(r.status));
  r = await fetch(`${BASE}/proces-verbaux/${pv1.id}`, { method: "PATCH", headers: H(tokAdmin), body: JSON.stringify({ date_pv: "2026-01-20" }) });
  check("modification de la date d'un PV signé : 409", r.status === 409, String(r.status));
  r = await fetch(`${BASE}/proces-verbaux/${pv1.id}`, { method: "PATCH", headers: H(tokAdmin), body: JSON.stringify({ numero: "PV-2026-099" }) });
  check("modification du numéro d'un PV signé : 409", r.status === 409, String(r.status));
  r = await fetch(`${BASE}/proces-verbaux/${pv1.id}`, { method: "PATCH", headers: H(tokAdmin), body: JSON.stringify({ statut: "archive" }) });
  check("archivage d'un PV signé : 200 (seule modification permise)", r.status === 200, String(r.status));
  r = await fetch(`${BASE}/proces-verbaux/${pv2.id}`, { method: "PATCH", headers: H(tokAdmin), body: JSON.stringify({ statut: "signe" }) });
  check("signer par PATCH générique : 409", r.status === 409, String(r.status));
  r = await fetch(`${BASE}/proces-verbaux`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ numero: "PV-2026-003", contenu: "Né signé.", date_pv: "2026-03-01", statut: "signe" }) });
  check("créer un PV déjà 'signe' : 400", r.status === 400, String(r.status));

  console.log("Audit :");
  const audit = await q(`SELECT action, details FROM audit_logs WHERE church_id=$1 AND action IN ('attestation.signee','proces_verbal.signe') ORDER BY created_at`, [churchA]);
  const acts = audit.map((x) => x.action);
  check("audit : attestation.signee et proces_verbal.signe tracés", acts.includes("attestation.signee") && acts.includes("proces_verbal.signe"), acts.join(","));
  check("audit : empreinte et signataire dans les détails", audit.every((x) => x.details?.empreinte_sha256 && x.details?.signataire_nom && x.details?.signataire_user_id), JSON.stringify(audit.map((x) => x.details)));
  r = await fetch(`${BASE}/audit/verifier`, { headers: H(tokAdmin) });
  d = await j(r);
  check("chaîne d'audit vérifiée (verifierChaineAudit, ok)", r.status === 200 && d.ok === true && d.verifies > 0, JSON.stringify(d));
  console.log(`\n${ok} OK, ${ko} KO`);
  process.exitCode = ko === 0 ? 0 : 1;
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch { server.kill(); }
  await db.end();
  // Suppression de la base de test, après l'arrêt du serveur.
  try {
    const maintUrl = new URL(DB);
    const nomBase = decodeURIComponent(maintUrl.pathname.slice(1));
    maintUrl.pathname = "/postgres";
    const maint = new Client({ connectionString: maintUrl.toString() });
    await maint.connect();
    await maint.query(`DROP DATABASE IF EXISTS "${nomBase}"`);
    await maint.end();
    console.log(`base ${nomBase} supprimée.`);
  } catch (e) {
    console.log(`base de test non supprimée : ${e.message}`);
  }
}
