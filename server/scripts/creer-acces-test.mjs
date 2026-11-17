// Script ponctuel : crée les trois comptes temporaires de test d'e-System Church.
// Usage (une seule fois, depuis Render) :
//   node scripts/creer-acces-test.mjs '<hash_admin_mere>' '<hash_admin_annexe>' '<hash_membre>'
// Les trois hash argon2id sont passés en arguments, dans cet ordre :
//   1. admin de l'église mère TEST (ESC-4240)
//   2. admin de l'annexe de test (créée sous ESC-4240)
//   3. membre simple de l'église mère TEST (ESC-4240)
// Les hash ne sont jamais écrits dans ce fichier ni dans le dépôt.
// Variables : DATABASE_URL (déjà définie sur Render).
// Idempotent : relancer le script ne crée pas de doublon.
// Ne touche qu'à l'église TEST (ESC-4240) et à l'annexe de test créée ici.
// Après les tests, supprimer les trois comptes et l'annexe (PR de nettoyage
// retirera aussi ce script).

import { randomInt } from "node:crypto";
import pg from "pg";

const { Client } = pg;

const CODE_EGLISE_TEST = "ESC-4240";
const NOM_ANNEXE_TEST = "Annexe Test";

// Naissance commune, cohérente avec les matricules (...010190 = 01/01/1990).
const BIRTH_DATE = "1990-01-01";
const SEXE = "M";

const COMPTES = [
  {
    cle: "admin_mere",
    email: "test-admin-mere@test.local",
    nom: "Test Admin Mère",
    matricule: "M-TA-010190-01",
    role: "admin_eglise",
    eglise: "mere",
  },
  {
    cle: "admin_annexe",
    email: "test-admin-annexe@test.local",
    nom: "Test Admin Annexe",
    matricule: "M-TA-010190-02",
    role: "admin_eglise",
    eglise: "annexe",
  },
  {
    cle: "membre",
    email: "test-membre@test.local",
    nom: "Test Membre",
    matricule: "M-TM-010190-01",
    role: "membre",
    eglise: "mere",
  },
];

// Postes de dépense prévisibles, miroir de seedPostesPrevisibles
// (server/src/postes_previsibles.ts) : mêmes huit postes que POST /eglises
// crée pour une nouvelle sous-église.
const POSTES_PREVISIBLES = [
  { nom: "Électricité", codeCategorie: "02", recurrente: true },
  { nom: "Eau", codeCategorie: "02", recurrente: true },
  { nom: "Transports", codeCategorie: "07", recurrente: true },
  { nom: "Cas sociaux", codeCategorie: "08", recurrente: false },
  { nom: "Location de sono", codeCategorie: "03", recurrente: false },
  { nom: "Achat d'équipement", codeCategorie: "03", recurrente: false },
  { nom: "Maintenance", codeCategorie: "03", recurrente: true },
  { nom: "Location d'équipement", codeCategorie: "03", recurrente: false },
];

const [hashMere, hashAnnexe, hashMembre] = process.argv.slice(2);
const hashes = { admin_mere: hashMere, admin_annexe: hashAnnexe, membre: hashMembre };
for (const [cle, hash] of Object.entries(hashes)) {
  if (!hash || !hash.startsWith("$argon2id$")) {
    console.error(
      "Usage : node scripts/creer-acces-test.mjs '<hash_admin_mere>' '<hash_admin_annexe>' '<hash_membre>'",
    );
    console.error(`Hash manquant ou invalide pour ${cle} (doit commencer par $argon2id$).`);
    process.exit(2);
  }
}

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error("DATABASE_URL manquante");
  process.exit(2);
}

const client = new Client({ connectionString, ssl: { rejectUnauthorized: false } });
await client.connect();

