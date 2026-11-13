/* Test local Nettoyage des données TEST — base PostgreSQL de test
 * seulement, jamais Render.
 * Usage : DATABASE_URL=postgres://esc_nettoyage:test-nettoyage@127.0.0.1:5432/esc_nettoyage_test
 *   node test-nettoyage-test.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis
 * les migrations, démarre l'API (tsx server/src/index.ts, PORT 3106) et
 * exerce la route POST /admin/nettoyage-test. Il ne supprime pas la base :
 * la supprimer après, à la main.
 *
 * Données recréées = l'état de production après l'audit du 11 nov. 2026 :
 * membre TEST transféré (demande acceptée), contribution TEST-001,
 * dépense TEST-DEP-001, campagne TEST, attestation ATT-2026-0001,
 * sous-église TEST ESC-PWBYKY, plus des leurres réels (ADJA, dîme réelle,
 * campagne réelle, église indépendante avec son propre membre TEST).
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
for (const f of ["001_fonctionnalites_eglise.sql","001_transferts_membre.sql","002_vue_consolidee_recursive.sql","003_mot_de_passe_acces_fidele.sql","004_depenses_budget_stats.sql","005_modules_eglise.sql","005_rapports_nombres.sql","006_organisation_catalogues.sql","007_campagnes.sql","008_attestations.sql","009_codes_tutelle.sql","010_codes_invitation.sql","011_checkins_enfants.sql"]) {
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const church = async (code, name, parent = null) =>
  (await q(`INSERT INTO churches (code,code_fidele,name,city,status,parent_church_id) VALUES ($1,$2,$3,'Bingerville','active',$4) RETURNING id`, [code, `ESC-F-${code.slice(4)}`, name, parent]))[0].id;
const mere = await church("ESC-MERE01", "Ministère Évangélique Charismatique");
const sousEglise = await church("ESC-PWBYKY", "TEST Sous-église Audit", mere);
const independante = await church("ESC-IND001", "Église Indépendante");
async function user(email, ch, role) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name) VALUES ($1,$2,$3) RETURNING id`, [email, hash, email]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [u, ch, role]);
  return u;
}
await user("admin-mere@test.ci", mere, "admin_eglise");
await user("membre-simple@test.ci", mere, "membre");
// L'admin de la mère est aussi admin de la sous-église (elle l'a créée),
// comme KATIA en production : c'est dans ce contexte que la suppression
// du membre échoue sur la clé transferts_membre.
await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ((SELECT id FROM users WHERE email='admin-mere@test.ci'),$1,'admin_eglise')`, [sousEglise]);
// Membre réel (leurre) + dîme et campagne réelles (leurres).
const adja = (await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,'M-0001','ADJA','actif') RETURNING id`, [mere]))[0].id;
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,payment_ref,status,note) VALUES ($1,$2,'dime',20000,'wave','WAVE-REAL-001','confirme','Dîme réelle')`, [mere, adja]);
await q(`INSERT INTO campagnes (church_id,nom,objectif_fcfa,date_debut,date_fin,statut) VALUES ($1,'Campagne réelle',50000,'2026-11-01','2026-12-31','active')`, [mere]);
// Membre TEST d'une autre église (leurre hors périmètre) : jamais touché.
await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,'M-0001','TEST Membre Ailleurs','actif') RETURNING id`, [independante]);
// Membre TEST : créé à la mère (M-0002), puis transféré accepté vers la
// sous-église (M-0001), comme en production après l'audit.
const testId = (await q(`INSERT INTO members (church_id,matricule,full_name,phone,email,status) VALUES ($1,'M-0002','TEST Membre Audit','0700000000','test.audit@example.com','actif') RETURNING id`, [mere]))[0].id;
await q(`INSERT INTO transferts_membre (membre_id,membre_nom,ancien_matricule,nouveau_matricule,eglise_depart_id,eglise_arrivee_id,motif,status,decision_depart,decision_arrivee) VALUES ($1,'TEST Membre Audit','M-0002','M-0001',$2,$3,'TEST transfert audit','accepte','accepte','accepte')`, [testId, mere, sousEglise]);
await q(`UPDATE members SET church_id=$1, matricule='M-0001' WHERE id=$2`, [sousEglise, testId]);
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,payment_ref,status,note) VALUES ($1,$2,'dime',1000,'wave','TEST-001','confirme','TEST contribution audit')`, [mere, testId]);
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,payment_ref,status,note) VALUES ($1,$2,'depense',500,'wave','TEST-DEP-001','confirme','TEST dépense audit')`, [mere, testId]);
await q(`INSERT INTO campagnes (church_id,nom,objectif_fcfa,date_debut,date_fin,statut) VALUES ($1,'TEST Campagne Audit',10000,'2026-11-11','2026-11-30','active')`, [mere]);
await q(`INSERT INTO attestations (church_id,member_id,annee,numero,total_fcfa,nb_dons,statut,contenu) VALUES ($1,$2,2026,'ATT-2026-0001',1000,1,'emise','{}')`, [mere, testId]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3106", DATABASE_URL: DB, JWT_SECRET: "test-secret-nettoyage-32-caracteres-min" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokAdmin = await login("admin-mere@test.ci");
  const tokMembre = await login("membre-simple@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const count = async (sql, p = []) => (await q(`SELECT count(*)::int AS n FROM (${sql}) s`, p))[0].n;

  console.log("Blocage d'origine (suppression du membre seul) :");
  // Dans le contexte de la sous-église, où réside le membre TEST.
  let r = await fetch(`${BASE}/auth/eglise-active`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ church_id: sousEglise }) });
  let d = await j(r);
  const tokSousEglise = d.token;
  check("bascule vers la sous-église", r.status === 200 && !!tokSousEglise, `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/membres/${testId}`, { method: "DELETE", headers: H(tokSousEglise) });
  d = await j(r);
  check("DELETE /membres du TEST échoue 409 (E19, membre lié à un transfert)", r.status === 409 && /transfert/i.test(d.message ?? ""), `${r.status} ${JSON.stringify(d)}`);
  check("membre TEST toujours présent", (await count(`SELECT id FROM members WHERE id='${testId}'`)) === 1);

  console.log("Droits :");
  r = await fetch(`${BASE}/admin/nettoyage-test`, { method: "POST", headers: H(tokMembre), body: JSON.stringify({}) });
  check("membre simple : 403", r.status === 403, `${r.status}`);
  r = await fetch(`${BASE}/admin/nettoyage-test`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({}) });
  check("sans jeton : 401", r.status === 401, `${r.status}`);

  console.log("Aperçu :");
  r = await fetch(`${BASE}/admin/nettoyage-test`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({}) });
  d = await j(r);
  check("aperçu 200, total 7", r.status === 200 && d.total === 7, `${r.status} ${JSON.stringify(d)}`);
  const types = (d.elements ?? []).map((e) => e.type).sort().join(",");
  check("aperçu : 1 transfert, 1 attestation, 2 contributions, 1 campagne, 1 membre, 1 église",
    types === "attestation,campagne,contribution,contribution,eglise,membre,transfert", types);
  check("aperçu : le membre TEST d'ailleurs n'est pas listé",
    !(d.elements ?? []).some((e) => e.label.includes("Ailleurs")));
  check("aperçu : rien n'est supprimé", (await count(`SELECT id FROM members WHERE id='${testId}'`)) === 1);

  console.log("Suppression confirmée :");
  r = await fetch(`${BASE}/admin/nettoyage-test`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ confirmer: true }) });
  d = await j(r);
  check("confirmation 200, total 7", r.status === 200 && d.total === 7, `${r.status} ${JSON.stringify(d)}`);
  check("transfert TEST supprimé", (await count(`SELECT id FROM transferts_membre WHERE membre_nom ILIKE 'TEST%'`)) === 0);
  check("membre TEST supprimé", (await count(`SELECT id FROM members WHERE full_name ILIKE 'TEST%' AND church_id IN (SELECT id FROM churches WHERE id='${mere}' OR parent_church_id='${mere}')`)) === 0);
  check("contributions TEST supprimées", (await count(`SELECT id FROM contributions WHERE payment_ref ILIKE 'TEST%'`)) === 0);
  check("campagne TEST supprimée", (await count(`SELECT id FROM campagnes WHERE nom ILIKE 'TEST%'`)) === 0);
  check("attestation TEST supprimée", (await count(`SELECT id FROM attestations WHERE numero='ATT-2026-0001'`)) === 0);
  check("sous-église TEST supprimée", (await count(`SELECT id FROM churches WHERE code='ESC-PWBYKY'`)) === 0);
  check("journal : 7 suppressions + 1 résumé",
    (await count(`SELECT id FROM audit_logs WHERE action='nettoyage_test.supprime'`)) === 7 &&
    (await count(`SELECT id FROM audit_logs WHERE action='nettoyage_test.execute'`)) === 1);

  console.log("Leurres intacts :");
  check("ADJA intact", (await count(`SELECT id FROM members WHERE id='${adja}'`)) === 1);
  check("dîme réelle intacte", (await count(`SELECT id FROM contributions WHERE payment_ref='WAVE-REAL-001'`)) === 1);
  check("campagne réelle intacte", (await count(`SELECT id FROM campagnes WHERE nom='Campagne réelle'`)) === 1);
  check("église mère intacte", (await count(`SELECT id FROM churches WHERE id='${mere}'`)) === 1);
  check("église indépendante et son membre TEST intacts",
    (await count(`SELECT id FROM churches WHERE id='${independante}'`)) === 1 &&
    (await count(`SELECT id FROM members WHERE full_name='TEST Membre Ailleurs'`)) === 1);

  console.log("Idempotence :");
  r = await fetch(`${BASE}/admin/nettoyage-test`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({}) });
  d = await j(r);
  check("deuxième aperçu : total 0", r.status === 200 && d.total === 0, JSON.stringify(d));
  r = await fetch(`${BASE}/admin/nettoyage-test`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ confirmer: true }) });
  d = await j(r);
  check("deuxième confirmation : total 0, ok", r.status === 200 && d.total === 0, JSON.stringify(d));
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
  await db.end();
}
console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko === 0 ? 0 : 1);
