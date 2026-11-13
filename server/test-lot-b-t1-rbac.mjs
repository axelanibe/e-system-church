/* Test local de la tranche 1 du Lot B — confidentialité RBAC et trois
 * contournements (12/11/2026) — base PostgreSQL de test seulement, jamais
 * Render.
 * Usage : DATABASE_URL=postgresql://esystem_test:test@localhost:5432/esystem_test_t1
 *   node test-lot-b-t1-rbac.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis
 * toutes les migrations, démarre l'API (tsx server/src/index.ts, PORT
 * 3107) et exerce les routes. Il ne supprime pas la base : la supprimer
 * après, à la main.
 *
 * T1 : (1) lecture pastorale réservée à admin_eglise et
 * responsable_culte, lectures journalisées ; trésorier autorisé sur son
 * rapport financier et le consolidé ; consolidé détaillé en agrégats
 * seulement, jamais nominatif. (2) Trois contournements fermés : PATCH
 * générique sur depenses.statut, PATCH/DELETE prières par tout membre,
 * PATCH réservations sans validation de chevauchement. (3) E19 serveur :
 * 409 français explicite sur suppression d'un membre lié à un transfert.
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
// 002 est sautée : db/schema.sql contient déjà la même vue récursive,
// avec les casts ::int ajoutés après (11/11, correctif bigint) —
// CREATE OR REPLACE VIEW refuse de repasser les colonnes en bigint.
// Incohérence préexistante du dépôt, hors tranche 1.
for (const f of readdirSync("../db/migrations").sort()) {
  if (!f.endsWith(".sql") || f === "002_vue_consolidee_recursive.sql") continue;
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const church = async (code, name, parent = null) =>
  (await q(`INSERT INTO churches (code,code_fidele,name,city,status,parent_church_id) VALUES ($1,$2,$3,'Abidjan','active',$4) RETURNING id`, [code, `${code}-F`, name, parent]))[0].id;
const mere = await church("ESC-T1MERE", "Église Mère T1");
const annexe = await church("ESC-T1ANNX", "Annexe T1", mere);
async function user(email, ch, role) {
  const u = (await q(`INSERT INTO users (email,password_hash,full_name) VALUES ($1,$2,$3) RETURNING id`, [email, hash, email]))[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [u, ch, role]);
  return u;
}
const adminId = await user("admin-t1@test.ci", mere, "admin_eglise");
const tresorierId = await user("tresorier-t1@test.ci", mere, "tresorier");
const cultId = await user("culte-t1@test.ci", mere, "responsable_culte");
const membreId = await user("membre-t1@test.ci", mere, "membre");

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3107", DATABASE_URL: DB, JWT_SECRET: "test-secret-lot-b-t1-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "Test1234!" }) });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokAdmin = await login("admin-t1@test.ci");
  const tokTres = await login("tresorier-t1@test.ci");
  const tokCulte = await login("culte-t1@test.ci");
  const tokMembre = await login("membre-t1@test.ci");
  const H = (t) => ({ "Content-Type": "application/json", Authorization: `Bearer ${t}` });
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const call = async (method, path, tok, body) => {
    const r = await fetch(`${BASE}${path}`, { method, headers: H(tok), body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, body: await j(r) };
  };

  console.log("1. Lecture pastorale réservée admin + responsable de culte :");
  let membre = await call("POST", "/membres", tokAdmin, { full_name: "Katia Test", status: "actif" });
  check("POST /membres admin : 201", membre.status === 201, String(membre.status));
  const membreRef = membre.body.id;
  let r = await call("POST", "/parcours-nouveaux", tokAdmin, { member_id: membreRef, etape: "accueil" });
  check("POST /parcours-nouveaux admin : 201", r.status === 201, String(r.status));
  r = await call("POST", "/visites-pastorales", tokAdmin, { member_id: membreRef, date_visite: "2026-11-12T10:00:00Z", compte_rendu: "Visite confidentielle." });
  check("POST /visites-pastorales admin : 201", r.status === 201, String(r.status));
  r = await call("POST", "/accompagnements", tokAdmin, { member_id: membreRef, type: "difficulte", description: "Suivi sensible." });
  check("POST /accompagnements admin : 201", r.status === 201, String(r.status));
  r = await call("GET", "/parcours-nouveaux", tokTres);
  check("GET /parcours-nouveaux trésorier : 403", r.status === 403, String(r.status));
  r = await call("GET", "/visites-pastorales", tokTres);
  check("GET /visites-pastorales trésorier : 403", r.status === 403, String(r.status));
  r = await call("GET", "/accompagnements", tokTres);
  check("GET /accompagnements trésorier : 403", r.status === 403, String(r.status));
  r = await call("GET", "/parcours-nouveaux", tokMembre);
  check("GET /parcours-nouveaux membre : 403", r.status === 403, String(r.status));
  r = await call("GET", "/parcours-nouveaux", tokCulte);
  check("GET /parcours-nouveaux responsable culte : 200", r.status === 200, String(r.status));
  r = await call("GET", "/visites-pastorales", tokAdmin);
  check("GET /visites-pastorales admin : 200", r.status === 200, String(r.status));
  const lectures = await q(`SELECT action FROM audit_logs WHERE action LIKE '%.lu' ORDER BY created_at DESC LIMIT 5`);
  check("lectures pastorales journalisées (audit_logs *.lu)", lectures.some((x) => x.action === "parcours_nouveau.lu" || x.action === "visite_pastorale.lu"), JSON.stringify(lectures.map((x) => x.action)));

  console.log("2a. Contournement dépenses : PATCH générique sur statut refusé :");
  r = await call("POST", "/depenses", tokTres, { montant_fcfa: 5000, motif: "Achat test", date_depense: "2026-11-12" });
  check("POST /depenses trésorier : 201", r.status === 201, String(r.status));
  const depenseId = r.body.id;
  r = await call("PATCH", `/depenses/${depenseId}`, tokTres, { statut: "payee" });
  check("PATCH /depenses/:id {statut: payee} : 400", r.status === 400, String(r.status));
  r = await call("GET", `/depenses/${depenseId}`, tokAdmin);
  check("dépense toujours « soumise » après le PATCH refusé", r.body.statut === "soumise", String(r.body.statut));
  r = await call("PATCH", `/depenses/${depenseId}/statut`, tokTres, { statut: "payee" });
  check("PATCH /depenses/:id/statut {payee} depuis soumise : 409", r.status === 409, String(r.status));
  r = await call("PATCH", `/depenses/${depenseId}/statut`, tokTres, { statut: "validee_tresorier" });
  check("PATCH /depenses/:id/statut {validee_tresorier} : 200", r.status === 200, String(r.status));
  r = await call("PATCH", `/depenses/${depenseId}`, tokTres, { montant_fcfa: 6000 });
  check("PATCH /depenses/:id {montant} (autre champ) : 200", r.status === 200, String(r.status));

  console.log("2b. Contournement prières : PATCH/DELETE restreints, confidentiel effectif :");
  r = await call("POST", "/demandes-priere", tokMembre, { sujet: "Prière publique", confidentiel: false });
  check("POST /demandes-priere membre (non confidentielle) : 201", r.status === 201, String(r.status));
  const publiqueId = r.body.id;
  r = await call("POST", "/demandes-priere", tokMembre, { sujet: "Prière secrète", confidentiel: true });
  check("POST /demandes-priere membre (confidentielle) : 201", r.status === 201, String(r.status));
  const secreteId = r.body.id;
  r = await call("GET", "/demandes-priere", tokMembre);
  check("GET /demandes-priere membre : 200, 1 seule visible (la non confidentielle)", r.status === 200 && r.body.total === 1 && r.body.items[0].id === publiqueId, `status=${r.status} total=${r.body.total}`);
  r = await call("GET", `/demandes-priere/${secreteId}`, tokMembre);
  check("GET /demandes-priere/:id confidentielle par un membre : 404", r.status === 404, String(r.status));
  r = await call("PATCH", `/demandes-priere/${publiqueId}`, tokMembre, { statut: "terminee" });
  check("PATCH /demandes-priere/:id par un membre : 403", r.status === 403, String(r.status));
  r = await call("DELETE", `/demandes-priere/${publiqueId}`, tokMembre);
  check("DELETE /demandes-priere/:id par un membre : 403", r.status === 403, String(r.status));
  r = await call("GET", "/demandes-priere", tokAdmin);
  check("GET /demandes-priere admin : 200, 2 visibles", r.status === 200 && r.body.total === 2, `status=${r.status} total=${r.body.total}`);
  r = await call("PATCH", `/demandes-priere/${publiqueId}`, tokCulte, { statut: "terminee" });
  check("PATCH /demandes-priere/:id responsable culte : 200", r.status === 200, String(r.status));
  // Auteur d'une demande confidentielle : il la voit, un autre membre non.
  const auteur = await call("POST", "/membres", tokAdmin, { full_name: "Auteur Prière", status: "actif" });
  await q(`UPDATE users SET member_id = $1 WHERE id = $2`, [auteur.body.id, membreId]);
  r = await call("POST", "/demandes-priere", tokMembre, { sujet: "Ma prière secrète", confidentiel: true, member_id: auteur.body.id });
  const mienneId = r.body.id;
  r = await call("GET", `/demandes-priere/${mienneId}`, tokMembre);
  check("GET sa propre demande confidentielle (auteur) : 200", r.status === 200, String(r.status));
  r = await call("GET", "/demandes-priere", tokTres);
  check("GET /demandes-priere trésorier : 200, voit la publique + aucune confidentielle d'autrui", r.status === 200 && r.body.items.every((x) => !x.confidentiel || x.id === mienneId) && r.body.total === 1, `status=${r.status} total=${r.body.total}`);
  r = await call("DELETE", `/demandes-priere/${publiqueId}`, tokAdmin);
  check("DELETE /demandes-priere/:id admin : 200", r.status === 200, String(r.status));
  // Correctif relecture PR #59 (Muse) : un simple membre ne peut déposer
  // que pour lui-même ; l'admin garde le dépôt pour un autre fidèle.
  const autre = await call("POST", "/membres", tokAdmin, { full_name: "Autre Fidèle", status: "actif" });
  r = await call("POST", "/demandes-priere", tokMembre, { sujet: "Pour un autre", confidentiel: true, member_id: autre.body.id });
  check("POST /demandes-priere membre avec le member_id d'un autre : 400", r.status === 400, String(r.status));
  r = await call("POST", "/demandes-priere", tokAdmin, { sujet: "Pour un autre (admin)", confidentiel: true, member_id: autre.body.id });
  check("POST /demandes-priere admin avec le member_id d'un autre : 201", r.status === 201, String(r.status));

  console.log("2c. Contournement réservations : PATCH revalide le chevauchement :");
  r = await call("POST", "/salles", tokAdmin, { nom: "Grande salle" });
  check("POST /salles admin : 201", r.status === 201, String(r.status));
  const salleId = r.body.id;
  r = await call("POST", "/reservations-salles", tokAdmin, { salle_id: salleId, titre: "Culte matin", debut: "2026-11-15T10:00:00Z", fin: "2026-11-15T11:00:00Z" });
  check("POST /reservations-salles 10h-11h : 201", r.status === 201, String(r.status));
  r = await call("POST", "/reservations-salles", tokAdmin, { salle_id: salleId, titre: "Réunion", debut: "2026-11-15T11:00:00Z", fin: "2026-11-15T12:00:00Z" });
  check("POST /reservations-salles 11h-12h : 201", r.status === 201, String(r.status));
  const resa2Id = r.body.id;
  r = await call("PATCH", `/reservations-salles/${resa2Id}`, tokAdmin, { debut: "2026-11-15T10:30:00Z" });
  check("PATCH réservation 11h→10h30 (chevauchement) : 400", r.status === 400, String(r.status));
  r = await call("PATCH", `/reservations-salles/${resa2Id}`, tokAdmin, { fin: "2026-11-15T09:00:00Z" });
  check("PATCH réservation fin avant début : 400", r.status === 400, String(r.status));
  r = await call("PATCH", `/reservations-salles/${resa2Id}`, tokAdmin, { statut: "annulee" });
  check("PATCH réservation annulation : 200", r.status === 200, String(r.status));
  r = await call("PATCH", `/reservations-salles/${resa2Id}`, tokAdmin, { debut: "2026-11-15T10:30:00Z" });
  check("PATCH réservation annulée vers un créneau pris : 200 (pas de chevauchement)", r.status === 200, String(r.status));

  console.log("3. E19 serveur : suppression d'un membre lié à un transfert :");
  const transfere = await call("POST", "/membres", tokAdmin, { full_name: "Transféré Test", status: "actif" });
  await q(`INSERT INTO transferts_membre (membre_id, membre_nom, ancien_matricule, eglise_depart_id, eglise_arrivee_id) VALUES ($1,$2,$3,$4,$5)`, [transfere.body.id, "Transféré Test", transfere.body.matricule, mere, annexe]);
  r = await call("DELETE", `/membres/${transfere.body.id}`, tokAdmin);
  check("DELETE /membres/:id lié à un transfert : 409 français explicite", r.status === 409 && /transfert/i.test(r.body.message ?? ""), `status=${r.status} message=${r.body.message}`);
  const libre = await call("POST", "/membres", tokAdmin, { full_name: "Libre Test", status: "actif" });
  r = await call("DELETE", `/membres/${libre.body.id}`, tokAdmin);
  check("DELETE /membres/:id sans transfert : 200", r.status === 200, String(r.status));

  console.log("4. Trésorier autorisé sur le rapport financier et le consolidé :");
  r = await call("GET", "/finances/rapport", tokTres);
  check("GET /finances/rapport trésorier : 200", r.status === 200, String(r.status));
  r = await call("GET", "/finances/rapport", tokMembre);
  check("GET /finances/rapport membre : 403", r.status === 403, String(r.status));
  r = await call("GET", "/rapports/consolide", tokTres);
  check("GET /rapports/consolide trésorier : 200", r.status === 200, String(r.status));
  r = await call("GET", "/rapports/consolide", tokMembre);
  check("GET /rapports/consolide membre : 403", r.status === 403, String(r.status));
  r = await call("GET", "/rapports/consolide/detail?periode=mois&mois=2026-11", tokTres);
  const sansTransactions = r.status === 200 && Array.isArray(r.body.branches) && r.body.branches.every((b) => !("transactions" in b));
  check("GET /rapports/consolide/detail trésorier : 200, agrégats seulement (pas de transactions)", sansTransactions, `status=${r.status} branches=${JSON.stringify((r.body.branches ?? []).map((b) => Object.keys(b)))}`);
} finally {
  server.kill();
  await db.end();
}
console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko ? 1 : 0);