try {
  await client.query("BEGIN");

  // 1. L'église TEST doit exister, sinon on ne crée rien.
  const test = await client.query(`SELECT id, code, name, status FROM churches WHERE code = $1`, [
    CODE_EGLISE_TEST,
  ]);
  if (test.rowCount === 0) {
    throw new Error(`Église TEST ${CODE_EGLISE_TEST} introuvable, abandon.`);
  }
  const egliseTestId = test.rows[0].id;
  console.log("église TEST :", JSON.stringify(test.rows[0]));

  // 2. Annexe de test sous ESC-4240 : réutilisée si elle existe déjà
  // (même parent, même nom), sinon créée comme POST /eglises le fait :
  // codes ESC-XXXX et ESC-F-XXXX à 4 chiffres, suffixes uniques entre
  // les deux colonnes, statut active, postes prévisibles semés.
  let annexe = await client.query(
    `SELECT id, code, code_fidele, name, parent_church_id, status
       FROM churches WHERE parent_church_id = $1 AND name = $2 LIMIT 1`,
    [egliseTestId, NOM_ANNEXE_TEST],
  );
  if (annexe.rowCount === 0) {
    const suffixeLibre = async () => {
      for (let attempt = 0; attempt < 50; attempt++) {
        const suffixe = String(randomInt(0, 10000)).padStart(4, "0");
        const clash = await client.query(
          `SELECT 1 FROM churches WHERE right(code, 4) = $1 OR right(code_fidele, 4) = $1`,
          [suffixe],
        );
        if (clash.rowCount === 0) return suffixe;
      }
      throw new Error("Impossible de générer un code d'annexe unique.");
    };
    const suffixeCode = await suffixeLibre();
    let suffixeFidele = await suffixeLibre();
    while (suffixeFidele === suffixeCode) suffixeFidele = await suffixeLibre();
    const code = `ESC-${suffixeCode}`;
    const codeFidele = `ESC-F-${suffixeFidele}`;
    annexe = await client.query(
      `INSERT INTO churches (code, code_fidele, name, parent_church_id, status)
       VALUES ($1, $2, $3, $4, 'active')
       RETURNING id, code, code_fidele, name, parent_church_id, status`,
      [code, codeFidele, NOM_ANNEXE_TEST, egliseTestId],
    );
    for (const poste of POSTES_PREVISIBLES) {
      await client.query(
        `INSERT INTO postes_budgetaires (church_id, nom, categorie, categorie_id, est_recurrente)
         SELECT $1, $2, 'depense', id, $3 FROM categories_depenses WHERE code = $4
         ON CONFLICT (church_id, nom) DO NOTHING`,
        [annexe.rows[0].id, poste.nom, poste.recurrente, poste.codeCategorie],
      );
    }
  }
  const annexeId = annexe.rows[0].id;
  console.log("annexe de test :", JSON.stringify(annexe.rows[0]));

  const eglises = { mere: egliseTestId, annexe: annexeId };

  // 3. Les trois comptes : utilisateur + fiche membre + rôle.
  for (const compte of COMPTES) {
    const egliseId = eglises[compte.eglise];
    const hash = hashes[compte.cle];

    const u = await client.query(
      `INSERT INTO users (email, password_hash, full_name, failed_logins, locked_until)
       VALUES ($1, $2, $3, 0, NULL)
       ON CONFLICT (email) DO UPDATE SET
         password_hash = EXCLUDED.password_hash,
         full_name = EXCLUDED.full_name,
         failed_logins = 0,
         locked_until = NULL,
         token_version = users.token_version + 1
       RETURNING id, email`,
      [compte.email, hash, compte.nom],
    );
    const userId = u.rows[0].id;

    // Garde : un matricule est unique dans tout le système côté applicatif
    // (vérification globale dans POST /membres). Refuser de prendre le
    // matricule d'un membre d'une autre église.
    const clash = await client.query(
      `SELECT id, church_id, email FROM members WHERE matricule = $1`,
      [compte.matricule],
    );
    // Toutes les lignes comptent : la requête peut en rendre plusieurs
    // (un même matricule dans plusieurs églises), il faut les vérifier
    // une par une, pas seulement la première.
    for (const existant of clash.rows) {
      if (existant.church_id !== egliseId || existant.email !== compte.email) {
        throw new Error(
          `Matricule ${compte.matricule} déjà utilisé par ${existant.email} dans une autre église, abandon.`,
        );
      }
    }

    const m = await client.query(
      `INSERT INTO members (church_id, user_id, matricule, full_name, email, birth_date, sexe, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'actif')
       ON CONFLICT (church_id, matricule) DO UPDATE SET
         user_id = EXCLUDED.user_id,
         full_name = EXCLUDED.full_name,
         email = EXCLUDED.email,
         birth_date = EXCLUDED.birth_date,
         sexe = EXCLUDED.sexe,
         status = 'actif'
       RETURNING id, matricule`,
      [egliseId, userId, compte.matricule, compte.nom, compte.email, BIRTH_DATE, SEXE],
    );
    const memberId = m.rows[0].id;

    // Garde : ne jamais détacher un compte d'une autre fiche membre.
    const lien = await client.query(`SELECT member_id FROM users WHERE id = $1`, [userId]);
    if (lien.rows[0].member_id && lien.rows[0].member_id !== memberId) {
      throw new Error(`Compte ${compte.email} déjà lié à une autre fiche membre, abandon.`);
    }
    await client.query(`UPDATE users SET member_id = $1 WHERE id = $2`, [memberId, userId]);

    const r = await client.query(
      `INSERT INTO church_users (user_id, church_id, role)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, church_id) DO UPDATE SET role = EXCLUDED.role
       RETURNING user_id, church_id, role`,
      [userId, egliseId, compte.role],
    );
    console.log(`${compte.cle} :`, JSON.stringify({ utilisateur: u.rows[0], membre: m.rows[0], rôle: r.rows[0] }));
  }

  await client.query("COMMIT");
} catch (e) {
  await client.query("ROLLBACK").catch(() => undefined);
  console.error("Échec :", e.message);
  await client.end();
  process.exit(1);
}

// 4. Vérification finale, un compte par ligne.
const verif = await client.query(
  `SELECT u.email, u.full_name, cu.role, c.code AS code_eglise, c.name AS eglise,
          mem.matricule
     FROM users u
     JOIN church_users cu ON cu.user_id = u.id
     JOIN churches c ON c.id = cu.church_id
     LEFT JOIN members mem ON mem.id = u.member_id
    WHERE u.email IN ($1, $2, $3)
    ORDER BY u.email`,
  [COMPTES[0].email, COMPTES[1].email, COMPTES[2].email],
);
console.log("vérification :", JSON.stringify(verif.rows, null, 2));

await client.end();
console.log("comptes de test créés");
