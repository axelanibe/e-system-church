// Test d'intégration « Chaîne de prière » (lot 3d) : migration 042,
// routes GET /chaine-priere (24 créneaux, compteur), POST
// /chaine-priere (prendre : un membre par créneau, un créneau par
// membre et par jour) et DELETE /chaine-priere/:heure (libérer ses
// propres créneaux seulement), isolation par église, jours passés en
// lecture seule, jour courant dans le fuseau horaire de l'église.
// Même forme que server/test-activites.mjs : base fraîche créée puis
// vidée par le test lui-même, application du schéma puis des
// migrations avec le vrai moteur de migration, démarrage de l'API,
// appels HTTP.
//
// Usage : `node server/test-chaine-priere.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4115).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_chaine_priere.
// Base locale : PostgreSQL est nécessaire.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);

const PORT = Number(process.env.PORT ?? 4115);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_chaine_priere';
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0).
const JWT_SECRET = 'test-jwt-secret-pour-t11-seulement-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const MIGRATION_042 = readFileSync(
  new URL('../db/migrations/042_chaine_priere.sql', import.meta.url),
  'utf8',
);

let echecs = 0;
function verifier(nom, condition, detail = '') {
  if (condition) {
    console.log(`  OK ${nom}`);
  } else {
    echecs += 1;
    console.log(`  ECHEC ${nom} ${detail}`);
  }
}

async function appel(methode, chemin, jeton, corps) {
  const reponse = await fetch(`${BASE}${chemin}`, {
    method: methode,
    headers: {
      'content-type': 'application/json',
      ...(jeton ? { authorization: `Bearer ${jeton}` } : {}),
    },
    body: corps === undefined ? undefined : JSON.stringify(corps),
  });
  const texte = await reponse.text();
  let json = null;
  try {
    json = JSON.parse(texte);
  } catch {
    json = null;
  }
  return { statut: reponse.status, json, texte };
}

/** Jour AAAA-MM-JJ décalé de `jours` jours depuis `iso`. */
function decaler(iso, jours) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + jours);
  return d.toISOString().slice(0, 10);
}

