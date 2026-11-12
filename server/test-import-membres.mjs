/* Test local import des fidèles (tranche A) — base PostgreSQL de test
 * seulement, jamais Render.
 * Usage : DATABASE_URL=<redacted>
 *   node test-import-membres.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis
 * toutes les migrations, démarre l'API (tsx server/src/index.ts, PORT
 * 3121) et exerce les routes. Il supprime la base à la fin.
 */
import { spawn } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3121";
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
  if (!f.endsWith(".sql")) continue;
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const churchA = (await q(`INSERT INTO churches (code,code_fidele,name,status) VALUES ('ESC-TEST-IMP-A','ESC-F-IMPA','Église Test Import A','active') RETURNING id`))[0].id;
const churchB = (await q(`INSERT INTO churches (code,code_fidele,name,status) VALUES ('ESC-TEST-IMP-B','ESC-F-IMPB','Église Test Import B','active') RETURNING id`))[0].id;
async function user(email, church, role, memberId = null) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name,member_id) VALUES ($1,$2,$3,$4) RETURNING id`, [email, hash, email, memberId]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [u, church, role]);
  return u;
}
const adminA = await user("admin-a@test.ci", churchA, "admin_eglise");
const membreA = await user("membre-a@test.ci", churchA, "membre");
await user("admin-b@test.ci", churchB, "admin_eglise");
// Membre déjà présent : doublon de base (e-mail + nom + naissance).
await q(`INSERT INTO members (church_id,matricule,full_name,phone,email,birth_date,sexe,status) VALUES ($1,'M-KJ-010190-01','Jean KOFFI','0707777777','koffi@test.ci','1990-01-01','M','actif')`, [churchA]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3121", DATABASE_URL: DB, JWT_SECRET: "test-secret-import-32-caracteres-minimum" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokAdmin = await login("admin-a@test.ci");
  const tokMembre = await login("membre-a@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };

  const CSV = [
    "nom;prenom;telephone;email;naissance;sexe;departement;fonction;poste;cellule",
    "KOUASSI;Aminata;0701111111;aminata@test.ci;1992-05-10;F;Louange;Chantre;Collaborateur;Cellule A",
    "YAO;Serge;0702222222;serge@test.ci;1988-03-15;M;Jeunesse;;Animateur;",
    "BAD;Email;0703333333;pas-un-email;1990-01-01;M;;;;",
    "SEUL;;0704444444;seul@test.ci;1990-01-01;M;;;;",
    "DATE;Mauvaise;0705555555;date@test.ci;1990-13-40;M;;;;",
    "SEXE;Mauvais;0706666666;sexe@test.ci;1990-01-01;X;;;;",
    "KOFFI;Jean;0707777777;koffi@test.ci;1990-01-01;M;;;;",
    "DOUBLON;Fichier;0708888888;aminata@test.ci;1995-06-06;F;;;;",
    "EXEMPLE;Jean;0700000000;jean.exemple@exemple.ci;1990-01-01;M;Louange;Chantre;Collaborateur;Exemple",
    "KOFFI;Jean;0709999999;autre@test.ci;1990-01-01;M;;;;",
  ].join("\n");

  console.log("Modèle :");
  let r = await fetch(`${BASE}/import/modele`, { headers: { Authorization: `Bearer ${tokAdmin}` } });
  let texte = await r.text();
  check("modèle 200 CSV", r.ok && (r.headers.get("content-type") ?? "").includes("text/csv"), String(r.status));
  check("modèle : en-têtes + ligne d'exemple", texte.includes("nom;prenom;telephone;email;naissance;sexe;departement;fonction;poste;cellule") && texte.includes("EXEMPLE"), texte.slice(0, 120));

  console.log("Droits :");
  r = await fetch(`${BASE}/import/apercu`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ contenu_csv: CSV }) });
  check("sans jeton 401", r.status === 401, String(r.status));
  r = await fetch(`${BASE}/import/apercu`, { method: "POST", headers: H(tokMembre), body: JSON.stringify({ contenu_csv: CSV }) });
  check("membre 403", r.status === 403, String(r.status));
  r = await fetch(`${BASE}/import/modele`, { headers: { Authorization: `Bearer ${tokMembre}` } });
  check("modèle : membre 403", r.status === 403, String(r.status));

  console.log("Aperçu CSV :");
  r = await fetch(`${BASE}/import/apercu`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ contenu_csv: CSV, nom_fichier: "fideles.csv" }) });
  let d = await j(r);
  check("aperçu 200", r.status === 200, `${r.status} ${JSON.stringify(d).slice(0, 200)}`);
  check("aperçu : 10 lignes", d.total_lignes === 10, JSON.stringify(d.total_lignes));
  check("aperçu : 2 valides", d.valides === 2, JSON.stringify(d.valides));
  check("aperçu : 5 en erreur", d.invalides === 5, JSON.stringify(d.invalides));
  check("aperçu : 3 doublons", d.doublons === 3, JSON.stringify(d.doublons));
  check("aperçu : colonnes détectées", (d.colonnes ?? []).includes("nom") && (d.colonnes ?? []).includes("prenom"), JSON.stringify(d.colonnes));
  check("aperçu : auto-mapping nom/prenom", d.mapping?.nom === "nom" && d.mapping?.prenom === "prenom", JSON.stringify(d.mapping));
  const ligneExemple = (d.lignes ?? []).find((l) => l.ligne === 10);
  check("aperçu : ligne d'exemple signalée", ligneExemple && (ligneExemple.erreurs ?? []).join(" ").includes("exemple"), JSON.stringify(ligneExemple));
  const ligneDoublon = (d.lignes ?? []).find((l) => l.ligne === 8);
  check("aperçu : doublon en base marqué", ligneDoublon && ligneDoublon.doublon === true, JSON.stringify(ligneDoublon));

  console.log("Aperçu lignes JSON (chemin XLSX) :");
  r = await fetch(`${BASE}/import/apercu`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ lignes: [{ nom: "TRAORE", prenom: "Awa", email: "awa@test.ci", naissance: "1995-07-20", sexe: "F" }] }) });
  d = await j(r);
  check("aperçu lignes 200, 1 valide", r.status === 200 && d.valides === 1, `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/import/apercu`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ lignes: [{ "Nom de famille": "DIALLO", "Prénom": "Moussa" }], mapping: { "Nom de famille": "nom", "Prénom": "prenom" } }) });
  d = await j(r);
  check("aperçu : correspondance manuelle 1 valide", r.status === 200 && d.valides === 1, `${r.status} ${JSON.stringify(d)}`);
  r = await fetch(`${BASE}/import/apercu`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ contenu_csv: "telephone;email\n0701111111;a@test.ci\n" }) });
  check("aperçu : sans nom ni prénom 400", r.status === 400, String(r.status));

  console.log("Confirmation :");
  r = await fetch(`${BASE}/import/confirmer`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ contenu_csv: CSV, nom_fichier: "fideles.csv" }) });
  d = await j(r);
  check("confirmation 201", r.status === 201, `${r.status} ${JSON.stringify(d).slice(0, 300)}`);
  check("rapport : 2 créés", d.crees === 2, JSON.stringify(d.crees));
  check("rapport : 3 ignorés", d.ignores === 3, JSON.stringify(d.ignores));
  check("rapport : 5 en erreur", d.invalides === 5, JSON.stringify(d.invalides));
  check("rapport : statut partiel", d.statut === "partiel", JSON.stringify(d.statut));
  const crees = await q(`SELECT id, matricule, full_name, user_id, status FROM members WHERE church_id = $1 AND full_name IN ('Aminata KOUASSI','Serge YAO') ORDER BY full_name`, [churchA]);
  check("membres créés en base", crees.length === 2, JSON.stringify(crees));
  check("matricule attribué (M-…)", crees.every((m) => /^M-/.test(m.matricule)), JSON.stringify(crees.map((m) => m.matricule)));
  check("statut actif, aucun compte créé", crees.every((m) => m.status === "actif" && m.user_id === null), JSON.stringify(crees));
  const rapports = await q(`SELECT * FROM imports_membres WHERE church_id = $1`, [churchA]);
  check("historique imports_membres : 1 ligne", rapports.length === 1 && rapports[0].crees === 2 && rapports[0].ignores === 3, JSON.stringify(rapports));
  const audits = await q(`SELECT * FROM audit_logs WHERE church_id = $1 AND action = 'import_membres.confirme'`, [churchA]);
  check("journal audit_logs : import journalisé", audits.length === 1, JSON.stringify(audits.length));

  console.log("Réimport (doublons) :");
  r = await fetch(`${BASE}/import/confirmer`, { method: "POST", headers: H(tokAdmin), body: JSON.stringify({ contenu_csv: CSV, nom_fichier: "fideles.csv" }) });
  d = await j(r);
  check("réimport 201, 0 créé", r.status === 201 && d.crees === 0, `${r.status} ${JSON.stringify(d)}`);
  check("réimport : 5 ignorés", d.ignores === 5, JSON.stringify(d.ignores));
  check("réimport : statut echoue", d.statut === "echoue", JSON.stringify(d.statut));
  const total = await q(`SELECT count(*)::int AS n FROM members WHERE church_id = $1`, [churchA]);
  check("aucun membre en double en base", total[0].n === 3, JSON.stringify(total));

  console.log("Historique :");
  r = await fetch(`${BASE}/import/historique`, { headers: { Authorization: `Bearer ${tokAdmin}` } });
  d = await j(r);
  check("historique 200, 2 imports", r.ok && (d.imports ?? []).length === 2, `${r.status} ${JSON.stringify(d).slice(0, 200)}`);
} finally {
  // Le serveur est détaché : tuer tout son groupe, sinon le processus
  // node garde des connexions et DROP DATABASE échoue.
  try { process.kill(-server.pid, "SIGKILL"); } catch { try { server.kill("SIGKILL"); } catch {} }
  await sleep(1000);
  await db.end();
  // Base de test supprimée après le test.
  const dbName = new URL(DB).pathname.replace(/^\//, "");
  const maintenance = new Client({ connectionString: DB.replace(`/${dbName}`, "/postgres") });
  try {
    await maintenance.connect();
    await maintenance.query(`DROP DATABASE IF EXISTS "${dbName}"`);
    console.log(`Base ${dbName} supprimée.`);
  } catch (e) { console.log(`Base ${dbName} non supprimée : ${e.message}`); }
  finally { await maintenance.end().catch(() => {}); }
}

console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko > 0 ? 1 : 0);
