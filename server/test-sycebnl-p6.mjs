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
// Chemins relatifs au fichier, pas au répertoire de lancement (T13) :
// le script démarre l'API avec cwd 'server', donc '../db/...' ne peut
// pas être relatif au répertoire courant.
await db.query(
    readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8'));
for (const f of readdirSync(new URL('../db/migrations', import.meta.url))
    .sort()) {
  if (f.endsWith('.sql'))
    await db.query(readFileSync(
        new URL(`../db/migrations/${f}`, import.meta.url), 'utf8'));
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
// Exercice 2026 EXEMPLE : 12 000 000 de produits, 3 000 000 de charges
// du registre, plus 500 000 de Budget et caisse (payée) : charges
// 3 500 000, résultat 8 500 000. Une dépense refusée de 999 999 ne
// compte pas. Exercice 2025 : 5 000 000 de produits, 2 000 000 de
// charges du registre, plus 1 000 000 de Budget et caisse (payée) :
// ouverture 2 000 000, clôture 10 500 000.
await contrib(churchA, m1, "dime", 8000000, "confirme", "2026-01-10");
await contrib(churchA, m1, "offrande", 3000000, "confirme", "2026-02-10");
await contrib(churchA, m1, "don", 1000000, "confirme", "2026-03-10");
await contrib(churchA, m1, "depense", 3000000, "confirme", "2026-04-10");
await contrib(churchA, m1, "don", 999999, "en_attente", "2026-05-10");
await contrib(churchA, m1, "don", 999999, "annule", "2026-05-11");
await contrib(churchA, m1, "don", 5000000, "confirme", "2025-06-10");
await contrib(churchA, m1, "depense", 2000000, "confirme", "2025-09-10");
async function depense(church, montant, statut, date) {
  await q(
    `INSERT INTO depenses (church_id,montant_fcfa,motif,statut,date_depense) VALUES ($1,$2,'Dépense de test',$3,$4)`,
    [church, montant, statut, date],
  );
}
await depense(churchA, 500000, "payee", "2026-06-15");
await depense(churchA, 999999, "refusee", "2026-07-01");
await depense(churchA, 1000000, "payee", "2025-10-05");

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
          "compte de résultat : 12 000 000 de produits, 3 500 000 de charges (registre + Budget et caisse, refusée exclue)",
          texte.includes("12 000 000") && texte.includes("3 500 000"),
        );
        check(
          "compte de résultat : résultat 8 500 000",
          texte.includes("8 500 000"),
        );
      }
      if (etat === "bilan") {
        check(
          "bilan : total 10 500 000 (ouverture 2 000 000 + résultat 8 500 000)",
          texte.includes("10 500 000"),
        );
      }
      if (etat === "flux") {
        check(
          "flux : ouverture 2 000 000, clôture 10 500 000",
          texte.includes("2 000 000") && texte.includes("10 500 000"),
        );
      }
    }

    // Données JSON pour l'écran : mêmes sommes que le PDF, droits
    // admin et trésorier. Le trésorier n'a pas accès à
    // GET /finances/rapport (admin et responsable de culte) : c'est
    // l'écart que cette route ferme.
    async function donneesSycebnl(annee, jeton) {
      const r = await fetch(`${BASE}/exports/sycebnl/donnees?annee=${annee}`, {
        headers: jeton ? { authorization: `Bearer ${jeton}` } : {},
      });
      return { statut: r.status, corps: await r.json().catch(() => null) };
    }
    const donneesSansJeton = await donneesSycebnl(2026, null);
    check("données sans jeton = 401", donneesSansJeton.statut === 401);
    const donneesMembre = await donneesSycebnl(2026, tokMembre);
    check("données membre = 403", donneesMembre.statut === 403);
    const donneesTres = await donneesSycebnl(2026, tokTres);
    check(
      "données trésorier = 200, charges 3 500 000, ouverture 2 000 000, clôture 10 500 000",
      donneesTres.statut === 200 &&
        donneesTres.corps?.charges === 3500000 &&
        donneesTres.corps?.produits === 12000000 &&
        donneesTres.corps?.ouverture === 2000000 &&
        donneesTres.corps?.cloture === 10500000,
      `statut ${donneesTres.statut} ${JSON.stringify(donneesTres.corps)}`,
    );
    const rapportTres = await fetch(`${BASE}/finances/rapport?annee=2026`, {
      headers: { authorization: `Bearer ${tokTres}` },
    });
    check(
      "GET /finances/rapport trésorier = 403 (écart connu, route fermée)",
      rapportTres.status === 403,
      `statut ${rapportTres.status}`,
    );
  }
} finally {
  api.kill();
  await new Promise((r) => api.on("exit", r));
}

await db.end();
console.log(`\n${ok} OK, ${ko} KO`);
process.exit(ko === 0 ? 0 : 1);
