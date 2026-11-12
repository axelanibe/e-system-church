// Test d'intégration de l'export SYCEBNL (tranche P6) : un état financier
// à la fois, généré depuis la vraie comptabilité, en PDF.
// Même forme que server/test-exports-pdf.mjs : base fraîche, schéma puis
// toutes les migrations, démarrage de l'API, appels HTTP, droits 401/403.
//
// Usage (depuis server/) :
//   DATABASE_URL=<redacted>
//     node test-sycebnl-p6.mjs
// Sans DATABASE_URL, cette même URL locale est utilisée par défaut.
// Base locale : PostgreSQL est nécessaire. Sans base locale, ce test
// ne peut pas tourner (constaté le 12 novembre 2026 : aucun PostgreSQL
// dans cette machine). Aucune migration créée par P6 : l'export se lit
// depuis les tables existantes.
import { spawn } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB =
  process.env.DATABASE_URL ??
  "postgres://postgres@127.0.0.1:5432/esc_sycebnl_test";
const ADMIN_DB = DB.replace(/\/[^/]*$/, "/postgres");
const BASE = "http://127.0.0.1:3124";
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

const admin = new Client({ connectionString: ADMIN_DB });
await admin.connect();
await admin.query(`DROP DATABASE IF EXISTS esc_sycebnl_test`);
await admin.query(`CREATE DATABASE esc_sycebnl_test`);
await admin.end();

const db = new Client({ connectionString: DB });
await db.connect();
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of readdirSync("../db/migrations").sort()) {
  if (f.endsWith(".sql"))
    await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const churchA = (
  await q(
    `INSERT INTO churches (code, code_fidele, name, status) VALUES ('ESC-TEST-A','ESC-F-TEST-A','Église Test A','active') RETURNING id`,
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
const adminA = await user("admin-a@test.ci", churchA, "admin_eglise");
const tresA = await user("tresorier-a@test.ci", churchA, "tresorier");
const membre1 = await user("membre1@test.ci", churchA, "membre", m1);
async function contrib(church, memberId, type, amount, status, date) {
  await q(
    `INSERT INTO contributions (church_id,member_id,type,amount_fcfa,payment_method,status,created_at) VALUES ($1,$2,$3,$4,'especes',$5,$6)`,
    [church, memberId, type, amount, status, date],
  );
}
// Exercice 2026 EXEMPLE : 12 000 000 de produits, 3 000 000 de charges.
// Exercice 2025 : 5 000 000 de produits, 2 000 000 de charges (ouverture).
await contrib(churchA, m1, "dime", 8000000, "confirme", "2026-01-10");
await contrib(churchA, m1, "offrande", 3000000, "confirme", "2026-02-10");
await contrib(churchA, m1, "don", 1000000, "confirme", "2026-03-10");
await contrib(churchA, m1, "depense", 3000000, "confirme", "2026-04-10");
await contrib(churchA, m1, "don", 999999, "en_attente", "2026-05-10");
await contrib(churchA, m1, "don", 999999, "annule", "2026-05-11");
await contrib(churchA, m1, "don", 5000000, "confirme", "2025-06-10");
await contrib(churchA, m1, "depense", 2000000, "confirme", "2025-09-10");

async function login(email) {
  const r = await fetch(`${BASE}/auth/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, mot_de_passe: "Test1234!" }),
  });
  const j = await r.json().catch(() => null);
  return j?.token ?? null;
}

const api = spawn("node", ["dist/index.js"], {
  cwd: "server",
  env: { ...process.env, DATABASE_URL: DB, PORT: "3124" },
  stdio: "pipe",
});
try {
  let pret = false;
  for (let i = 0; i < 30 && !pret; i += 1) {
    await sleep(500);
    try {
      const r = await fetch(`${BASE}/sante`);
      pret = r.ok;
    } catch {
      pret = false;
    }
  }
  check("API démarrée (/sante)", pret);
  if (pret) {
    const tokAdmin = await login("admin-a@test.ci");
    const tokTres = await login("tresorier-a@test.ci");
    const tokMembre = await login("membre1@test.ci");
    check("connexion admin", tokAdmin != null);
    check("connexion trésorier", tokTres != null);

    async function exportSycebnl(etat, annee, jeton) {
      const r = await fetch(
        `${BASE}/exports/sycebnl?etat=${etat}&annee=${annee}`,
        { headers: jeton ? { authorization: `Bearer ${jeton}` } : {} },
      );
      const buf = Buffer.from(await r.arrayBuffer());
      return { statut: r.status, buf };
    }

    const sansJeton = await exportSycebnl("bilan", 2026, null);
    check("sans jeton = 401", sansJeton.statut === 401);

    const membre = await exportSycebnl("bilan", 2026, tokMembre);
    check("membre = 403", membre.statut === 403);

    const mauvaisEtat = await exportSycebnl("tafere", 2026, tokAdmin);
    check("état inconnu = 400", mauvaisEtat.statut === 400);

    for (const etat of ["bilan", "compte_resultat", "flux", "notes"]) {
      const res = await exportSycebnl(etat, 2026, tokTres);
      check(
        `trésorier, ${etat} = 200 et PDF`,
        res.statut === 200 &&
          res.buf.subarray(0, 5).toString("latin1") === "%PDF-",
        `statut ${res.statut}`,
      );
      const texte = res.buf.toString("latin1");
      if (etat === "compte_resultat") {
        check(
          "compte de résultat : 12 000 000 et 3 000 000",
          texte.includes("12 000 000") && texte.includes("3 000 000"),
        );
        check(
          "compte de résultat : résultat 9 000 000",
          texte.includes("9 000 000"),
        );
      }
      if (etat === "bilan") {
        check(
          "bilan : total 12 000 000 (ouverture 3 000 000 + résultat 9 000 000)",
          texte.includes("12 000 000"),
        );
      }
      if (etat === "flux") {
        check(
          "flux : ouverture 3 000 000, clôture 12 000 000",
          texte.includes("3 000 000") && texte.includes("12 000 000"),
        );
      }
    }
  }
} finally {
  api.kill();
  await new Promise((r) => api.on("exit", r));
}

await db.end();
console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko === 0 ? 0 : 1);
