/* Test local tranche C — exports PDF, base PostgreSQL de test seulement,
 * jamais Render.
 * Usage (depuis server/) :
 *   DATABASE_URL=postgres://postgres@127.0.0.1:5432/esc_exports_test \
 *     node test-exports-pdf.mjs
 * Sans DATABASE_URL, cette même URL locale est utilisée par défaut.
 * Le script crée la base si besoin, applique db/schema.sql puis toutes les
 * migrations, démarre l'API (tsx server/src/index.ts, PORT 3123), exerce
 * les 4 routes d'export, puis supprime la base de test.
 */
import { spawn } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB =
  process.env.DATABASE_URL ??
  "postgres://postgres@127.0.0.1:5432/esc_exports_test";
const ADMIN_DB = DB.replace(/\/[^/]*$/, "/postgres");
const BASE = "http://127.0.0.1:3123";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0,
  ko = 0;
function check(nom, cond, extra = "") {
  if (cond) {
    ok++;
    console.log(`  OK  ${nom}`);
  } else {
    ko++;
    console.log(`  KO  ${nom} ${extra}`);
  }
}

// Crée la base de test (supprimée si elle existait déjà).
const admin = new Client({ connectionString: ADMIN_DB });
await admin.connect();
await admin.query(`DROP DATABASE IF EXISTS esc_exports_test`);
await admin.query(`CREATE DATABASE esc_exports_test`);
await admin.end();

