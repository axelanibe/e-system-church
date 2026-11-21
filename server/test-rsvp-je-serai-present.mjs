// Test d'intégration « Je serai présent » (lot 3b, migration 040) :
// confirmation de présence du fidèle au culte et à l'activité,
// annulation + reprise, vue admin des confirmations par culte et par
// activité, isolation par église.
// Même forme que server/test-activites.mjs : base fraîche créée puis
// vidée par le test lui-même, application du schéma puis des migrations
// avec le vrai moteur de migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-rsvp-je-serai-present.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4115).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_rsvp_je_serai_present.
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
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_rsvp_je_serai_present';
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0).
const JWT_SECRET = 'test-secret-rsvp-je-serai-present-2026';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const MIGRATION_040 = readFileSync(
  new URL('../db/migrations/040_rsvp_activites.sql', import.meta.url),
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

  // Schéma + migrations avec le vrai moteur (dont la 040).
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, JWT_SECRET, PAYMENT_SECRETS_KEY },
  });

  const direct = new Client({ connectionString: DATABASE_URL });
  await direct.connect();

  // --- 1. Migration 040 : table et enregistrement -------------------------
  const colonnes = await direct.query(
    `SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'activite_rsvp'`,
  );
  verifier(
    'migration 040 : table activite_rsvp, 5 colonnes',
    colonnes.rowCount === 5,
    `reçu ${colonnes.rowCount} : ${colonnes.rows.map((r) => r.column_name).join(',')}`,
  );
  const migration = await direct.query(
    `SELECT 1 FROM schema_migrations WHERE name = '040_rsvp_activites'`,
  );
  verifier('migration 040 enregistrée dans schema_migrations', migration.rowCount === 1);
  // Rejeu : idempotence, rien ne change.
  const avant = JSON.stringify(
    (await direct.query(`SELECT * FROM activite_rsvp ORDER BY id`)).rows,
  );
  await direct.query(MIGRATION_040);
  const apres = JSON.stringify(
    (await direct.query(`SELECT * FROM activite_rsvp ORDER BY id`)).rows,
  );
  verifier('migration 040 rejouée : données inchangées', avant === apres);

  // --- 2. Données sources : mère + annexe ---------------------------------
  const eglise = async (code, nom, parent) =>
    (
      await direct.query(
        `INSERT INTO churches (code, code_fidele, name, parent_church_id, city, country,
             address, phone, email, status, devise, fuseau_horaire)
         VALUES ($1, $2, $3, $4, 'Abidjan', 'Côte d’Ivoire',
           '12 rue de la Mère', '+2250102030405', 'mere40@example.com', 'active', 'FCFA', 'Africa/Abidjan')
         RETURNING id`,
        [code, `${code}-F`, nom, parent],
      )
    ).rows[0].id;
  const mereId = await eglise('ESC-MERE40', 'Église Mère RSVP', null);
  const annexeId = await eglise('ESC-ANNX40', 'Annexe RSVP', mereId);

  // --- 3. Comptes : admin mère, responsable mère, membres liés, membre
  //      sans fiche, membre annexe ----------------------------------------
  const hash = await argon2.hash('MotDePasse123!');
  const creerCompte = async (email, churchId, role, memberId = null) => {
    const u = (
      await direct.query(
        `INSERT INTO users (email, password_hash, full_name, member_id) VALUES ($1, $2, $3, $4) RETURNING id`,
        [email, hash, email, memberId],
      )
    ).rows[0].id;
    await direct.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
      [u, churchId, role],
    );
    return u;
  };
  const creerMembre = async (churchId, matricule, nom, email) =>
    (
      await direct.query(
        `INSERT INTO members (church_id, matricule, full_name, phone, email, status)
         VALUES ($1, $2, $3, '+2250102030405', $4, 'actif') RETURNING id`,
        [churchId, matricule, nom, email],
      )
    ).rows[0].id;
  const membreA = await creerMembre(mereId, 'M-RSVP-A01', 'Membre RSVP A', 'membre-a40@example.com');
  const membreB = await creerMembre(mereId, 'M-RSVP-B01', 'Membre RSVP B', 'membre-b40@example.com');
  const membreAnnexe = await creerMembre(annexeId, 'M-RSVP-X01', 'Membre RSVP Annexe', 'membre-x40@example.com');
  await creerCompte('admin-mere40@example.com', mereId, 'admin_eglise');
  await creerCompte('admin-annexe40@example.com', annexeId, 'admin_eglise');
  await creerCompte('responsable-mere40@example.com', mereId, 'responsable_culte');
  await creerCompte('membre-a40@example.com', mereId, 'membre', membreA);
  await creerCompte('membre-b40@example.com', mereId, 'membre', membreB);
  await creerCompte('membre-x40@example.com', annexeId, 'membre', membreAnnexe);
  await creerCompte('sans-membre40@example.com', mereId, 'membre');

  // --- 4. Cultes et activités (SQL direct, dates fixes à venir) -----------
  const culte = async (churchId, titre, dateHeure) =>
    (
      await direct.query(
        `INSERT INTO cultes (church_id, titre, date_heure, lieu)
         VALUES ($1, $2, $3, 'Temple EXEMPLE') RETURNING id`,
        [churchId, titre, dateHeure],
      )
    ).rows[0].id;
  const activite = async (churchId, titre, dateHeure, statut) =>
    (
      await direct.query(
        `INSERT INTO activites (church_id, titre, date_heure, lieu, statut)
         VALUES ($1, $2, $3, 'Parc EXEMPLE', $4) RETURNING id`,
        [churchId, titre, dateHeure, statut],
      )
    ).rows[0].id;
  const culteId = await culte(mereId, 'Culte RSVP EXEMPLE', '2027-01-03 09:00');
  const cultePasseId = await culte(mereId, 'Culte passé EXEMPLE', '2020-01-05 09:00');
  const activiteId = await activite(mereId, 'Sortie RSVP EXEMPLE', '2027-01-16 09:00', 'publié');
  const activiteBrouillonId = await activite(mereId, 'Sortie brouillon EXEMPLE', '2027-01-23 09:00', 'brouillon');
  const activitePasseeId = await activite(mereId, 'Sortie passée EXEMPLE', '2020-01-01 09:00', 'publié');

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
    const tokAdmin = await login('admin-mere40@example.com');
    const tokAnnexe = await login('admin-annexe40@example.com');
    const tokResponsable = await login('responsable-mere40@example.com');
    const tokA = await login('membre-a40@example.com');
    const tokB = await login('membre-b40@example.com');
    const tokX = await login('membre-x40@example.com');
    const tokSansMembre = await login('sans-membre40@example.com');

    const seraiPresentCulte = async (jeton) => {
      const r = await appel('GET', '/moi/cultes', jeton);
      return r.json?.cultes?.find((c) => c.id === culteId)?.serai_present;
    };
    const seraiPresentActivite = async (jeton) => {
      const r = await appel('GET', '/moi/activites', jeton);
      return r.json?.activites?.find((a) => a.id === activiteId)?.serai_present;
    };

    // --- 5. Culte : confirmation, idempotence, annulation, reprise --------
    const confirmeA = await appel('POST', `/moi/cultes/${culteId}/present`, tokA);
    verifier(
      'POST /moi/cultes/:id/present A : 200, present vrai',
      confirmeA.statut === 200 && confirmeA.json?.present === true,
      confirmeA.texte.slice(0, 200),
    );
    const confirmeA2 = await appel('POST', `/moi/cultes/${culteId}/present`, tokA);
    verifier(
      'POST /moi/cultes/:id/present A (doublon) : 200, idempotent',
      confirmeA2.statut === 200 && confirmeA2.json?.present === true,
      confirmeA2.texte.slice(0, 200),
    );
    verifier('GET /moi/cultes A : serai_present vrai', (await seraiPresentCulte(tokA)) === true);
    const rsvp1 = await appel('GET', `/cultes/${culteId}/rsvp`, tokAdmin);
    verifier(
      'GET /cultes/:id/rsvp admin : 200, total 1, nom et matricule',
      rsvp1.statut === 200 &&
        rsvp1.json?.total === 1 &&
        rsvp1.json?.confirmes?.[0]?.membre_nom === 'Membre RSVP A' &&
        rsvp1.json?.confirmes?.[0]?.membre_matricule === 'M-RSVP-A01',
      rsvp1.texte.slice(0, 300),
    );
    const confirmeB = await appel('POST', `/moi/cultes/${culteId}/present`, tokB);
    verifier('POST /moi/cultes/:id/present B : 200', confirmeB.statut === 200, confirmeB.texte.slice(0, 200));
    const rsvp2 = await appel('GET', `/cultes/${culteId}/rsvp`, tokResponsable);
    verifier(
      'GET /cultes/:id/rsvp responsable_culte : 200, total 2',
      rsvp2.statut === 200 && rsvp2.json?.total === 2,
      rsvp2.texte.slice(0, 200),
    );
    const rsvpMembre = await appel('GET', `/cultes/${culteId}/rsvp`, tokA);
    verifier('GET /cultes/:id/rsvp membre : 403', rsvpMembre.statut === 403, rsvpMembre.texte.slice(0, 200));
    const rsvpAnnexe = await appel('GET', `/cultes/${culteId}/rsvp`, tokAnnexe);
    verifier('GET /cultes/:id/rsvp admin annexe : 404 (isolation)', rsvpAnnexe.statut === 404, rsvpAnnexe.texte.slice(0, 200));
    const annuleA = await appel('DELETE', `/moi/cultes/${culteId}/present`, tokA);
    verifier(
      'DELETE /moi/cultes/:id/present A : 200, present faux',
      annuleA.statut === 200 && annuleA.json?.present === false,
      annuleA.texte.slice(0, 200),
    );
    verifier('GET /moi/cultes A après annulation : serai_present faux', (await seraiPresentCulte(tokA)) === false);
    const rsvp3 = await appel('GET', `/cultes/${culteId}/rsvp`, tokAdmin);
    verifier(
      'GET /cultes/:id/rsvp après annulation : total 1 (B reste)',
      rsvp3.statut === 200 && rsvp3.json?.total === 1,
      rsvp3.texte.slice(0, 200),
    );
    const repriseA = await appel('POST', `/moi/cultes/${culteId}/present`, tokA);
    verifier('POST /moi/cultes/:id/present A après annulation : 200, reprise', repriseA.statut === 200, repriseA.texte.slice(0, 200));

    // --- 6. Culte : refus ---------------------------------------------------
    const culteAutreEglise = await appel('POST', `/moi/cultes/${culteId}/present`, tokX);
    verifier('POST culte mère par membre annexe : 404 (isolation)', culteAutreEglise.statut === 404, culteAutreEglise.texte.slice(0, 200));
    const culteSansMembre = await appel('POST', `/moi/cultes/${culteId}/present`, tokSansMembre);
    verifier('POST culte sans membre lié : 404', culteSansMembre.statut === 404, culteSansMembre.texte.slice(0, 200));
    const cultePasse = await appel('POST', `/moi/cultes/${cultePasseId}/present`, tokA);
    verifier('POST culte passé : 404', cultePasse.statut === 404, cultePasse.texte.slice(0, 200));
    const culteInconnu = await appel('POST', '/moi/cultes/00000000-0000-0000-0000-000000000000/present', tokA);
    verifier('POST culte inconnu : 404', culteInconnu.statut === 404, culteInconnu.texte.slice(0, 200));
    const culteSansJeton = await appel('POST', `/moi/cultes/${culteId}/present`, null);
    verifier('POST culte sans jeton : 401', culteSansJeton.statut === 401, culteSansJeton.texte.slice(0, 200));

    // --- 7. Activité : confirmation, doublon 409, annulation, reprise -----
    verifier('GET /moi/activites A avant : serai_present faux', (await seraiPresentActivite(tokA)) === false);
    const confirmeActA = await appel('POST', `/moi/activites/${activiteId}/present`, tokA);
    verifier(
      'POST /moi/activites/:id/present A : 200, present vrai',
      confirmeActA.statut === 200 && confirmeActA.json?.present === true,
      confirmeActA.texte.slice(0, 200),
    );
    const doublonActA = await appel('POST', `/moi/activites/${activiteId}/present`, tokA);
    verifier(
      'POST /moi/activites/:id/present A (doublon) : 409 deja_confirme',
      doublonActA.statut === 409 && doublonActA.json?.error === 'deja_confirme',
      doublonActA.texte.slice(0, 200),
    );
    verifier('GET /moi/activites A : serai_present vrai', (await seraiPresentActivite(tokA)) === true);
    const rsvpAct1 = await appel('GET', `/activites/${activiteId}/rsvp`, tokAdmin);
    verifier(
      'GET /activites/:id/rsvp admin : 200, total 1, nom et matricule',
      rsvpAct1.statut === 200 &&
        rsvpAct1.json?.total === 1 &&
        rsvpAct1.json?.confirmes?.[0]?.membre_nom === 'Membre RSVP A' &&
        rsvpAct1.json?.confirmes?.[0]?.membre_matricule === 'M-RSVP-A01',
      rsvpAct1.texte.slice(0, 300),
    );
    const confirmeActB = await appel('POST', `/moi/activites/${activiteId}/present`, tokB);
    verifier('POST /moi/activites/:id/present B : 200', confirmeActB.statut === 200, confirmeActB.texte.slice(0, 200));
    const rsvpAct2 = await appel('GET', `/activites/${activiteId}/rsvp`, tokResponsable);
    verifier(
      'GET /activites/:id/rsvp responsable_culte : 200, total 2',
      rsvpAct2.statut === 200 && rsvpAct2.json?.total === 2,
      rsvpAct2.texte.slice(0, 200),
    );
    const rsvpActMembre = await appel('GET', `/activites/${activiteId}/rsvp`, tokA);
    verifier('GET /activites/:id/rsvp membre : 403', rsvpActMembre.statut === 403, rsvpActMembre.texte.slice(0, 200));
    const rsvpActAnnexe = await appel('GET', `/activites/${activiteId}/rsvp`, tokAnnexe);
    verifier('GET /activites/:id/rsvp admin annexe : 404 (isolation)', rsvpActAnnexe.statut === 404, rsvpActAnnexe.texte.slice(0, 200));
    const annuleActA = await appel('DELETE', `/moi/activites/${activiteId}/present`, tokA);
    verifier(
      'DELETE /moi/activites/:id/present A : 200, present faux',
      annuleActA.statut === 200 && annuleActA.json?.present === false,
      annuleActA.texte.slice(0, 200),
    );
    verifier('GET /moi/activites A après annulation : serai_present faux', (await seraiPresentActivite(tokA)) === false);
    const rsvpAct3 = await appel('GET', `/activites/${activiteId}/rsvp`, tokAdmin);
    verifier(
      'GET /activites/:id/rsvp après annulation : total 1 (B reste)',
      rsvpAct3.statut === 200 && rsvpAct3.json?.total === 1,
      rsvpAct3.texte.slice(0, 200),
    );
    const repriseActA = await appel('POST', `/moi/activites/${activiteId}/present`, tokA);
    verifier('POST /moi/activites/:id/present A après annulation : 200, reprise', repriseActA.statut === 200, repriseActA.texte.slice(0, 200));
    const doublonActA2 = await appel('POST', `/moi/activites/${activiteId}/present`, tokA);
    verifier('POST /moi/activites/:id/present A (doublon après reprise) : 409', doublonActA2.statut === 409, doublonActA2.texte.slice(0, 200));

    // --- 8. Activité : refus ------------------------------------------------
    const actBrouillon = await appel('POST', `/moi/activites/${activiteBrouillonId}/present`, tokA);
    verifier('POST activité brouillon : 404', actBrouillon.statut === 404, actBrouillon.texte.slice(0, 200));
    const actPassee = await appel('POST', `/moi/activites/${activitePasseeId}/present`, tokA);
    verifier('POST activité passée : 404', actPassee.statut === 404, actPassee.texte.slice(0, 200));
    const actAutreEglise = await appel('POST', `/moi/activites/${activiteId}/present`, tokX);
    verifier('POST activité mère par membre annexe : 404 (isolation)', actAutreEglise.statut === 404, actAutreEglise.texte.slice(0, 200));
    const actSansMembre = await appel('POST', `/moi/activites/${activiteId}/present`, tokSansMembre);
    verifier('POST activité sans membre lié : 404', actSansMembre.statut === 404, actSansMembre.texte.slice(0, 200));
    const actInconnue = await appel('POST', '/moi/activites/00000000-0000-0000-0000-000000000000/present', tokA);
    verifier('POST activité inconnue : 404', actInconnue.statut === 404, actInconnue.texte.slice(0, 200));
    const actSansJeton = await appel('POST', `/moi/activites/${activiteId}/present`, null);
    verifier('POST activité sans jeton : 401', actSansJeton.statut === 401, actSansJeton.texte.slice(0, 200));

    // --- 9. Les confirmations ne sont pas des pointages --------------------
    const pointages = await direct.query(
      `SELECT count(*)::int AS n FROM presences WHERE church_id = $1`,
      [mereId],
    );
    verifier(
      'confirmations RSVP : aucune ligne dans presences',
      pointages.rows[0].n === 0,
      `reçu ${pointages.rows[0].n}`,
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
