/* Test local Suppression d'une église — base PostgreSQL de test
 * seulement, jamais Render.
 * Usage : DATABASE_URL=<redacted>
 *   node test-suppression-eglise.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis
 * toutes les migrations, démarre l'API (tsx server/src/index.ts,
 * PORT 3107) et exerce la route POST /admin/supprimer-eglise et le
 * PATCH /eglises/:id/profil. Il ne supprime pas la base : la supprimer
 * après, à la main.
 *
 * Cas testés : auto-suppression de l'église TEST (priorité), suppression
 * d'une annexe réelle par sa mère, suppression d'une annexe par le
 * super admin, modification d'une annexe par la mère et par le super
 * admin, gardes (403, 409, 400), leurres réels intacts.
 */
import { spawn } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3107";
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
for (const f of readdirSync("../db/migrations").sort()) {
  if (!f.endsWith(".sql")) continue;
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const church = async (code, name, parent = null) =>
  (await q(`INSERT INTO churches (code,code_fidele,name,city,status,parent_church_id) VALUES ($1,$2,$3,'Bingerville','active',$4) RETURNING id`, [code, `ESC-F-${code.slice(4)}`, name, parent]))[0].id;
const mere = await church("ESC-MERE01", "Ministère Évangélique Charismatique");
const testEglise = await church("ESC-4240", "TEST Église");
const testAnnexe = await church("ESC-4241", "TEST Annexe", testEglise);
const annexe1 = await church("ESC-ANN001", "Annexe Réelle", mere);
const annexe2 = await church("ESC-ANN002", "Annexe Réelle 2", mere);
const independante = await church("ESC-IND001", "Église Indépendante");
async function user(email, fullName, ch, role) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name) VALUES ($1,$2,$3) RETURNING id`, [email, hash, fullName]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [u, ch, role]);
  return u;
}
const adminMere = await user("admin-mere@test.ci", "Admin Mère", mere, "admin_eglise");
await user("membre-simple@test.ci", "Membre Simple", mere, "membre");
await user("super@test.ci", "Super Admin", mere, "super_admin");
await user("admin-test@test.ci", "Admin TEST", testEglise, "admin_eglise");
// Compte TEST qui n'a que l'église TEST : supprimé avec elle.
await user("test-seul@test.ci", "TEST Seul", testEglise, "admin_eglise");
// L'admin de la mère est aussi admin de TEST (comme KATIA en production) :
// son compte survit à la suppression de TEST.
await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,'admin_eglise')`, [adminMere, testEglise]);
await user("admin-ann1@test.ci", "Admin Annexe 1", annexe1, "admin_eglise");
// Membre réel (leurre) + dîme et campagne réelles (leurres).
const adja = (await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,'M-0001','ADJA','actif') RETURNING id`, [mere]))[0].id;
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,payment_ref,status,note) VALUES ($1,$2,'dime',20000,'wave','WAVE-REAL-001','confirme','Dîme réelle')`, [mere, adja]);
await q(`INSERT INTO campagnes (church_id,nom,objectif_fcfa,date_debut,date_fin,statut) VALUES ($1,'Campagne réelle',50000,'2026-11-01','2026-12-31','active')`, [mere]);
// Membre TEST d'une autre église (leurre hors périmètre) : jamais touché.
await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,'M-0001','TEST Membre Ailleurs','actif') RETURNING id`, [independante]);
// Église TEST : membre TEST, contribution, campagne, attestation,
// transfert accepté vers son annexe TEST.
const testId = (await q(`INSERT INTO members (church_id,matricule,full_name,phone,email,status) VALUES ($1,'M-0002','TEST Membre','0700000000','test@example.com','actif') RETURNING id`, [testEglise]))[0].id;
await q(`INSERT INTO transferts_membre (membre_id,membre_nom,ancien_matricule,nouveau_matricule,eglise_depart_id,eglise_arrivee_id,motif,status,decision_depart,decision_arrivee) VALUES ($1,'TEST Membre','M-0002','M-0001',$2,$3,'TEST transfert','accepte','accepte','accepte')`, [testId, testEglise, testAnnexe]);
await q(`UPDATE members SET church_id=$1, matricule='M-0001' WHERE id=$2`, [testAnnexe, testId]);
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,payment_ref,status,note) VALUES ($1,$2,'dime',1000,'wave','TEST-001','confirme','TEST contribution')`, [testEglise, testId]);
await q(`INSERT INTO campagnes (church_id,nom,objectif_fcfa,date_debut,date_fin,statut) VALUES ($1,'TEST Campagne',10000,'2026-11-11','2026-11-30','active')`, [testEglise]);
await q(`INSERT INTO attestations (church_id,member_id,annee,numero,total_fcfa,nb_dons,statut,contenu) VALUES ($1,$2,2026,'ATT-2026-0001',1000,1,'emise','{}')`, [testEglise, testId]);
// Annexes réelles : un membre et une contribution chacune.
const reel1 = (await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,'M-0001','Réel Annexe 1','actif') RETURNING id`, [annexe1]))[0].id;
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,payment_ref,status,note) VALUES ($1,$2,'dime',5000,'wave','WAVE-ANN1-001','confirme','Dîme annexe 1')`, [annexe1, reel1]);
const reel2 = (await q(`INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,'M-0001','Réel Annexe 2','actif') RETURNING id`, [annexe2]))[0].id;
await q(`INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,payment_ref,status,note) VALUES ($1,$2,'dime',7000,'wave','WAVE-ANN2-001','confirme','Dîme annexe 2')`, [annexe2, reel2]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3107", DATABASE_URL: DB, JWT_SECRET: "test-secret-suppression-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email, churchId) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!", ...(churchId ? { church_id: churchId } : {}) }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokAdminMere = await login("admin-mere@test.ci", mere);
  const tokAdminTest = await login("admin-test@test.ci", testEglise);
  const tokSuper = await login("super@test.ci", mere);
  const tokMembre = await login("membre-simple@test.ci", mere);
  const tokAdminAnn1 = await login("admin-ann1@test.ci", annexe1);
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const count = async (sql, p = []) => (await q(`SELECT count(*)::int AS n FROM (${sql}) s`, p))[0].n;
  const postSuppr = (tok, body) => fetch(`${BASE}/admin/supprimer-eglise`, { method: "POST", headers: H(tok), body: JSON.stringify(body) });

  console.log("Droits :");
  let r = await postSuppr(tokMembre, {});
  check("membre simple : 403", r.status === 403, `${r.status}`);
  r = await fetch(`${BASE}/admin/supprimer-eglise`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({}) });
  check("sans jeton : 401", r.status === 401, `${r.status}`);

  console.log("Gardes :");
  r = await postSuppr(tokAdminMere, {});
  let d = await j(r);
  check("mère qui se supprime elle-même (pas TEST) : 409", r.status === 409 && d.error === "pas_test", `${r.status} ${JSON.stringify(d)}`);
  r = await postSuppr(tokAdminMere, { eglise_id: testEglise });
  check("mère visant TEST (pas son annexe) : 403", r.status === 403, `${r.status}`);
  r = await postSuppr(tokAdminAnn1, {});
  d = await j(r);
  check("admin d'annexe qui se supprime : 409", r.status === 409 && d.error === "annexe_par_la_mere", `${r.status} ${JSON.stringify(d)}`);
  r = await postSuppr(tokSuper, {});
  check("super admin sans eglise_id : 400", r.status === 400, `${r.status}`);
  r = await postSuppr(tokSuper, { eglise_id: mere });
  d = await j(r);
  check("super admin visant une église de premier niveau : 409", r.status === 409 && d.error === "pas_une_annexe", `${r.status} ${JSON.stringify(d)}`);
  r = await postSuppr(tokSuper, { eglise_id: testEglise });
  check("super admin visant TEST (premier niveau) : 409", r.status === 409, `${r.status}`);
  r = await postSuppr(tokAdminMere, { eglise_id: "pas-un-uuid" });
  check("eglise_id invalide : 400", r.status === 400, `${r.status}`);
  r = await postSuppr(tokAdminMere, { eglise_id: "00000000-0000-0000-0000-000000000000" });
  check("eglise_id introuvable : 404", r.status === 404, `${r.status}`);

  console.log("Modification d'une annexe (PATCH /eglises/:id/profil) :");
  r = await fetch(`${BASE}/eglises/${annexe1}/profil`, { method: "PATCH", headers: H(tokMembre), body: JSON.stringify({ name: "Nouveau nom" }) });
  check("membre simple : 403", r.status === 403, `${r.status}`);
  r = await fetch(`${BASE}/eglises/${mere}/profil`, { method: "PATCH", headers: H(tokAdminAnn1), body: JSON.stringify({ name: "Nouveau nom" }) });
  check("admin d'annexe visant la mère : 403", r.status === 403, `${r.status}`);
  r = await fetch(`${BASE}/eglises/${independante}/profil`, { method: "PATCH", headers: H(tokAdminMere), body: JSON.stringify({ name: "Nouveau nom" }) });
  check("mère visant une église indépendante : 403", r.status === 403, `${r.status}`);
  r = await fetch(`${BASE}/eglises/${annexe1}/profil`, { method: "PATCH", headers: H(tokAdminMere), body: JSON.stringify({}) });
  check("mère sans champ : 400", r.status === 400, `${r.status}`);
  r = await fetch(`${BASE}/eglises/${annexe1}/profil`, { method: "PATCH", headers: H(tokAdminMere), body: JSON.stringify({ name: "Annexe Réelle Renommée", city: "Abidjan" }) });
  d = await j(r);
  check("mère renomme son annexe : 200", r.status === 200 && d.name === "Annexe Réelle Renommée" && d.city === "Abidjan" && d.code === "ESC-ANN001", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/eglises/${annexe2}/profil`, { method: "PATCH", headers: H(tokSuper), body: JSON.stringify({ name: "Annexe 2 Renommée" }) });
  d = await j(r);
  check("super admin renomme une annexe : 200, code inchangé", r.status === 200 && d.name === "Annexe 2 Renommée" && d.code === "ESC-ANN002", `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/eglises/${mere}/profil`, { method: "PATCH", headers: H(tokAdminMere), body: JSON.stringify({ name: "Ministère Évangélique Charismatique" }) });
  check("mère modifie toujours sa propre église : 200", r.status === 200, `${r.status}`);

  console.log("Cas TEST (priorité) : aperçu puis suppression :");
  r = await postSuppr(tokAdminTest, {});
  d = await j(r);
  check("aperçu TEST 200", r.status === 200, `${r.status} ${JSON.stringify(d)}`);
  check("aperçu : église ESC-4240", d.eglise?.code === "ESC-4240", JSON.stringify(d.eglise));
  check("aperçu : 1 annexe TEST", (d.annexes ?? []).length === 1 && d.annexes[0].code === "ESC-4241", JSON.stringify(d.annexes));
  check("aperçu : membres 1, contributions 1, campagnes 1, attestations 1, transferts 1",
    d.comptes?.members === 1 && d.comptes?.contributions === 1 && d.comptes?.campagnes === 1 && d.comptes?.attestations === 1 && d.comptes?.transferts_membre === 1, JSON.stringify(d.comptes));
  check("aperçu : 1 compte TEST à supprimer", d.utilisateurs_supprimes === 1, JSON.stringify(d));
  check("aperçu : rien n'est supprimé", (await count(`SELECT id FROM churches WHERE id='${testEglise}'`)) === 1);
  r = await postSuppr(tokAdminTest, { confirmer: true });
  d = await j(r);
  check("confirmation TEST 200", r.status === 200 && d.ok === true, `${r.status} ${JSON.stringify(d)}`);
  check("église TEST supprimée", (await count(`SELECT id FROM churches WHERE code='ESC-4240'`)) === 0);
  check("annexe TEST supprimée", (await count(`SELECT id FROM churches WHERE code='ESC-4241'`)) === 0);
  check("membre TEST supprimé", (await count(`SELECT id FROM members WHERE full_name='TEST Membre'`)) === 0);
  check("contribution TEST supprimée", (await count(`SELECT id FROM contributions WHERE payment_ref='TEST-001'`)) === 0);
  check("campagne TEST supprimée", (await count(`SELECT id FROM campagnes WHERE nom='TEST Campagne'`)) === 0);
  check("attestation TEST supprimée", (await count(`SELECT id FROM attestations WHERE numero='ATT-2026-0001'`)) === 0);
  check("transfert TEST supprimé", (await count(`SELECT id FROM transferts_membre WHERE membre_nom='TEST Membre'`)) === 0);
  check("compte TEST seul supprimé", (await count(`SELECT id FROM users WHERE email='test-seul@test.ci'`)) === 0);
  check("compte admin de la mère intact (aussi admin de TEST)", (await count(`SELECT id FROM users WHERE email='admin-mere@test.ci'`)) === 1);
  check("journal : 2 suppressions + 1 résumé", (await count(`SELECT id FROM audit_logs WHERE action='suppression_eglise.supprime'`)) === 2 && (await count(`SELECT id FROM audit_logs WHERE action='suppression_eglise.execute'`)) === 1);

  console.log("Cas annexe par la mère :");
  r = await postSuppr(tokAdminMere, { eglise_id: annexe1 });
  d = await j(r);
  check("aperçu annexe 200, 1 membre réel + 1 contribution réelle", r.status === 200 && d.comptes?.members === 1 && d.comptes?.contributions === 1, `${r.status} ${JSON.stringify(d)}`);
  r = await postSuppr(tokAdminMere, { eglise_id: annexe1, confirmer: true });
  d = await j(r);
  check("confirmation annexe 200", r.status === 200 && d.ok === true, `${r.status} ${JSON.stringify(d)}`);
  check("annexe 1 supprimée", (await count(`SELECT id FROM churches WHERE id='${annexe1}'`)) === 0);
  check("membre de l'annexe 1 supprimé", (await count(`SELECT id FROM members WHERE id='${reel1}'`)) === 0);
  check("contribution de l'annexe 1 supprimée", (await count(`SELECT id FROM contributions WHERE payment_ref='WAVE-ANN1-001'`)) === 0);

  console.log("Cas annexe par le super admin :");
  r = await postSuppr(tokSuper, { eglise_id: annexe2 });
  d = await j(r);
  check("aperçu super admin 200", r.status === 200 && d.eglise?.code === "ESC-ANN002", `${r.status} ${JSON.stringify(d)}`);
  r = await postSuppr(tokSuper, { eglise_id: annexe2, confirmer: true });
  d = await j(r);
  check("confirmation super admin 200", r.status === 200 && d.ok === true, `${r.status} ${JSON.stringify(d)}`);
  check("annexe 2 supprimée", (await count(`SELECT id FROM churches WHERE id='${annexe2}'`)) === 0);
  check("membre de l'annexe 2 supprimé", (await count(`SELECT id FROM members WHERE id='${reel2}'`)) === 0);
  check("contribution de l'annexe 2 supprimée", (await count(`SELECT id FROM contributions WHERE payment_ref='WAVE-ANN2-001'`)) === 0);

  console.log("Leurres intacts :");
  check("ADJA intact", (await count(`SELECT id FROM members WHERE id='${adja}'`)) === 1);
  check("dîme réelle intacte", (await count(`SELECT id FROM contributions WHERE payment_ref='WAVE-REAL-001'`)) === 1);
  check("campagne réelle intacte", (await count(`SELECT id FROM campagnes WHERE nom='Campagne réelle'`)) === 1);
  check("église mère intacte", (await count(`SELECT id FROM churches WHERE id='${mere}'`)) === 1);
  check("église indépendante et son membre TEST intacts",
    (await count(`SELECT id FROM churches WHERE id='${independante}'`)) === 1 &&
    (await count(`SELECT id FROM members WHERE full_name='TEST Membre Ailleurs'`)) === 1);
  check("journal : 4 suppressions + 3 résumés au total",
    (await count(`SELECT id FROM audit_logs WHERE action='suppression_eglise.supprime'`)) === 4 &&
    (await count(`SELECT id FROM audit_logs WHERE action='suppression_eglise.execute'`)) === 3);
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
  await db.end();
}
console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko === 0 ? 0 : 1);