const db = new Client({ connectionString: DB });
await db.connect();
// Schéma + toutes les migrations (même ordre que migrate.ts).
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of readdirSync("../db/migrations").sort()) {
  if (f.endsWith(".sql")) await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const churchA = (
  await q(
    `INSERT INTO churches (code, code_fidele, name, status) VALUES ('ESC-TEST-A','ESC-F-TEST-A','Église Test A','active') RETURNING id`,
  )
)[0].id;
const churchB = (
  await q(
    `INSERT INTO churches (code, code_fidele, name, parent_church_id, status) VALUES ('ESC-TEST-B','ESC-F-TEST-B','Église Test B',$1,'active') RETURNING id`,
    [churchA],
  )
)[0].id;
async function user(email, church, role, memberId = null) {
  const u = (
    await q(
      `INSERT INTO users (email,password_hash,full_name,member_id) VALUES ($1,$2,$3,$4) RETURNING id`,
      [email, hash, email, memberId],
    )
  )[0].id;
  await q(`INSERT INTO church_users (user_id,church_id,role) VALUES ($1,$2,$3)`, [
    u,
    church,
    role,
  ]);
  return u;
}
async function member(church, matricule, nom) {
  return (
    await q(
      `INSERT INTO members (church_id,matricule,full_name,status) VALUES ($1,$2,$3,'actif') RETURNING id`,
      [church, matricule, nom],
    )
  )[0].id;
}
const m1 = await member(churchA, "M-0001", "KOFFI JEAN");
const m2 = await member(churchA, "M-0002", "KOUASSI AMINATA");
const m3 = await member(churchB, "M-0003", "YAO SERGE");
const adminA = await user("admin-a@test.ci", churchA, "admin_eglise");
const tresA = await user("tresorier-a@test.ci", churchA, "tresorier");
const respA = await user("responsable-a@test.ci", churchA, "responsable_culte");
const membre1 = await user("membre1@test.ci", churchA, "membre", m1);
async function contrib(church, memberId, type, amount, status, date) {
  await q(
    `INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status,created_at) VALUES ($1,$2,$3,$4,'especes',$5,$6)`,
    [church, memberId, type, amount, status, date],
  );
}
await contrib(churchA, m1, "dime", 10000, "confirme", "2026-03-01");
await contrib(churchA, m1, "offrande", 5000, "confirme", "2026-05-10");
await contrib(churchA, m2, "don", 30000, "confirme", "2026-04-15");
await contrib(churchA, m1, "don", 2000, "en_attente", "2026-06-01");
await contrib(churchA, m2, "don", 7000, "annule", "2026-03-03");
await contrib(churchA, m2, "don", 40000, "confirme", "2025-12-20");
await contrib(churchA, null, "don", 15000, "confirme", "2026-02-01"); // anonyme
await contrib(churchB, m3, "don", 50000, "confirme", "2026-03-15"); // autre église
// 120 lignes en mars 2026 : le détail de mars doit tenir sur plusieurs pages.
for (let i = 0; i < 120; i++) {
  await contrib(churchA, m1, "don", 100, "confirme", "2026-03-02");
}
const posteEntretien = (
  await q(
    `INSERT INTO postes_budgetaires (church_id,nom,categorie) VALUES ($1,'Entretien','depense') RETURNING id`,
    [churchA],
  )
)[0].id;
await q(
  `INSERT INTO postes_budgetaires (church_id,nom,categorie) VALUES ($1,'Dimes','recette')`,
  [churchA],
);
await q(
  `INSERT INTO budgets (church_id,poste_id,annee,montant_prevu) VALUES ($1,$2,2026,500000)`,
  [churchA, posteEntretien],
);
async function depense(posteId, montant, motif, statut, date) {
  await q(
    `INSERT INTO depenses (church_id,poste_id,montant_fcfa,motif,statut,date_depense) VALUES ($1,$2,$3,$4,$5,$6)`,
    [churchA, posteId, montant, motif, statut, date],
  );
}
await depense(posteEntretien, 80000, "Réparation toit", "payee", "2026-03-05");
await depense(posteEntretien, 120000, "Achat chaises", "validee_pasteur", "2026-04-10");
await depense(posteEntretien, 5000, "Demande en cours", "soumise", "2026-03-06");
await depense(posteEntretien, 9000, "Demande refusée", "refusee", "2026-03-07");
const typeDimanche = (
  await q(
    `INSERT INTO culte_types (church_id,nom,jour_semaine,heure_debut,actif) VALUES ($1,'Dimanche',0,'09:00',true) RETURNING id`,
    [churchA],
  )
)[0].id;
async function culte(titre, dateHeure, orateur) {
  return (
    await q(
      `INSERT INTO cultes (church_id,culte_type_id,titre,date_heure,lieu,orateur,theme) VALUES ($1,$2,$3,$4,'Temple central',$5,'La foi') RETURNING id`,
      [churchA, typeDimanche, titre, dateHeure, orateur],
    )
  )[0].id;
}
const culte1 = await culte("Culte du dimanche", "2026-03-01 09:00:00+00", "Pasteur Yao");
const culte2 = await culte("Culte du soir", "2026-03-08 17:00:00+00", "Pasteur Yao");
await culte("Culte de Noël", "2025-12-25 09:00:00+00", "Pasteur Yao");
async function presence(culteId, memberId, statut) {
  await q(
    `INSERT INTO presences (church_id,culte_id,member_id,statut,mode) VALUES ($1,$2,$3,$4,'manuel')`,
    [churchA, culteId, memberId, statut],
  );
}
await presence(culte1, m1, "present");
await presence(culte1, m2, "absent");
await presence(culte2, m1, "present");
await presence(culte2, m2, "excuse");

const server = spawn("npx", ["tsx", "src/index.ts"], {
  cwd: process.cwd(),
  env: {
    ...process.env,
    PORT: "3123",
    DATABASE_URL: DB,
    JWT_SECRET: "test-secret-exports-pdf-32-caracteres",
  },
  stdio: "ignore",
  detached: true,
});
try {
  for (let i = 0; i < 30; i++) {
    try {
      const r = await fetch(`${BASE}/sante`);
      if (r.ok) break;
    } catch {}
    await sleep(500);
  }
  async function login(email) {
    const r = await fetch(`${BASE}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: "Test1234!" }),
    });
    const j = await r.json();
    if (!r.ok) throw new Error(`login ${email}: ${JSON.stringify(j)}`);
    return j.token;
  }
  const tokAdmin = await login("admin-a@test.ci");
  const tokTres = await login("tresorier-a@test.ci");
  const tokResp = await login("responsable-a@test.ci");
  const tokMembre = await login("membre1@test.ci");
  const H = (t) => ({ Authorization: `Bearer ${t}` });
  const pdf = async (path, token) => {
    const r = await fetch(`${BASE}${path}`, {
      headers: token ? H(token) : {},
    });
    const buf = Buffer.from(await r.arrayBuffer());
    return { r, buf, texte: buf.toString("latin1") };
  };
  const nbPages = (texte) => (texte.match(/\/Type \/Page(?!s)/g) ?? []).length;

  console.log("Détail finances :");
  let d = await pdf(
    "/exports/finances/detail?from=2026-03-01&to=2026-03-31",
    tokTres,
  );
  check("détail mars trésorier 200", d.r.status === 200, String(d.r.status));
  check(
    "détail content-type application/pdf",
    (d.r.headers.get("content-type") ?? "").startsWith("application/pdf"),
    d.r.headers.get("content-type") ?? "",
  );
  check(
    "détail content-disposition pièce jointe",
    (d.r.headers.get("content-disposition") ?? "").startsWith("attachment;"),
    d.r.headers.get("content-disposition") ?? "",
  );
  check("détail en-tête %PDF", d.texte.startsWith("%PDF"));
  check("détail titre présent", d.texte.includes("Détail des finances"));
  check("détail membre nommé", d.texte.includes("KOFFI JEAN"));
  check("détail dépense payée", d.texte.includes("Réparation toit"));
  check(
    "détail exclut l'autre église (50 000)",
    !d.texte.includes("50 000 FCFA"),
  );
  check(
    "détail exclut la dépense soumise",
    !d.texte.includes("Demande en cours"),
  );
  check("détail paginé (120 lignes)", nbPages(d.texte) >= 2, `pages=${nbPages(d.texte)}`);
  d = await pdf("/exports/finances/detail", tokAdmin);
  check("détail sans période admin 200", d.r.status === 200, String(d.r.status));
  check("détail toute période, anonyme inclus", d.texte.includes("Anonyme"));
  d = await pdf("/exports/finances/detail", tokMembre);
  check("détail membre 403", d.r.status === 403, String(d.r.status));
  d = await pdf("/exports/finances/detail", tokResp);
  check(
    "détail responsable de culte 403 (admin + trésorier seulement)",
    d.r.status === 403,
    String(d.r.status),
  );
  d = await pdf("/exports/finances/detail");
  check("détail sans jeton 401", d.r.status === 401, String(d.r.status));
  d = await pdf("/exports/finances/detail?from=pas-une-date", tokTres);
  check("détail date invalide 400", d.r.status === 400, String(d.r.status));
  d = await pdf(
    "/exports/finances/detail?from=2030-01-01&to=2030-01-31",
    tokTres,
  );
  check("détail période vide 200", d.r.status === 200, String(d.r.status));
  check(
    "détail période vide mention aucune donnée",
    d.texte.includes("Aucune donnée"),
    "mention absente",
  );

  console.log("Résumé finances :");
  d = await pdf("/exports/finances/resume?annee=2026", tokTres);
  check("résumé 2026 trésorier 200", d.r.status === 200, String(d.r.status));
  check("résumé en-tête %PDF", d.texte.startsWith("%PDF"));
  check("résumé titre présent", d.texte.includes("Résumé des finances"));
  check("résumé section par mois", d.texte.includes("Par mois"));
  check("résumé section par poste", d.texte.includes("Par poste"));
  check("résumé poste Entretien", d.texte.includes("Entretien"));
  d = await pdf("/exports/finances/resume", tokMembre);
  check("résumé membre 403", d.r.status === 403, String(d.r.status));

  console.log("Cultes :");
  d = await pdf(
    "/exports/cultes?from=2026-03-01&to=2026-03-31",
    tokMembre,
  );
  check("cultes mars membre 200 (lecture tous rôles)", d.r.status === 200, String(d.r.status));
  check("cultes en-tête %PDF", d.texte.startsWith("%PDF"));
  check("cultes titre présent", d.texte.includes("Cultes et présences"));
  check("cultes liste le culte de mars", d.texte.includes("Culte du dimanche"));
  check(
    "cultes exclut le culte hors période",
    !d.texte.includes("Culte de Noël"),
  );
  d = await pdf("/exports/cultes");
  check("cultes sans jeton 401", d.r.status === 401, String(d.r.status));
  d = await pdf(
    "/exports/cultes?from=2030-01-01&to=2030-01-31",
    tokAdmin,
  );
  check("cultes période vide 200", d.r.status === 200, String(d.r.status));
  check(
    "cultes période vide mention aucune donnée",
    d.texte.includes("Aucune donnée"),
    "mention absente",
  );

  console.log("Rapport consolidé :");
  d = await pdf("/exports/rapports/consolide", tokAdmin);
  check("consolidé admin 200", d.r.status === 200, String(d.r.status));
  check("consolidé en-tête %PDF", d.texte.startsWith("%PDF"));
  check("consolidé titre présent", d.texte.includes("Rapport consolidé"));
  check("consolidé total réseau", d.texte.includes("Total réseau"));
  check(
    "consolidé liste la sous-église (agrégat)",
    d.texte.includes("Église Test B"),
  );
  check(
    "consolidé sans détail nominatif (pas de nom de membre)",
    !d.texte.includes("KOFFI JEAN") && !d.texte.includes("YAO SERGE"),
  );
  d = await pdf("/exports/rapports/consolide", tokTres);
  check("consolidé trésorier 403", d.r.status === 403, String(d.r.status));
  d = await pdf("/exports/rapports/consolide", tokMembre);
  check("consolidé membre 403", d.r.status === 403, String(d.r.status));

  console.log(`\n${ok} OK, ${ko} KO`);
  if (ko > 0) process.exitCode = 1;
} finally {
  try {
    process.kill(-server.pid, "SIGTERM");
  } catch {}
  await sleep(500);
  await db.end();
  const admin2 = new Client({ connectionString: ADMIN_DB });
  await admin2.connect();
  await admin2.query(`DROP DATABASE IF EXISTS esc_exports_test`);
  await admin2.end();
  console.log("Base esc_exports_test supprimée.");
}
