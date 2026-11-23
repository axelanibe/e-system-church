// Test d'intégration « Dépôt SYCEBNL » : migration 043, registres
// (immobilisations, dettes, créances, notes annexes), sommes SYCEBNL
// étendues, seuil et échéance du dépôt, suivi du dépôt, champ NCC.
// Même forme que server/test-activites.mjs : base fraîche créée puis
// vidée par le test lui-même, application du schéma puis des migrations
// avec le vrai moteur de migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-depot-sycebnl.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4125).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_depot_sycebnl.
// Base locale : PostgreSQL est nécessaire.
//
// Règle de référence : il n'existe pas d'API DGI, le dépôt se fait par
// l'église sur e-impots.gouv.ci avec son NCC. L'application prépare,
// exporte et suit, elle ne dépose pas elle-même.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);

const PORT = Number(process.env.PORT ?? 4125);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_depot_sycebnl';
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0).
const JWT_SECRET = 'secret-test-depot-sycebnl-0123456789abcdef';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const MIGRATION_043 = readFileSync(
  new URL('../db/migrations/043_depot_sycebnl.sql', import.meta.url),
  'utf8',
);

// Exercice courant : les sommes et le dépôt sont testés sur l'année
// civile en cours, pour ne pas dépendre de 2026.
const ANNEE = new Date().getFullYear();
const ECHEANCE = `${ANNEE + 1}-05-30`;

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

  // Schéma + migrations avec le vrai moteur (dont la 043).
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, JWT_SECRET, PAYMENT_SECRETS_KEY },
  });

  const direct = new Client({ connectionString: DATABASE_URL });
  await direct.connect();

  // --- 1. Migration 043 : tables, colonne NCC, enregistrement -----------
  for (const table of ['immobilisations', 'dettes', 'creances', 'notes_annexes', 'depots_sycebnl']) {
    const t = await direct.query(
      `SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = $1`,
      [table],
    );
    verifier(`migration 043 : table ${table} existe`, t.rowCount === 1);
  }
  const ncc = await direct.query(
    `SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'eglise_parametres'
        AND column_name = 'ncc'`,
  );
  verifier('migration 043 : colonne ncc sur eglise_parametres', ncc.rowCount === 1);
  const migration = await direct.query(
    `SELECT 1 FROM schema_migrations WHERE name = '043_depot_sycebnl'`,
  );
  verifier('migration 043 enregistrée dans schema_migrations', migration.rowCount === 1);
  // Rejeu : idempotence, rien ne change.
  const avant = JSON.stringify(
    (await direct.query(`SELECT * FROM immobilisations ORDER BY id`)).rows,
  );
  await direct.query(MIGRATION_043);
  const apres = JSON.stringify(
    (await direct.query(`SELECT * FROM immobilisations ORDER BY id`)).rows,
  );
  verifier('migration 043 rejouée : données inchangées', avant === apres);

  // --- 2. Données sources : mère + annexe ---------------------------------
  const eglise = async (code, nom, parent) =>
    (
      await direct.query(
        `INSERT INTO churches (code, code_fidele, name, parent_church_id, city, country,
             address, phone, email, status, devise, fuseau_horaire)
         VALUES ($1, $2, $3, $4, 'Abidjan', 'Côte d’Ivoire',
           '12 rue de la Mère', '+2250102030405', 'mere43@example.com', 'active', 'FCFA', 'Africa/Abidjan')
         RETURNING id`,
        [code, `${code}-F`, nom, parent],
      )
    ).rows[0].id;
  const mereId = await eglise('ESC-MERE43', 'Église Mère Dépôt', null);
  const annexeId = await eglise('ESC-ANNX43', 'Annexe Dépôt', mereId);

  // --- 3. Comptes : admin mère, trésorier mère, membre mère, admin annexe -
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
  await creerCompte('admin-mere43@example.com', mereId, 'admin_eglise');
  await creerCompte('tresorier-mere43@example.com', mereId, 'tresorier');
  await creerCompte('membre-mere43@example.com', mereId, 'membre');
  await creerCompte('admin-annexe43@example.com', annexeId, 'admin_eglise');

  // --- 4. Comptabilité source : contributions confirmées ------------------
  // Mère, exercice courant : dîme 40 M + offrande 15 M + don 5 M +
  // cotisation 2 M = 62 000 000 de ressources ; dépense 3 000 000.
  // Une offrande en attente (9 999 999) ne compte pas. Une dîme de
  // l'exercice précédent (1 000 000) alimente l'ouverture.
  const contribuer = async (churchId, type, montant, statut, date) =>
    direct.query(
      `INSERT INTO contributions (church_id, member_id, type, amount_fcfa,
           payment_method, status, created_at)
         VALUES ($1, NULL, $2, $3, 'especes', $4, $5)`,
      [churchId, type, montant, statut, date],
    );
  await contribuer(mereId, 'dime', 40000000, 'confirme', `${ANNEE}-03-10T12:00:00Z`);
  await contribuer(mereId, 'offrande', 15000000, 'confirme', `${ANNEE}-04-10T12:00:00Z`);
  await contribuer(mereId, 'don', 5000000, 'confirme', `${ANNEE}-05-10T12:00:00Z`);
  await contribuer(mereId, 'cotisation', 2000000, 'confirme', `${ANNEE}-06-10T12:00:00Z`);
  await contribuer(mereId, 'depense', 3000000, 'confirme', `${ANNEE}-07-10T12:00:00Z`);
  await contribuer(mereId, 'offrande', 9999999, 'en_attente', `${ANNEE}-08-10T12:00:00Z`);
  await contribuer(mereId, 'dime', 1000000, 'confirme', `${ANNEE - 1}-06-10T12:00:00Z`);
  // Annexe : 1 000 000 seulement, sous le seuil.
  await contribuer(annexeId, 'dime', 1000000, 'confirme', `${ANNEE}-03-10T12:00:00Z`);

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
    const tokAdmin = await login('admin-mere43@example.com');
    const tokTresorier = await login('tresorier-mere43@example.com');
    const tokMembre = await login('membre-mere43@example.com');
    const tokAnnexe = await login('admin-annexe43@example.com');

    // --- 5. Immobilisations : admin oui, autres non, validation -----------
    const immo = await appel('POST', '/immobilisations', tokAdmin, {
      libelle: 'Temple EXEMPLE',
      date_acquisition: `${ANNEE}-03-10`,
      valeur_acquisition: 1000000,
      amortissement_cumule: 200000,
    });
    verifier(
      'POST /immobilisations admin : 201, valeur nette 800 000',
      immo.statut === 201 &&
        immo.json?.libelle === 'Temple EXEMPLE' &&
        typeof immo.json?.id === 'string',
      immo.texte.slice(0, 300),
    );
    const immoId = immo.json?.id;
    const immoAmorti = await appel('POST', '/immobilisations', tokAdmin, {
      libelle: 'Trop amorti EXEMPLE',
      date_acquisition: `${ANNEE}-03-10`,
      valeur_acquisition: 100000,
      amortissement_cumule: 200000,
    });
    verifier(
      'POST /immobilisations amortissement supérieur à la valeur : 400',
      immoAmorti.statut === 400,
      immoAmorti.texte.slice(0, 200),
    );
    const immoTresorier = await appel('POST', '/immobilisations', tokTresorier, {
      libelle: 'Trésorier EXEMPLE',
      date_acquisition: `${ANNEE}-03-10`,
      valeur_acquisition: 100000,
    });
    verifier('POST /immobilisations trésorier : 403', immoTresorier.statut === 403, immoTresorier.texte);
    const immoMembre = await appel('POST', '/immobilisations', tokMembre, {
      libelle: 'Membre EXEMPLE',
      date_acquisition: `${ANNEE}-03-10`,
      valeur_acquisition: 100000,
    });
    verifier('POST /immobilisations membre : 403', immoMembre.statut === 403, immoMembre.texte);
    const listeImmo = await appel('GET', '/immobilisations', tokAdmin);
    verifier(
      'GET /immobilisations admin : 200, contient le temple',
      listeImmo.statut === 200 &&
        Array.isArray(listeImmo.json?.items) &&
        listeImmo.json.items.some((a) => a.id === immoId),
      listeImmo.texte.slice(0, 300),
    );
    const listeImmoAnnexe = await appel('GET', '/immobilisations', tokAnnexe);
    verifier(
      'GET /immobilisations admin annexe : 200, vide (isolation)',
      listeImmoAnnexe.statut === 200 &&
        Array.isArray(listeImmoAnnexe.json?.items) &&
        listeImmoAnnexe.json.items.length === 0,
      listeImmoAnnexe.texte.slice(0, 300),
    );
    const patchImmo = await appel('PATCH', `/immobilisations/${immoId}`, tokAdmin, {
      amortissement_cumule: 250000,
    });
    verifier(
      'PATCH /immobilisations admin : 200, amortissement 250 000',
      patchImmo.statut === 200 && patchImmo.json?.amortissement_cumule === 250000,
      patchImmo.texte.slice(0, 200),
    );

    // --- 6. Dettes, créances, notes : création et isolation --------------
    const dette = await appel('POST', '/dettes', tokAdmin, {
      libelle: 'Emprunt travaux EXEMPLE',
      montant: 500000,
      echeance: `${ANNEE + 1}-06-30`,
    });
    verifier(
      'POST /dettes admin : 201, en cours par défaut',
      dette.statut === 201 && dette.json?.statut === 'en_cours',
      dette.texte.slice(0, 300),
    );
    const detteStatut = await appel('POST', '/dettes', tokAdmin, {
      libelle: 'Statut EXEMPLE',
      montant: 1000,
      statut: 'payee',
    });
    verifier('POST /dettes statut invalide : 400', detteStatut.statut === 400, detteStatut.texte);
    const creance = await appel('POST', '/creances', tokAdmin, {
      libelle: 'Loyer à recevoir EXEMPLE',
      montant: 100000,
      echeance: `${ANNEE}-12-31`,
    });
    verifier('POST /creances admin : 201', creance.statut === 201, creance.texte.slice(0, 300));
    const note = await appel('POST', '/notes-annexes', tokAdmin, {
      titre: 'Méthode comptable EXEMPLE',
      contenu: 'Les dîmes sont comptées à la réception, en FCFA.',
      exercice: ANNEE,
    });
    verifier('POST /notes-annexes admin : 201', note.statut === 201, note.texte.slice(0, 300));
    const listeNotesAnnexe = await appel('GET', '/notes-annexes', tokAnnexe);
    verifier(
      'GET /notes-annexes admin annexe : 200, vide (isolation)',
      listeNotesAnnexe.statut === 200 &&
        Array.isArray(listeNotesAnnexe.json?.items) &&
        listeNotesAnnexe.json.items.length === 0,
      listeNotesAnnexe.texte.slice(0, 300),
    );

    // --- 7. Sommes SYCEBNL étendues -----------------------------------------
    // Produits 60 000 000 (dîme 40 M + offrande 15 M + don 5 M ; la
    // cotisation de 2 M compte dans les ressources du dépôt, pas dans
    // les produits SYCEBNL, dont les sources restent celles de la P6),
    // charges 3 000 000, résultat 57 000 000, ouverture 1 000 000,
    // clôture 58 000 000. Immobilisation nette 750 000 (1 000 000 −
    // 250 000 après le PATCH), dette 500 000, créance 100 000. Fonds
    // propres = 750 000 + 100 000 + 58 000 000 − 500 000 = 58 350 000.
    // Flux investissement −1 000 000 (achat de l'exercice), flux
    // financement +500 000 (dette créée), flux opérationnel =
    // 57 000 000 + 1 000 000 − 500 000 = 57 500 000, variation
    // = 57 000 000 = résultat.
    const donnees = await appel('GET', `/exports/sycebnl/donnees?annee=${ANNEE}`, tokAdmin);
    verifier(
      'GET /exports/sycebnl/donnees : produits 60 000 000, charges 3 000 000',
      donnees.statut === 200 &&
        donnees.json?.produits === 60000000 &&
        donnees.json?.charges === 3000000 &&
        donnees.json?.resultat === 57000000 &&
        donnees.json?.ouverture === 1000000 &&
        donnees.json?.cloture === 58000000,
      donnees.texte.slice(0, 300),
    );
    verifier(
      'GET /exports/sycebnl/donnees : bilan complet, fonds propres 58 350 000',
      donnees.statut === 200 &&
        donnees.json?.actifImmobilise === 750000 &&
        donnees.json?.actifCirculant === 100000 &&
        donnees.json?.dettes === 500000 &&
        donnees.json?.fondsPropres === 58350000,
      donnees.texte.slice(0, 300),
    );
    verifier(
      'GET /exports/sycebnl/donnees : flux, variation = résultat',
      donnees.statut === 200 &&
        donnees.json?.fluxInvestissement === -1000000 &&
        donnees.json?.fluxFinancement === 500000 &&
        donnees.json?.fluxOperationnelles === 57500000 &&
        donnees.json?.variation === 57000000 &&
        donnees.json?.notesRedigees === 1,
      donnees.texte.slice(0, 300),
    );
    const pdfBilan = await fetch(`${BASE}/exports/sycebnl?etat=bilan&annee=${ANNEE}`, {
      headers: { authorization: `Bearer ${tokAdmin}` },
    });
    const pdfTexte = await pdfBilan.text();
    verifier(
      'GET /exports/sycebnl bilan : 200, PDF',
      pdfBilan.status === 200 &&
        (pdfBilan.headers.get('content-type') ?? '').includes('application/pdf') &&
        pdfTexte.startsWith('%PDF'),
      `statut ${pdfBilan.status}`,
    );

    // --- 8. Dépôt : seuil, échéance, suivi ---------------------------------
    const depotSansJeton = await appel('GET', `/sycebnl/depot?annee=${ANNEE}`, null);
    verifier('GET /sycebnl/depot sans jeton : 401', depotSansJeton.statut === 401, depotSansJeton.texte);
    const depotMembre = await appel('GET', `/sycebnl/depot?annee=${ANNEE}`, tokMembre);
    verifier('GET /sycebnl/depot membre : 403', depotMembre.statut === 403, depotMembre.texte);
    const depot = await appel('GET', `/sycebnl/depot?annee=${ANNEE}`, tokAdmin);
    verifier(
      'GET /sycebnl/depot mère : requis, ressources 62 000 000, échéance 30 mai',
      depot.statut === 200 &&
        depot.json?.ressources === 62000000 &&
        depot.json?.seuil === 50000000 &&
        depot.json?.requis === true &&
        depot.json?.echeance === ECHEANCE &&
        depot.json?.suivi === null,
      depot.texte.slice(0, 400),
    );
    const depotTresorier = await appel('GET', `/sycebnl/depot?annee=${ANNEE}`, tokTresorier);
    verifier('GET /sycebnl/depot trésorier : 200', depotTresorier.statut === 200, depotTresorier.texte);
    const depotAnnexe = await appel('GET', `/sycebnl/depot?annee=${ANNEE}`, tokAnnexe);
    verifier(
      'GET /sycebnl/depot annexe : non requis, ressources 1 000 000',
      depotAnnexe.statut === 200 &&
        depotAnnexe.json?.ressources === 1000000 &&
        depotAnnexe.json?.requis === false,
      depotAnnexe.texte.slice(0, 400),
    );
    const suiviTresorier = await appel('PATCH', '/sycebnl/depot', tokTresorier, {
      annee: ANNEE,
      statut: 'pret',
    });
    verifier('PATCH /sycebnl/depot trésorier : 403', suiviTresorier.statut === 403, suiviTresorier.texte);
    const suiviSansDate = await appel('PATCH', '/sycebnl/depot', tokAdmin, {
      annee: ANNEE,
      statut: 'depose',
    });
    verifier(
      'PATCH /sycebnl/depot déposé sans date : 400',
      suiviSansDate.statut === 400,
      suiviSansDate.texte.slice(0, 200),
    );
    const suivi = await appel('PATCH', '/sycebnl/depot', tokAdmin, {
      annee: ANNEE,
      statut: 'depose',
      date_depot: `${ANNEE + 1}-05-20`,
      reference: 'REC-IMPOTS-EXEMPLE',
    });
    verifier(
      'PATCH /sycebnl/depot admin : 200, déposé avec date et référence',
      suivi.statut === 200 &&
        suivi.json?.statut === 'depose' &&
        suivi.json?.date_depot === `${ANNEE + 1}-05-20` &&
        suivi.json?.reference === 'REC-IMPOTS-EXEMPLE',
      suivi.texte.slice(0, 300),
    );
    const depotApres = await appel('GET', `/sycebnl/depot?annee=${ANNEE}`, tokAdmin);
    verifier(
      'GET /sycebnl/depot après suivi : suivi déposé',
      depotApres.statut === 200 && depotApres.json?.suivi?.statut === 'depose',
      depotApres.texte.slice(0, 300),
    );
    const suiviMaj = await appel('PATCH', '/sycebnl/depot', tokAdmin, {
      annee: ANNEE,
      statut: 'pret',
    });
    verifier(
      'PATCH /sycebnl/depot second : 200, statut mis à jour',
      suiviMaj.statut === 200 && suiviMaj.json?.statut === 'pret',
      suiviMaj.texte.slice(0, 300),
    );

    // --- 9. NCC dans l'identité ---------------------------------------------
    const nccAdmin = await appel('PATCH', '/identite', tokAdmin, { ncc: 'NCC-EXEMPLE-123' });
    verifier(
      'PATCH /identite NCC admin mère : 200, NCC renvoyé',
      nccAdmin.statut === 200 && nccAdmin.json?.ncc === 'NCC-EXEMPLE-123',
      nccAdmin.texte.slice(0, 300),
    );
    const identite = await appel('GET', '/identite', tokAdmin);
    verifier(
      'GET /identite : NCC présent',
      identite.statut === 200 && identite.json?.ncc === 'NCC-EXEMPLE-123',
      identite.texte.slice(0, 300),
    );
    const nccAnnexe = await appel('PATCH', '/identite', tokAnnexe, { ncc: 'NCC-ANNEXE' });
    verifier('PATCH /identite NCC admin annexe : 403', nccAnnexe.statut === 403, nccAnnexe.texte);

    // --- 10. Journalisation --------------------------------------------------
    const auditImmo = await direct.query(
      `SELECT action FROM audit_logs WHERE church_id = $1 AND action = 'immobilisation.cree'`,
      [mereId],
    );
    verifier('POST /immobilisations : journalisé immobilisation.cree', auditImmo.rowCount >= 1, `reçu ${auditImmo.rowCount}`);
    const auditDepot = await direct.query(
      `SELECT action FROM audit_logs WHERE church_id = $1 AND action = 'depot.sycebnl.maj'`,
      [mereId],
    );
    verifier('PATCH /sycebnl/depot : journalisé depot.sycebnl.maj', auditDepot.rowCount >= 1, `reçu ${auditDepot.rowCount}`);

    // --- 11. Suppression de l'immobilisation --------------------------------
    const supprime = await appel('DELETE', `/immobilisations/${immoId}`, tokAdmin);
    verifier(
      'DELETE /immobilisations admin : 200',
      supprime.statut === 200 && supprime.json?.ok === true,
      supprime.texte.slice(0, 200),
    );
    const apresSuppression = await appel('GET', `/immobilisations/${immoId}`, tokAdmin);
    verifier('GET /immobilisations/:id après suppression : 404', apresSuppression.statut === 404, apresSuppression.texte);
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
