// Test d'intégration de la Phase 2 « Identité institutionnelle et
// documents » (tranche serveur) : migration 037, héritage mère/annexe,
// gardes 403 sur les champs institutionnels, routes GET/PATCH /identite
// et synchronisations entre `churches` et `eglise_parametres`.
// Même forme que server/test-messagerie-t0.mjs : base fraîche créée puis
// vidée par le test lui-même, application du schéma puis des migrations
// avec le vrai moteur de migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-identite-institutionnelle.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4113).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_identite.
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

const PORT = Number(process.env.PORT ?? 4113);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_identite';
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0).
const JWT_SECRET = 'test-jwt-secret-pour-t11-seulement-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const MIGRATION_037 = readFileSync(
  new URL('../db/migrations/037_identite_institutionnelle.sql', import.meta.url),
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

  // Schéma + migrations avec le vrai moteur (dont la 037, sans église :
  // la copie de données n'a alors rien à faire).
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, JWT_SECRET, PAYMENT_SECRETS_KEY },
  });

  const direct = new Client({ connectionString: DATABASE_URL });
  await direct.connect();

  // --- 1. Migration 037 : colonnes et enregistrement ----------------------
  const colonnes = await direct.query(
    `SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'eglise_parametres'
        AND column_name IN ('sigle','slogan','site_web','numero_enregistrement',
          'infos_legales','couleurs','parametres_documents','statut')`,
  );
  verifier('migration 037 : 8 colonnes ajoutées à eglise_parametres', colonnes.rowCount === 8, `reçu ${colonnes.rowCount}`);
  const migration = await direct.query(
    `SELECT 1 FROM schema_migrations WHERE name = '037_identite_institutionnelle'`,
  );
  verifier('migration 037 enregistrée dans schema_migrations', migration.rowCount === 1);

  // --- 2. Données sources : mère + annexe, valeurs côté `churches` --------
  const eglise = async (code, nom, parent, vals) =>
    (
      await direct.query(
        `INSERT INTO churches (code, code_fidele, name, parent_church_id, city, country,
             address, phone, email, status, logo_url, couleur_principale,
             devise, fuseau_horaire, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'active', $10, $11, $12, $13, $14)
         RETURNING id`,
        [code, `${code}-F`, nom, parent, vals.ville, vals.pays ?? 'Côte d’Ivoire',
         vals.adresse, vals.telephone, vals.email, vals.logo_url,
         vals.couleur_principale, vals.devise, vals.fuseau_horaire, vals.description ?? null],
      )
    ).rows[0].id;
  const mereId = await eglise('ESC-MERE37', 'Église Mère Identité', null, {
    ville: 'Abidjan', adresse: '12 rue de la Mère', telephone: '+2250102030405',
    email: 'mere37@example.com', logo_url: '/logos/mere-churches.png',
    couleur_principale: '#2A0059', devise: 'FCFA', fuseau_horaire: 'Africa/Abidjan',
    description: 'Église mère de test.',
  });
  const annexeId = await eglise('ESC-ANNX37', 'Annexe de Yopougon', mereId, {
    ville: 'Yopougon', adresse: '3 rue de la Branche', telephone: '+2250708080911',
    email: 'annexe37@example.com', logo_url: '/logos/annexe-churches.png',
    // Devise et fuseau non standards côté `churches` seulement : la
    // migration doit les reprendre (la cible ne porte que le défaut).
    couleur_principale: '#3D0073', devise: 'XOF', fuseau_horaire: 'Europe/Paris',
  });
  // Conflit : la mère a déjà une ligne `eglise_parametres` avec un logo
  // différent — c'est elle qui doit gagner, pas `churches`.
  await direct.query(
    `INSERT INTO eglise_parametres (church_id, logo_url) VALUES ($1, $2)`,
    [mereId, '/logos/mere-parametres-gagne.png'],
  );

  // Deuxième application de la 037 sur les données : c'est elle qui
  // effectue la copie (la première, par le moteur, n'avait aucune église).
  const notices2 = [];
  direct.on('notice', (m) => notices2.push(m.message));
  await direct.query(MIGRATION_037);
  verifier(
    'migration 037 rejouée : 1 ligne créée, 2 lignes mises à jour (RAISE NOTICE)',
    notices2.some((n) => n.includes('1 lignes eglise_parametres créées, 2 lignes mises à jour')),
    notices2.join(' | '),
  );
  const params = await direct.query(
    `SELECT church_id, adresse, ville, telephone, email, logo_url, couleurs
       FROM eglise_parametres WHERE church_id IN ($1, $2) ORDER BY church_id`,
    [mereId, annexeId],
  );
  verifier('migration 037 : 2 lignes eglise_parametres', params.rowCount === 2, `reçu ${params.rowCount}`);
  const parMere = params.rows.find((r) => r.church_id === mereId);
  const parAnnexe = params.rows.find((r) => r.church_id === annexeId);
  verifier(
    'migration 037 : conflit, eglise_parametres gagne (logo mère)',
    parMere?.logo_url === '/logos/mere-parametres-gagne.png',
    String(parMere?.logo_url),
  );
  verifier(
    'migration 037 : adresse et ville migrées depuis churches (annexe)',
    parAnnexe?.adresse === '3 rue de la Branche' && parAnnexe?.ville === 'Yopougon',
    JSON.stringify(parAnnexe),
  );
  verifier(
    'migration 037 : téléphone, email et logo migrés (annexe)',
    parAnnexe?.telephone === '+2250708080911' &&
      parAnnexe?.email === 'annexe37@example.com' &&
      parAnnexe?.logo_url === '/logos/annexe-churches.png',
    JSON.stringify(parAnnexe),
  );
  verifier(
    'migration 037 : couleur_principale migrée vers couleurs.principale (annexe)',
    parAnnexe?.couleurs?.principale === '#3D0073',
    JSON.stringify(parAnnexe?.couleurs),
  );
  const parAnnexeDevise = (
    await direct.query(`SELECT devise, fuseau_horaire FROM eglise_parametres WHERE church_id = $1`, [annexeId])
  ).rows[0];
  verifier(
    'migration 037 : devise et fuseau non standards repris depuis churches (défaut seul côté paramètres)',
    parAnnexeDevise?.devise === 'XOF' && parAnnexeDevise?.fuseau_horaire === 'Europe/Paris',
    JSON.stringify(parAnnexeDevise),
  );
  verifier(
    'migration 037 : statut par défaut brouillon (annexe)',
    (await direct.query(`SELECT statut FROM eglise_parametres WHERE church_id = $1`, [annexeId])).rows[0]?.statut === 'brouillon',
  );

  // Troisième application : idempotence, rien ne change.
  const avant = JSON.stringify(
    (await direct.query(`SELECT * FROM eglise_parametres ORDER BY church_id`)).rows,
  );
  const notices3 = [];
  const onNotice3 = (m) => notices3.push(m.message);
  direct.on('notice', onNotice3);
  await direct.query(MIGRATION_037);
  direct.off('notice', onNotice3);
  const apres = JSON.stringify(
    (await direct.query(`SELECT * FROM eglise_parametres ORDER BY church_id`)).rows,
  );
  verifier(
    'migration 037 : troisième passage, 0 créée, 0 mise à jour',
    notices3.some((n) => n.includes('0 lignes eglise_parametres créées, 0 lignes mises à jour')),
    notices3.join(' | '),
  );
  verifier('migration 037 : troisième passage, données inchangées', avant === apres);

  // --- 3. Comptes : admin mère, admin annexe, trésorier mère ---------------
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
  await creerCompte('admin-mere37@example.com', mereId, 'admin_eglise');
  await creerCompte('admin-annexe37@example.com', annexeId, 'admin_eglise');
  await creerCompte('tresorier-mere37@example.com', mereId, 'tresorier');

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
    const tokMere = await login('admin-mere37@example.com');
    const tokAnnexe = await login('admin-annexe37@example.com');
    const tokTresorier = await login('tresorier-mere37@example.com');

    // --- 4. GET /identite : propre pour la mère -----------------------------
    const getMere = await appel('GET', '/identite', tokMere);
    verifier(
      'GET /identite mère : 200, valeurs propres, non hérité',
      getMere.statut === 200 &&
        getMere.json?.eglise_nom === 'Église Mère Identité' &&
        getMere.json?.est_annexe === false &&
        getMere.json?.heritee === false &&
        getMere.json?.statut === 'brouillon' &&
        getMere.json?.statut_mere === null &&
        getMere.json?.logo_url === '/logos/mere-parametres-gagne.png',
      getMere.texte.slice(0, 300),
    );
    const getTresorier = await appel('GET', '/identite', tokTresorier);
    verifier('GET /identite trésorier mère : 200', getTresorier.statut === 200, getTresorier.texte.slice(0, 200));
    const sansJeton = await appel('GET', '/identite', null);
    verifier('GET /identite sans jeton : 401', sansJeton.statut === 401, sansJeton.texte);

    // --- 5. PATCH /identite mère : accepté, synchronisé, journalisé --------
    const patchMere = await appel('PATCH', '/identite', tokMere, {
      nom_officiel: 'Église Mère Renommée',
      sigle: 'EMR',
      slogan: 'Une foi, une famille.',
      logo_url: 'https://example.com/logo-mere.png',
      couleur_principale: '#1A003F',
      couleurs: { secondaire: '#E8B820' },
      adresse: '24 avenue de la Mère',
      ville: 'Abidjan',
      pays: 'Côte d’Ivoire',
      telephone: '+2250102030499',
      email: 'contact-mere37@example.com',
      site_web: 'https://mere37.example.com',
      devise: 'XOF',
      fuseau_horaire: 'Africa/Abidjan',
      numero_enregistrement: 'REG-37-001',
      infos_legales: { forme: 'Association' },
      parametres_documents: { langue: 'fr' },
      description: 'Nouvelle description.',
      statut: 'publié',
    });
    verifier(
      'PATCH /identite mère : 200, identité résolue renvoyée',
      patchMere.statut === 200 &&
        patchMere.json?.nom_officiel === 'Église Mère Renommée' &&
        patchMere.json?.sigle === 'EMR' &&
        patchMere.json?.couleur_principale === '#1A003F' &&
        patchMere.json?.couleurs?.secondaire === '#E8B820' &&
        patchMere.json?.statut === 'publié' &&
        patchMere.json?.heritee === false,
      patchMere.texte.slice(0, 400),
    );
    const mereApres = (
      await direct.query(
        `SELECT name, logo_url, couleur_principale, country, description FROM churches WHERE id = $1`,
        [mereId],
      )
    ).rows[0];
    verifier(
      'PATCH /identite mère : churches synchronisé (nom, logo, couleur, pays, description)',
      mereApres?.name === 'Église Mère Renommée' &&
        mereApres?.logo_url === 'https://example.com/logo-mere.png' &&
        mereApres?.couleur_principale === '#1A003F' &&
        mereApres?.country === 'Côte d’Ivoire' &&
        mereApres?.description === 'Nouvelle description.',
      JSON.stringify(mereApres),
    );
    const paramsMere = (
      await direct.query(
        `SELECT sigle, slogan, site_web, numero_enregistrement, infos_legales,
                parametres_documents, devise, statut, couleurs
           FROM eglise_parametres WHERE church_id = $1`,
        [mereId],
      )
    ).rows[0];
    verifier(
      'PATCH /identite mère : eglise_parametres porte les nouveaux champs',
      paramsMere?.sigle === 'EMR' &&
        paramsMere?.slogan === 'Une foi, une famille.' &&
        paramsMere?.site_web === 'https://mere37.example.com' &&
        paramsMere?.numero_enregistrement === 'REG-37-001' &&
        paramsMere?.infos_legales?.forme === 'Association' &&
        paramsMere?.parametres_documents?.langue === 'fr' &&
        paramsMere?.devise === 'XOF' &&
        paramsMere?.statut === 'publié' &&
        paramsMere?.couleurs?.principale === '#1A003F' &&
        paramsMere?.couleurs?.secondaire === '#E8B820',
      JSON.stringify(paramsMere),
    );
    const audit = await direct.query(
      `SELECT action, details FROM audit_logs WHERE church_id = $1 AND action = 'identite.modifiee'`,
      [mereId],
    );
    verifier(
      'PATCH /identite mère : journalisé identite.modifiee avec les champs',
      audit.rowCount === 1 && Array.isArray(audit.rows[0]?.details?.champs) && audit.rows[0].details.champs.includes('sigle'),
      JSON.stringify(audit.rows[0]),
    );
    const patchVide = await appel('PATCH', '/identite', tokMere, {});
    verifier('PATCH /identite mère sans champ : 400', patchVide.statut === 400, patchVide.texte);
    const patchCouleur = await appel('PATCH', '/identite', tokMere, { couleur_principale: 'rouge' });
    verifier('PATCH /identite mère couleur invalide : 400', patchCouleur.statut === 400, patchCouleur.texte);

    // --- 6. Héritage : l'annexe voit la mère publiée ------------------------
    const getAnnexeHeritee = await appel('GET', '/identite', tokAnnexe);
    verifier(
      'GET /identite annexe : hérite de la mère publiée',
      getAnnexeHeritee.statut === 200 &&
        getAnnexeHeritee.json?.heritee === true &&
        getAnnexeHeritee.json?.est_annexe === true &&
        getAnnexeHeritee.json?.eglise_nom === 'Annexe de Yopougon' &&
        getAnnexeHeritee.json?.nom_officiel === 'Église Mère Renommée' &&
        getAnnexeHeritee.json?.sigle === 'EMR' &&
        getAnnexeHeritee.json?.logo_url === 'https://example.com/logo-mere.png' &&
        getAnnexeHeritee.json?.couleur_principale === '#1A003F' &&
        getAnnexeHeritee.json?.adresse === '24 avenue de la Mère' &&
        getAnnexeHeritee.json?.devise === 'XOF' &&
        getAnnexeHeritee.json?.statut_mere === 'publié' &&
        getAnnexeHeritee.json?.mere?.id === mereId,
      getAnnexeHeritee.texte.slice(0, 500),
    );
    verifier(
      'GET /identite annexe : coordonnées locales propres conservées',
      getAnnexeHeritee.json?.adresse_locale === '3 rue de la Branche' &&
        getAnnexeHeritee.json?.ville_locale === 'Yopougon' &&
        getAnnexeHeritee.json?.telephone_local === '+2250708080911' &&
        getAnnexeHeritee.json?.email_local === 'annexe37@example.com',
      getAnnexeHeritee.texte.slice(0, 300),
    );

    // --- 7. Mère brouillon : l'annexe retombe sur ses valeurs propres ------
    const repasseBrouillon = await appel('PATCH', '/identite', tokMere, { statut: 'brouillon' });
    verifier('PATCH /identite mère repasse brouillon : 200', repasseBrouillon.statut === 200, repasseBrouillon.texte.slice(0, 200));
    const getAnnexePropre = await appel('GET', '/identite', tokAnnexe);
    verifier(
      'GET /identite annexe, mère brouillon : valeurs propres, non hérité',
      getAnnexePropre.statut === 200 &&
        getAnnexePropre.json?.heritee === false &&
        getAnnexePropre.json?.nom_officiel === 'Annexe de Yopougon' &&
        getAnnexePropre.json?.logo_url === '/logos/annexe-churches.png' &&
        getAnnexePropre.json?.couleur_principale === '#3D0073' &&
        getAnnexePropre.json?.statut_mere === 'brouillon',
      getAnnexePropre.texte.slice(0, 500),
    );
    // On republie pour la suite (les gardes n'en dépendent pas, mais
    // l'état final reste cohérent).
    await appel('PATCH', '/identite', tokMere, { statut: 'publié' });

    // --- 8. Gardes 403 : annexe refusée sur les champs institutionnels -----
    const patchAnnexeIdentite = await appel('PATCH', '/identite', tokAnnexe, { sigle: 'AX' });
    verifier(
      'PATCH /identite annexe : 403',
      patchAnnexeIdentite.statut === 403 &&
        patchAnnexeIdentite.json?.message === 'Seule l’église mère modifie son identité institutionnelle.',
      patchAnnexeIdentite.texte,
    );
    const patchParamsLogo = await appel('PATCH', '/parametres', tokAnnexe, { logo_url: 'https://example.com/annexe.png' });
    verifier(
      'PATCH /parametres annexe logo_url : 403 champ hérité',
      patchParamsLogo.statut === 403 &&
        patchParamsLogo.json?.message ===
          'Champ institutionnel hérité de l’église mère : modifiable uniquement par l’église mère.',
      patchParamsLogo.texte,
    );
    const patchParamsDevise = await appel('PATCH', '/parametres', tokAnnexe, { devise: 'EUR' });
    verifier('PATCH /parametres annexe devise : 403', patchParamsDevise.statut === 403, patchParamsDevise.texte);
    const patchParamsFuseau = await appel('PATCH', '/parametres', tokAnnexe, { fuseau_horaire: 'Europe/Paris' });
    verifier('PATCH /parametres annexe fuseau_horaire : 403', patchParamsFuseau.statut === 403, patchParamsFuseau.texte);
    const patchParamsPropre = await appel('PATCH', '/parametres', tokAnnexe, { ville: 'Cocody' });
    verifier(
      'PATCH /parametres annexe ville (champ propre) : 200',
      patchParamsPropre.statut === 200 && patchParamsPropre.json?.ville === 'Cocody',
      patchParamsPropre.texte.slice(0, 200),
    );
    const patchProfilCouleur = await appel('PATCH', `/eglises/${annexeId}/profil`, tokAnnexe, {
      couleur_principale: '#123456',
    });
    verifier(
      'PATCH /eglises/:id/profil annexe couleur_principale : 403 champ hérité',
      patchProfilCouleur.statut === 403,
      patchProfilCouleur.texte,
    );
    const patchProfilLogo = await appel('PATCH', `/eglises/${annexeId}/profil`, tokAnnexe, {
      logo_url: 'https://example.com/annexe.png',
    });
    verifier('PATCH /eglises/:id/profil annexe logo_url : 403', patchProfilLogo.statut === 403, patchProfilLogo.texte);
    const patchProfilPropre = await appel('PATCH', `/eglises/${annexeId}/profil`, tokAnnexe, {
      city: 'Abobo',
    });
    verifier(
      'PATCH /eglises/:id/profil annexe ville (champ propre) : 200',
      patchProfilPropre.statut === 200 && patchProfilPropre.json?.city === 'Abobo',
      patchProfilPropre.texte.slice(0, 200),
    );
    const villeSync = (
      await direct.query(`SELECT ville FROM eglise_parametres WHERE church_id = $1`, [annexeId])
    ).rows[0];
    verifier(
      'PATCH /eglises/:id/profil annexe : ville synchronisée vers eglise_parametres',
      villeSync?.ville === 'Abobo',
      JSON.stringify(villeSync),
    );
    const postLogoAnnexe = await appel('POST', `/eglises/${annexeId}/logo`, tokAnnexe, {});
    verifier(
      'POST /eglises/:id/logo annexe : 403 champ hérité',
      postLogoAnnexe.statut === 403,
      postLogoAnnexe.texte,
    );

    // --- 9. Synchronisations côté mère --------------------------------------
    const patchParamsMere = await appel('PATCH', '/parametres', tokMere, {
      logo_url: 'https://example.com/logo-sync.png',
      devise: 'EUR',
    });
    verifier(
      'PATCH /parametres mère logo_url + devise : 200',
      patchParamsMere.statut === 200 && patchParamsMere.json?.logo_url === 'https://example.com/logo-sync.png',
      patchParamsMere.texte.slice(0, 200),
    );
    const mereSync = (
      await direct.query(`SELECT logo_url, devise FROM churches WHERE id = $1`, [mereId])
    ).rows[0];
    verifier(
      'PATCH /parametres mère : churches synchronisé (logo, devise)',
      mereSync?.logo_url === 'https://example.com/logo-sync.png' && mereSync?.devise === 'EUR',
      JSON.stringify(mereSync),
    );
    const patchProfilMere = await appel('PATCH', `/eglises/${mereId}/profil`, tokMere, {
      couleur_principale: '#AABBCC',
      address: '99 rue Sync',
    });
    verifier(
      'PATCH /eglises/:id/profil mère : 200',
      patchProfilMere.statut === 200 && patchProfilMere.json?.couleur_principale === '#AABBCC',
      patchProfilMere.texte.slice(0, 200),
    );
    const paramsMereSync = (
      await direct.query(`SELECT adresse, couleurs FROM eglise_parametres WHERE church_id = $1`, [mereId])
    ).rows[0];
    verifier(
      'PATCH /eglises/:id/profil mère : adresse et couleurs.principale synchronisés',
      paramsMereSync?.adresse === '99 rue Sync' && paramsMereSync?.couleurs?.principale === '#AABBCC',
      JSON.stringify(paramsMereSync),
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
