/* Test local Bascule entre espaces + accès spécial Plateforme (migration 032)
 * — base PostgreSQL de test seulement, jamais Render.
 * Usage :
 *   sudo -u postgres psql -c "CREATE DATABASE esc_bascule_test;"
 *   DATABASE_URL=<redacted>
 *   node test-bascule-espaces.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis
 * toutes les migrations, démarre l'API (tsx server/src/index.ts,
 * PORT 3113) et exerce la bascule entre espaces, la liste filtrée, la
 * séparation des connexions et le cycle de vie des accès Plateforme.
 * Il ne supprime pas la base : la supprimer après, à la main.
 *
 * Cas testés : bascule mère→mère (200), mère→annexe (403), annexe→annexe
 * même mère (200), annexe→annexe autre mère (403), membre→membre même
 * ancre (200) et autre ancre (403), plateforme→plateforme (200), église
 * inconnue (400), session inchangée après un refus ; liste « Mes églises »
 * filtrée par espace ; connexion Plateforme séparée (403/400) ; aide :
 * création (201), double création (409), initialisation du mot de passe,
 * connexion aide (200), chiffres (200), gestion refusée (403), révocation
 * (200) puis session révoquée (401).
 */
import { spawn } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3113";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

function decodeJwt(token) {
  const part = token.split(".")[1];
  return JSON.parse(Buffer.from(part.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString());
}

const db = new Client({ connectionString: DB });
await db.connect();
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of readdirSync("../db/migrations").sort()) {
  if (!f.endsWith(".sql")) continue;
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const table = await db.query(`SELECT 1 FROM information_schema.tables WHERE table_name = 'acces_plateforme'`);
check("migration 032 : table acces_plateforme créée", table.rowCount === 1);
const role = await db.query(`SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'user_role' AND e.enumlabel = 'aide_plateforme'`);
check("migration 032 : rôle aide_plateforme dans l'enum", role.rowCount === 1);

const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const church = async (code, name, parent = null) =>
  (await q(`INSERT INTO churches (code, code_fidele, name, city, status, parent_church_id) VALUES ($1, $2, $3, 'Abidjan', 'active', $4) RETURNING id`, [code, `ESC-F-${code.slice(4)}`, name, parent]))[0].id;
const mereA = await church("ESC-BAS-A", "Mère A");
const mereB = await church("ESC-BAS-B", "Mère B");
const annexeA1 = await church("ESC-BAS-A1", "Annexe A1", mereA);
const annexeA2 = await church("ESC-BAS-A2", "Annexe A2", mereA);
const annexeB1 = await church("ESC-BAS-B1", "Annexe B1", mereB);
async function user(email, fullName, memberships) {
  const u = (await q(`INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id`, [email, hash, fullName]))[0].id;
  for (const [egliseId, roleName] of memberships) {
    await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`, [u, egliseId, roleName]);
  }
  return u;
}
const adminA = await user("admin-a@bascule.test", "Admin A", [[mereA, "admin_eglise"], [annexeA1, "admin_eglise"], [annexeA2, "admin_eglise"], [mereB, "admin_eglise"], [annexeB1, "admin_eglise"]]);
const membreA = await user("membre-a@bascule.test", "Membre A", [[mereA, "membre"], [annexeA1, "membre"], [mereB, "membre"]]);
const existantA = await user("existant-a@bascule.test", "Existant A", [[mereA, "admin_eglise"]]);
const superA = await user("super-a@bascule.test", "Super A", [[mereA, "super_admin"], [mereB, "super_admin"]]);

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3113", DATABASE_URL: DB, JWT_SECRET: "test-secret-bascule-32-caracteres" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const appel = async (method, path, token, body) => {
    const r = await fetch(`${BASE}${path}`, {
      method,
      headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    return { status: r.status, d: await j(r) };
  };
  const login = (email, opts = {}) => appel("POST", "/auth/login", null, { identifiant: email, password: "Test1234!", channel: "web", ...opts });
  const basculer = (token, churchId) => appel("POST", "/auth/eglise-active", token, { church_id: churchId });
  const mesEglises = (token) => appel("GET", "/moi/eglises?limite=100", token);
  const moi = (token) => appel("GET", "/moi/eglise", token);
  const ids = (d) => (d.eglises ?? []).map((e) => e.church.id).sort();
  const memeEnsemble = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());

  console.log("Connexion séparée :");
  let r = await login("admin-a@bascule.test");
  check("connexion normale admin 200, rôle admin_eglise", r.status === 200 && r.d.church?.role === "admin_eglise", `status=${r.status} ${JSON.stringify(r.d).slice(0, 160)}`);
  r = await login("admin-a@bascule.test", { plateforme: true });
  check("connexion Plateforme admin 403 pas_acces_plateforme", r.status === 403 && r.d.error === "pas_acces_plateforme", `status=${r.status} ${JSON.stringify(r.d).slice(0, 120)}`);
  r = await login("super-a@bascule.test", { plateforme: true });
  check("connexion Plateforme super_admin 200", r.status === 200 && r.d.church?.role === "super_admin", `status=${r.status} ${JSON.stringify(r.d).slice(0, 160)}`);
  const jetonSuper = r.d.token;
  r = await login("super-a@bascule.test");
  check("connexion normale super_admin 400 plateforme_seulement", r.status === 400 && r.d.error === "plateforme_seulement", `status=${r.status} ${JSON.stringify(r.d).slice(0, 120)}`);
  r = await login("super-a@bascule.test", { plateforme: true, church_id: mereB });
  check("connexion Plateforme avec church_id Mère B 200", r.status === 200 && r.d.church?.id === mereB, `status=${r.status} ${JSON.stringify(r.d).slice(0, 160)}`);
  r = await login("membre-a@bascule.test", { plateforme: true });
  check("connexion Plateforme membre 403 pas_acces_plateforme", r.status === 403 && r.d.error === "pas_acces_plateforme", `status=${r.status}`);

  console.log("Bascule entre espaces :");
  r = await login("admin-a@bascule.test", { church_id: mereA });
  const jetonAdminMere = r.d.token;
  r = await basculer(jetonAdminMere, mereB);
  check("mère→mère 200, nouveau jeton sur Mère B", r.status === 200 && decodeJwt(r.d.token).churchId === mereB && decodeJwt(r.d.token).role === "admin_eglise", `status=${r.status} ${JSON.stringify(r.d).slice(0, 160)}`);
  r = await basculer(jetonAdminMere, annexeA1);
  check("mère→annexe 403 changement_espace_refuse", r.status === 403 && r.d.error === "changement_espace_refuse", `status=${r.status} ${JSON.stringify(r.d).slice(0, 120)}`);
  r = await moi(jetonAdminMere);
  check("session inchangée après un refus (toujours Mère A)", r.status === 200 && r.d.church?.id === mereA && r.d.role === "admin_eglise", `status=${r.status}`);
  r = await login("admin-a@bascule.test", { church_id: annexeA1 });
  const jetonAdminAnnexe = r.d.token;
  r = await basculer(jetonAdminAnnexe, annexeA2);
  check("annexe→annexe même mère 200", r.status === 200 && decodeJwt(r.d.token).churchId === annexeA2, `status=${r.status}`);
  r = await basculer(jetonAdminAnnexe, annexeB1);
  check("annexe→annexe autre mère 403", r.status === 403 && r.d.error === "changement_espace_refuse", `status=${r.status}`);
  r = await basculer(jetonAdminMere, "00000000-0000-0000-0000-000000000000");
  check("église inconnue 400 invalid_church", r.status === 400 && r.d.error === "invalid_church", `status=${r.status}`);
  r = await login("membre-a@bascule.test", { church_id: mereA });
  const jetonMembre = r.d.token;
  r = await basculer(jetonMembre, annexeA1);
  check("membre→membre même ancre 200", r.status === 200 && decodeJwt(r.d.token).churchId === annexeA1 && decodeJwt(r.d.token).role === "membre", `status=${r.status}`);
  r = await basculer(jetonMembre, mereB);
  check("membre→membre autre ancre 403", r.status === 403 && r.d.error === "changement_espace_refuse", `status=${r.status}`);
  r = await basculer(jetonSuper, mereB);
  check("plateforme→plateforme 200", r.status === 200 && decodeJwt(r.d.token).churchId === mereB && decodeJwt(r.d.token).role === "super_admin", `status=${r.status}`);

  console.log("Liste « Mes églises » filtrée par espace :");
  r = await mesEglises(jetonAdminMere);
  check("admin sur Mère A : Mère A et Mère B seulement", r.status === 200 && memeEnsemble(ids(r.d), [mereA, mereB]), `status=${r.status} ids=${JSON.stringify(ids(r.d))}`);
  r = await mesEglises(jetonAdminAnnexe);
  check("admin sur Annexe A1 : Annexe A1 et Annexe A2 seulement", r.status === 200 && memeEnsemble(ids(r.d), [annexeA1, annexeA2]), `status=${r.status} ids=${JSON.stringify(ids(r.d))}`);
  r = await mesEglises(jetonMembre);
  check("membre sur Mère A : Mère A et Annexe A1 seulement", r.status === 200 && memeEnsemble(ids(r.d), [mereA, annexeA1]), `status=${r.status} ids=${JSON.stringify(ids(r.d))}`);
  r = await mesEglises(jetonSuper);
  check("super_admin : accès Plateforme seulement", r.status === 200 && memeEnsemble(ids(r.d), [mereA, mereB]) && r.d.eglises.every((e) => e.role === "super_admin"), `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);

  console.log("Accès Plateforme, cycle de vie d'une aide :");
  r = await appel("GET", "/plateforme/acces", jetonSuper);
  const accesSuper = (r.d.acces ?? []).find((a) => a.email === "super-a@bascule.test");
  check("GET /plateforme/acces liste le super_admin, droits chiffres+acces", r.status === 200 && accesSuper?.role === "super_admin" && memeEnsemble(accesSuper.droits, ["chiffres", "acces"]), `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);
  r = await appel("POST", "/plateforme/acces", jetonSuper, { email: "aide@bascule.test", full_name: "Aide Bascule", droits: ["chiffres"] });
  check("POST /plateforme/acces nouveau compte 201, lien d'invitation", r.status === 201 && r.d.deja_membre === false && typeof r.d.lien_invitation === "string" && r.d.lien_invitation.includes("initialiser?token="), `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);
  const lienAide = r.d.lien_invitation;
  r = await appel("POST", "/plateforme/acces", jetonSuper, { email: "aide@bascule.test", droits: ["chiffres"] });
  check("double création 409 deja_acces_plateforme", r.status === 409 && r.d.error === "deja_acces_plateforme", `status=${r.status}`);
  r = await login("aide@bascule.test", { plateforme: true });
  check("aide sans mot de passe : connexion refusée", r.status === 401 && r.d.error === "password_not_set", `status=${r.status} ${JSON.stringify(r.d).slice(0, 120)}`);
  const jetonInvitation = new URL(lienAide).searchParams.get("token");
  r = await appel("POST", "/auth/initialiser-mot-de-passe", null, { token: jetonInvitation, mot_de_passe: "Test1234!" });
  check("initialisation du mot de passe par le lien 200", r.status === 200, `status=${r.status} ${JSON.stringify(r.d).slice(0, 120)}`);
  r = await login("aide@bascule.test", { plateforme: true });
  check("connexion aide Plateforme 200, rôle aide_plateforme", r.status === 200 && r.d.church?.role === "aide_plateforme", `status=${r.status} ${JSON.stringify(r.d).slice(0, 160)}`);
  const jetonAide = r.d.token;
  const refreshAide = r.d.refresh_token;
  r = await appel("GET", "/plateforme/chiffres", jetonAide);
  check("aide avec le droit chiffres : GET /plateforme/chiffres 200", r.status === 200 && typeof r.d.chiffres?.eglises_total === "number", `status=${r.status}`);
  r = await appel("GET", "/plateforme/acces", jetonAide);
  check("aide : GET /plateforme/acces 403", r.status === 403, `status=${r.status}`);
  r = await appel("GET", "/plateforme/chiffres", jetonMembre);
  check("membre : GET /plateforme/chiffres 403", r.status === 403, `status=${r.status}`);
  r = await appel("POST", "/plateforme/acces", jetonSuper, { email: "existant-a@bascule.test", droits: ["chiffres"] });
  check("POST /plateforme/acces compte existant 201, deja_membre, sans lien", r.status === 201 && r.d.deja_membre === true && !r.d.lien_invitation, `status=${r.status} ${JSON.stringify(r.d).slice(0, 160)}`);
  r = await login("existant-a@bascule.test", { plateforme: true });
  check("existant devenu aide : connexion Plateforme 200, rôle aide_plateforme, ancre Mère B", r.status === 200 && r.d.church?.role === "aide_plateforme" && r.d.church?.id === mereB, `status=${r.status} ${JSON.stringify(r.d).slice(0, 200)}`);
  const jetonExistantAide = r.d.token;
  r = await appel("GET", "/plateforme/chiffres", jetonExistantAide);
  check("existant devenu aide : chiffres 200", r.status === 200, `status=${r.status}`);
  const aideId = (await q(`SELECT id FROM users WHERE email = 'aide@bascule.test'`))[0].id;
  r = await appel("DELETE", `/plateforme/acces/${aideId}`, jetonSuper);
  check("révocation de l'aide 200", r.status === 200 && r.d.ok === true, `status=${r.status}`);
  r = await moi(jetonAide);
  check("session de l'aide révoquée 401", r.status === 401, `status=${r.status}`);
  r = await appel("POST", "/auth/refresh", null, { refresh_token: refreshAide });
  check("jeton de rafraîchissement de l'aide révoqué 401", r.status === 401, `status=${r.status}`);
  r = await appel("DELETE", `/plateforme/acces/${existantA}`, jetonSuper);
  check("révocation de l'aide existant 200", r.status === 200, `status=${r.status}`);
  r = await moi(jetonExistantAide);
  check("session de l'existant aide révoqué 401", r.status === 401, `status=${r.status}`);
  r = await appel("DELETE", `/plateforme/acces/${superA}`, jetonSuper);
  check("révocation de soi-même 409", r.status === 409, `status=${r.status}`);
  r = await appel("DELETE", "/plateforme/acces/00000000-0000-0000-0000-000000000000", jetonSuper);
  check("révocation d'un inconnu 404", r.status === 404, `status=${r.status}`);
} finally {
  try { process.kill(-server.pid, "SIGTERM"); } catch {}
}
console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko ? 1 : 0);
