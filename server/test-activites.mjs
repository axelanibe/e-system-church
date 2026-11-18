// Test d'intégration « Activités à venir » (V1) : migration 039,
// routes CRUD /activites (écriture admin_eglise seulement, brouillons
// invisibles aux membres), route fidèle GET /moi/activites (publiées
// à venir seulement, isolation par église).
// Même forme que server/test-identite-institutionnelle.mjs : base
// fraîche créée puis vidée par le test lui-même, application du schéma
// puis des migrations avec le vrai moteur de migration, démarrage de
// l'API, appels HTTP.
//
// Usage : `node server/test-activites.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4114).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_activites.
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

const PORT = Number(process.env.PORT ?? 4114);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_activites';
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0).
const JWT_SECRET = 'test-jwt-secret-pour-t11-seulement-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const MIGRATION_039 = readFileSync(
  new URL('../db/migrations/039_activites_a_venir.sql', import.meta.url),
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

  // Schéma + migrations avec le vrai moteur (dont la 039).
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, JWT_SECRET, PAYMENT_SECRETS_KEY },
  });

  const direct = new Client({ connectionString: DATABASE_URL });
  await direct.connect();

  // --- 1. Migration 039 : table et enregistrement -------------------------
  const colonnes = await direct.query(
    `SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'activites'`,
  );
  verifier(
    'migration 039 : table activites, 9 colonnes',
    colonnes.rowCount === 9,
    `reçu ${colonnes.rowCount} : ${colonnes.rows.map((r) => r.column_name).join(',')}`,
  );
  const migration = await direct.query(
    `SELECT 1 FROM schema_migrations WHERE name = '039_activites_a_venir'`,
  );
  verifier('migration 039 enregistrée dans schema_migrations', migration.rowCount === 1);
  const statutDefaut = (
    await direct.query(
      `SELECT column_default FROM information_schema.columns
        WHERE table_name = 'activites' AND column_name = 'statut'`,
    )
  ).rows[0]?.column_default;
  verifier(
    'migration 039 : statut par défaut brouillon',
    typeof statutDefaut === 'string' && statutDefaut.includes('brouillon'),
    String(statutDefaut),
  );
  // Rejeu : idempotence, rien ne change.
  const avant = JSON.stringify(
    (await direct.query(`SELECT * FROM activites ORDER BY id`)).rows,
  );
  await direct.query(MIGRATION_039);
  const apres = JSON.stringify(
    (await direct.query(`SELECT * FROM activites ORDER BY id`)).rows,
  );
  verifier('migration 039 rejouée : données inchangées', avant === apres);

  // --- 2. Données sources : mère + annexe ---------------------------------
  const eglise = async (code, nom, parent) =>
    (
      await direct.query(
        `INSERT INTO churches (code, code_fidele, name, parent_church_id, city, country,
             address, phone, email, status, devise, fuseau_horaire)
         VALUES ($1, $2, $3, $4, 'Abidjan', 'Côte d’Ivoire',
           '12 rue de la Mère', '+2250102030405', 'mere39@example.com', 'active', 'FCFA', 'Africa/Abidjan')
         RETURNING id`,
        [code, `${code}-F`, nom, parent],
      )
    ).rows[0].id;
  const mereId = await eglise('ESC-MERE39', 'Église Mère Activités', null);
  const annexeId = await eglise('ESC-ANNX39', 'Annexe Activités', mereId);

  // --- 3. Comptes : admin mère, admin annexe, responsable, trésorier,
  //      membre mère, membre annexe ----------------------------------------
  const hash = await argon2.hash('MotDePasse123!');
  const creerCompte = async (email, churchId, role) => {
    const u = (
      await direct.query(
        `INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id`,
        [email, hash, email],
      )
    ).rows[0].id;
    await direct.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
      [u, churchId, role],
    );
    return u;
  };
  await creerCompte('admin-mere39@example.com', mereId, 'admin_eglise');
  await creerCompte('admin-annexe39@example.com', annexeId, 'admin_eglise');
  await creerCompte('responsable-mere39@example.com', mereId, 'responsable_culte');
  await creerCompte('tresorier-mere39@example.com', mereId, 'tresorier');
  await creerCompte('membre-mere39@example.com', mereId, 'membre');
  await creerCompte('membre-annexe39@example.com', annexeId, 'membre');

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
    const tokAdmin = await login('admin-mere39@example.com');
    const tokAnnexe = await login('admin-annexe39@example.com');
    const tokResponsable = await login('responsable-mere39@example.com');
    const tokTresorier = await login('tresorier-mere39@example.com');
    const tokMembre = await login('membre-mere39@example.com');
    const tokMembreAnnexe = await login('membre-annexe39@example.com');

    // --- 4. Création : admin oui, autres rôles non, validation ------------
    const creee = await appel('POST', '/activites', tokAdmin, {
      titre: 'Sortie jeunesse EXEMPLE',
      description: 'Une sortie pour les jeunes de l’église.',
      date_heure: '2027-01-16 09:00',
      lieu: 'Parc EXEMPLE',
      responsable: 'Responsable EXEMPLE',
    });
    verifier(
      'POST /activites admin : 201, brouillon par défaut',
      creee.statut === 201 &&
        creee.json?.titre === 'Sortie jeunesse EXEMPLE' &&
        creee.json?.statut === 'brouillon' &&
        creee.json?.lieu === 'Parc EXEMPLE' &&
        creee.json?.responsable === 'Responsable EXEMPLE' &&
        typeof creee.json?.id === 'string',
      creee.texte.slice(0, 300),
    );
    const activiteId = creee.json?.id;
    const titreCourt = await appel('POST', '/activites', tokAdmin, {
      titre: 'A',
      date_heure: '2027-01-16 09:00',
    });
    verifier('POST /activites titre trop court : 400', titreCourt.statut === 400, titreCourt.texte);
    const statutInvalide = await appel('POST', '/activites', tokAdmin, {
      titre: 'Sortie EXEMPLE',
      date_heure: '2027-01-16 09:00',
      statut: 'visible',
    });
    verifier('POST /activites statut invalide : 400', statutInvalide.statut === 400, statutInvalide.texte);
    const creeResponsable = await appel('POST', '/activites', tokResponsable, {
      titre: 'Sortie EXEMPLE',
      date_heure: '2027-01-16 09:00',
    });
    verifier('POST /activites responsable_culte : 403', creeResponsable.statut === 403, creeResponsable.texte);
    const creeTresorier = await appel('POST', '/activites', tokTresorier, {
      titre: 'Sortie EXEMPLE',
      date_heure: '2027-01-16 09:00',
    });
    verifier('POST /activites trésorier : 403', creeTresorier.statut === 403, creeTresorier.texte);
    const creeMembre = await appel('POST', '/activites', tokMembre, {
      titre: 'Sortie EXEMPLE',
      date_heure: '2027-01-16 09:00',
    });
    verifier('POST /activites membre : 403', creeMembre.statut === 403, creeMembre.texte);

    // --- 5. Brouillon invisible aux membres -------------------------------
    const listeAdmin = await appel('GET', '/activites', tokAdmin);
    verifier(
      'GET /activites admin : 200, contient le brouillon',
      listeAdmin.statut === 200 &&
        Array.isArray(listeAdmin.json?.items) &&
        listeAdmin.json.items.some((a) => a.id === activiteId),
      listeAdmin.texte.slice(0, 300),
    );
    const listeMembre = await appel('GET', '/activites', tokMembre);
    verifier(
      'GET /activites membre : 200, brouillon absent',
      listeMembre.statut === 200 &&
        Array.isArray(listeMembre.json?.items) &&
        !listeMembre.json.items.some((a) => a.id === activiteId),
      listeMembre.texte.slice(0, 300),
    );
    const detailMembre = await appel('GET', `/activites/${activiteId}`, tokMembre);
    verifier('GET /activites/:id membre (brouillon) : 404', detailMembre.statut === 404, detailMembre.texte);
    const moiBrouillon = await appel('GET', '/moi/activites', tokMembre);
    verifier(
      'GET /moi/activites membre, brouillon seulement : 200, vide',
      moiBrouillon.statut === 200 &&
        Array.isArray(moiBrouillon.json?.activites) &&
        moiBrouillon.json.activites.length === 0,
      moiBrouillon.texte.slice(0, 200),
    );
    const moiSansJeton = await appel('GET', '/moi/activites', null);
    verifier('GET /moi/activites sans jeton : 401', moiSansJeton.statut === 401, moiSansJeton.texte);

    // --- 6. Publication : visible côté fidèle, isolée par église ----------
    const publie = await appel('PATCH', `/activites/${activiteId}`, tokAdmin, { statut: 'publié' });
    verifier(
      'PATCH /activites/:id publier : 200',
      publie.statut === 200 && publie.json?.statut === 'publié',
      publie.texte.slice(0, 200),
    );
    const moiPublie = await appel('GET', '/moi/activites', tokMembre);
    verifier(
      'GET /moi/activites membre : 200, liste la publiée',
      moiPublie.statut === 200 &&
        Array.isArray(moiPublie.json?.activites) &&
        moiPublie.json.activites.length === 1 &&
        moiPublie.json.activites[0]?.titre === 'Sortie jeunesse EXEMPLE' &&
        moiPublie.json.activites[0]?.lieu === 'Parc EXEMPLE' &&
        moiPublie.json.activites[0]?.responsable === 'Responsable EXEMPLE',
      moiPublie.texte.slice(0, 300),
    );
    const moiAnnexe = await appel('GET', '/moi/activites', tokMembreAnnexe);
    verifier(
      'GET /moi/activites membre annexe : 200, vide (isolation)',
      moiAnnexe.statut === 200 &&
        Array.isArray(moiAnnexe.json?.activites) &&
        moiAnnexe.json.activites.length === 0,
      moiAnnexe.texte.slice(0, 200),
    );
    const listeAnnexe = await appel('GET', '/activites', tokAnnexe);
    verifier(
      'GET /activites admin annexe : 200, vide (isolation)',
      listeAnnexe.statut === 200 &&
        Array.isArray(listeAnnexe.json?.items) &&
        listeAnnexe.json.items.length === 0,
      listeAnnexe.texte.slice(0, 200),
    );

    // --- 7. Activité passée : absente des « à venir » ----------------------
    const passee = await appel('POST', '/activites', tokAdmin, {
      titre: 'Sortie passée EXEMPLE',
      date_heure: '2020-01-01 09:00',
      statut: 'publié',
    });
    verifier('POST /activites passée publiée : 201', passee.statut === 201, passee.texte.slice(0, 200));
    const moiApresPassee = await appel('GET', '/moi/activites', tokMembre);
    verifier(
      'GET /moi/activites : la passée est absente, la future reste',
      moiApresPassee.statut === 200 &&
        moiApresPassee.json?.activites?.length === 1 &&
        moiApresPassee.json.activites[0]?.titre === 'Sortie jeunesse EXEMPLE',
      moiApresPassee.texte.slice(0, 300),
    );

    // --- 8. Modification et suppression ------------------------------------
    const patchResponsable = await appel('PATCH', `/activites/${activiteId}`, tokResponsable, {
      titre: 'Sortie renommée',
    });
    verifier('PATCH /activites/:id responsable_culte : 403', patchResponsable.statut === 403, patchResponsable.texte);
    const patchTitre = await appel('PATCH', `/activites/${activiteId}`, tokAdmin, {
      titre: 'Sortie jeunesse renommée',
    });
    verifier(
      'PATCH /activites/:id admin titre : 200',
      patchTitre.statut === 200 && patchTitre.json?.titre === 'Sortie jeunesse renommée',
      patchTitre.texte.slice(0, 200),
    );
    const supprimeResponsable = await appel('DELETE', `/activites/${activiteId}`, tokResponsable);
    verifier('DELETE /activites/:id responsable_culte : 403', supprimeResponsable.statut === 403, supprimeResponsable.texte);
    const supprime = await appel('DELETE', `/activites/${activiteId}`, tokAdmin);
    verifier(
      'DELETE /activites/:id admin : 200',
      supprime.statut === 200 && supprime.json?.ok === true,
      supprime.texte.slice(0, 200),
    );
    const apresSuppression = await appel('GET', `/activites/${activiteId}`, tokAdmin);
    verifier('GET /activites/:id après suppression : 404', apresSuppression.statut === 404, apresSuppression.texte);

    // --- 9. Journalisation ---------------------------------------------------
    const audit = await direct.query(
      `SELECT action FROM audit_logs WHERE church_id = $1 AND action = 'activite.cree'`,
      [mereId],
    );
    verifier('POST /activites : journalisé activite.cree', audit.rowCount >= 1, `reçu ${audit.rowCount}`);
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