async function main() {
  // Base fraîche (celle de DATABASE_URL, recréée par le test lui-même).
  const nomBase = `"${DB_NAME.replace(/"/g, '""')}"`;
  const admin = new Client({
    connectionString: 'postgres://postgres:postgres@127.0.0.1:5432/postgres',
  });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${nomBase}`);
  await admin.query(`CREATE DATABASE ${nomBase}`);
  await admin.end();

  // Schéma + migrations avec le vrai moteur (dont la 042).
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, JWT_SECRET, PAYMENT_SECRETS_KEY },
  });

  const direct = new Client({ connectionString: DATABASE_URL });
  await direct.connect();

  // --- 1. Migration 042 : table et enregistrement -------------------------
  const colonnes = await direct.query(
    `SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'creneaux_priere'`,
  );
  verifier(
    'migration 042 : table creneaux_priere, 6 colonnes',
    colonnes.rowCount === 6,
    `reçu ${colonnes.rowCount} : ${colonnes.rows.map((r) => r.column_name).join(',')}`,
  );
  const migration = await direct.query(
    `SELECT 1 FROM schema_migrations WHERE name = '042_chaine_priere'`,
  );
  verifier('migration 042 enregistrée dans schema_migrations', migration.rowCount === 1);
  const contraintes = await direct.query(
    `SELECT constraint_name FROM information_schema.table_constraints
      WHERE table_name = 'creneaux_priere' AND constraint_type = 'UNIQUE'`,
  );
  const nomsContraintes = contraintes.rows.map((r) => r.constraint_name).sort();
  verifier(
    'migration 042 : deux unicités nommées (créneau, membre-jour)',
    JSON.stringify(nomsContraintes) ===
      JSON.stringify(['uq_creneaux_priere_creneau', 'uq_creneaux_priere_membre_jour']),
    `reçu ${nomsContraintes.join(',')}`,
  );
  // Rejeu : idempotence, rien ne change.
  const avant = JSON.stringify(
    (await direct.query(`SELECT * FROM creneaux_priere ORDER BY id`)).rows,
  );
  await direct.query(MIGRATION_042);
  const apres = JSON.stringify(
    (await direct.query(`SELECT * FROM creneaux_priere ORDER BY id`)).rows,
  );
  verifier('migration 042 rejouée : données inchangées', avant === apres);

  // --- 2. Données sources : mère + annexe ---------------------------------
  const eglise = async (code, nom, parent) =>
    (
      await direct.query(
        `INSERT INTO churches (code, code_fidele, name, parent_church_id, city, country,
             address, phone, email, status, devise, fuseau_horaire)
         VALUES ($1, $2, $3, $4, 'Abidjan', 'Côte d’Ivoire',
           '12 rue de la Mère', '+2250102030405', 'mere42@example.com', 'active', 'FCFA', 'Africa/Abidjan')
         RETURNING id`,
        [code, `${code}-F`, nom, parent],
      )
    ).rows[0].id;
  const mereId = await eglise('ESC-MERE42', 'Église Mère Chaîne', null);
  const annexeId = await eglise('ESC-ANNX42', 'Annexe Chaîne', mereId);

  // --- 3. Fiches membres et comptes ---------------------------------------
  const membre = async (churchId, matricule, nom) =>
    (
      await direct.query(
        `INSERT INTO members (church_id, matricule, full_name)
         VALUES ($1, $2, $3) RETURNING id`,
        [churchId, matricule, nom],
      )
    ).rows[0].id;
  const membreAdmin = await membre(mereId, 'M-AD-010190-01', 'Awa Koné EXEMPLE');
  const membre1 = await membre(mereId, 'M-KO-020290-01', 'Kofi Mensah EXEMPLE');
  const membre2 = await membre(mereId, 'M-YA-030390-01', 'Yao N’Guessan EXEMPLE');
  const membreAnnexe = await membre(annexeId, 'M-AN-040490-01', 'Aminata Diallo EXEMPLE');

  const hash = await argon2.hash('MotDePasse123!');
  const creerCompte = async (email, churchId, role, memberId) => {
    const u = (
      await direct.query(
        `INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id`,
        [email, hash, email],
      )
    ).rows[0].id;
    if (memberId) {
      await direct.query(`UPDATE users SET member_id = $2 WHERE id = $1`, [u, memberId]);
    }
    await direct.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
      [u, churchId, role],
    );
    return u;
  };
  await creerCompte('admin-mere42@example.com', mereId, 'admin_eglise', membreAdmin);
  await creerCompte('membre1-mere42@example.com', mereId, 'membre', membre1);
  await creerCompte('membre2-mere42@example.com', mereId, 'membre', membre2);
  await creerCompte('membre-annexe42@example.com', annexeId, 'membre', membreAnnexe);
  await creerCompte('sans-fiche42@example.com', mereId, 'membre', null);

  // Démarrage de l'API.
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, PORT: String(PORT), JWT_SECRET, PAYMENT_SECRETS_KEY },
    stdio: 'pipe',
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
    verifier('API démarrée (/sante)', pret);
    if (!pret) return;

    const login = async (email) => {
      const r = await appel('POST', '/auth/login', null, { email, password: 'MotDePasse123!' });
      if (r.statut !== 200) throw new Error(`login ${email}: ${r.texte}`);
      return r.json.token;
    };
    const tokAdmin = await login('admin-mere42@example.com');
    const tokMembre1 = await login('membre1-mere42@example.com');
    const tokMembre2 = await login('membre2-mere42@example.com');
    const tokAnnexe = await login('membre-annexe42@example.com');
    const tokSansFiche = await login('sans-fiche42@example.com');

    // --- 4. Lecture : chaîne vide, 24 créneaux, compteur à 0 --------------
    const sansJeton = await appel('GET', '/chaine-priere', null);
    verifier('GET /chaine-priere sans jeton : 401', sansJeton.statut === 401, sansJeton.texte);
    const vide = await appel('GET', '/chaine-priere', tokMembre1);
    const aujourdHui = vide.json?.aujourd_hui;
    verifier(
      'GET /chaine-priere : 200, 24 créneaux, 0 couverte, jour = aujourd’hui',
      vide.statut === 200 &&
        Array.isArray(vide.json?.creneaux) &&
        vide.json.creneaux.length === 24 &&
        vide.json.heures_couvertes === 0 &&
        vide.json.heures_totales === 24 &&
        vide.json.jour === aujourdHui &&
        vide.json.mon_member_id === membre1 &&
        vide.json.creneaux.every((c) => c.member_id === null && c.prenom === ''),
      vide.texte.slice(0, 300),
    );
    const jourInvalide = await appel('GET', '/chaine-priere?jour=2026-02-30', tokMembre1);
    verifier('GET /chaine-priere jour inexistant : 400', jourInvalide.statut === 400, jourInvalide.texte);
    const jourMalForme = await appel('GET', '/chaine-priere?jour=pasunjour', tokMembre1);
    verifier('GET /chaine-priere jour mal formé : 400', jourMalForme.statut === 400, jourMalForme.texte);

    // --- 5. Prise : un membre par créneau, un créneau par membre -----------
    const prise = await appel('POST', '/chaine-priere', tokMembre1, { heure: 8 });
    verifier(
      'POST /chaine-priere membre, 8 h : 201',
      prise.statut === 201 &&
        prise.json?.heure === 8 &&
        prise.json?.jour === aujourdHui &&
        prise.json?.member_id === membre1,
      prise.texte.slice(0, 300),
    );
    const apresPrise = await appel('GET', '/chaine-priere', tokMembre1);
    const creneau8 = apresPrise.json?.creneaux?.[8];
    verifier(
      'GET /chaine-priere après prise : 1 couverte, 8 h = Kofi (prénom seul)',
      apresPrise.statut === 200 &&
        apresPrise.json?.heures_couvertes === 1 &&
        creneau8?.member_id === membre1 &&
        creneau8?.prenom === 'Kofi',
      apresPrise.texte.slice(0, 300),
    );
    const dejaPris = await appel('POST', '/chaine-priere', tokMembre2, { heure: 8 });
    verifier(
      'POST /chaine-priere même créneau, autre membre : 409',
      dejaPris.statut === 409,
      dejaPris.texte.slice(0, 200),
    );
    const deuxieme = await appel('POST', '/chaine-priere', tokMembre1, { heure: 9 });
    verifier(
      'POST /chaine-priere deuxième créneau le même jour : 409',
      deuxieme.statut === 409,
      deuxieme.texte.slice(0, 200),
    );
    const heure24 = await appel('POST', '/chaine-priere', tokMembre2, { heure: 24 });
    verifier('POST /chaine-priere heure 24 : 400', heure24.statut === 400, heure24.texte);
    const heureTexte = await appel('POST', '/chaine-priere', tokMembre2, { heure: 'abc' });
    verifier('POST /chaine-priere heure texte : 400', heureTexte.statut === 400, heureTexte.texte);
    const jourPasse = await appel('POST', '/chaine-priere', tokMembre2, {
      heure: 10,
      jour: decaler(aujourdHui, -1),
    });
    verifier('POST /chaine-priere jour passé : 400', jourPasse.statut === 400, jourPasse.texte);
    const jourFutur = decaler(aujourdHui, 7);
    const priseFuture = await appel('POST', '/chaine-priere', tokMembre2, {
      heure: 10,
      jour: jourFutur,
    });
    verifier(
      'POST /chaine-priere jour à venir : 201',
      priseFuture.statut === 201 && priseFuture.json?.jour === jourFutur,
      priseFuture.texte.slice(0, 200),
    );
    const lectureFuture = await appel('GET', `/chaine-priere?jour=${jourFutur}`, tokMembre1);
    verifier(
      'GET /chaine-priere jour à venir : 1 couverte, créneau de l’autre membre visible',
      lectureFuture.statut === 200 &&
        lectureFuture.json?.heures_couvertes === 1 &&
        lectureFuture.json?.creneaux?.[10]?.prenom === 'Yao',
      lectureFuture.texte.slice(0, 300),
    );
    const sansFiche = await appel('POST', '/chaine-priere', tokSansFiche, { heure: 11 });
    verifier(
      'POST /chaine-priere sans fiche membre : 403',
      sansFiche.statut === 403,
      sansFiche.texte.slice(0, 200),
    );

    // --- 6. Libération : seulement ses propres créneaux --------------------
    const libereAutre = await appel('DELETE', '/chaine-priere/8', tokMembre2);
    verifier(
      'DELETE /chaine-priere/8 par un autre membre : 404',
      libereAutre.statut === 404,
      libereAutre.texte.slice(0, 200),
    );
    const libere = await appel('DELETE', '/chaine-priere/8', tokMembre1);
    verifier(
      'DELETE /chaine-priere/8 par le membre : 200',
      libere.statut === 200 && libere.json?.ok === true,
      libere.texte.slice(0, 200),
    );
    const apresLibere = await appel('GET', '/chaine-priere', tokMembre1);
    verifier(
      'GET /chaine-priere après libération : 0 couverte',
      apresLibere.statut === 200 && apresLibere.json?.heures_couvertes === 0,
      apresLibere.texte.slice(0, 200),
    );
    const libereEncore = await appel('DELETE', '/chaine-priere/8', tokMembre1);
    verifier('DELETE /chaine-priere/8 déjà libéré : 404', libereEncore.statut === 404, libereEncore.texte);
    const liberePasse = await appel(
      'DELETE',
      `/chaine-priere/10?jour=${decaler(aujourdHui, -1)}`,
      tokMembre2,
    );
    verifier('DELETE /chaine-priere jour passé : 400', liberePasse.statut === 400, liberePasse.texte);
    const libereHeure = await appel('DELETE', '/chaine-priere/25', tokMembre1);
    verifier('DELETE /chaine-priere/25 : 400', libereHeure.statut === 400, libereHeure.texte);

    // --- 7. Isolation par église + admin ------------------------------------
    const vueAnnexe = await appel('GET', '/chaine-priere', tokAnnexe);
    verifier(
      'GET /chaine-priere membre annexe : 0 couverte (isolation)',
      vueAnnexe.statut === 200 && vueAnnexe.json?.heures_couvertes === 0,
      vueAnnexe.texte.slice(0, 200),
    );
    const priseAnnexe = await appel('POST', '/chaine-priere', tokAnnexe, { heure: 8 });
    verifier(
      'POST /chaine-priere annexe, même heure 8 h : 201 (chaîne propre à chaque église)',
      priseAnnexe.statut === 201,
      priseAnnexe.texte.slice(0, 200),
    );
    const vueMereApres = await appel('GET', '/chaine-priere', tokMembre1);
    verifier(
      'GET /chaine-priere mère après prise annexe : toujours 0 couverte',
      vueMereApres.statut === 200 && vueMereApres.json?.heures_couvertes === 0,
      vueMereApres.texte.slice(0, 200),
    );
    const priseAdmin = await appel('POST', '/chaine-priere', tokAdmin, { heure: 20 });
    verifier(
      'POST /chaine-priere admin avec fiche membre : 201',
      priseAdmin.statut === 201 && priseAdmin.json?.member_id === membreAdmin,
      priseAdmin.texte.slice(0, 200),
    );
  } finally {
    api.kill();
    await once(api, 'exit').catch(() => {});
  }
  await direct.end();
  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ÉCHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
