// Test d'intégration des rapports à mon église mère (tranche P5) :
// contact de l'église mère, envoi d'un rapport par une annexe,
// lecture des rapports reçus par la mère, avec la migration 023.
// Même forme que server/test-abonnements-p3.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP, droits 401/403.
//
// Usage : `node server/test-rapports-annexe-p5.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4105).
// Base locale : PostgreSQL est nécessaire. Sans base locale, ce test
// ne peut pas tourner (constaté le 12 novembre 2026 : aucun PostgreSQL
// dans cette machine). La migration 023 sera appliquée sur Render
// après la fusion, comme les migrations 015, 016, 018, 019, 020 et 021.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';

const PORT = Number(process.env.PORT ?? 4105);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_p5';

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
  // Base fraîche.
  const admin = new Client({
    connectionString: 'postgres://postgres:postgres@127.0.0.1:5432/postgres',
  });
  await admin.connect();
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_p5');
  await admin.query('CREATE DATABASE e_system_church_test_p5');
  await admin.end();

  // Schéma + migrations avec le vrai moteur.
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const exec = promisify(execFile);
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL },
  });

  // Démarrage de l'API.
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, PORT: String(PORT) },
    stdio: 'pipe',
  });
  try {
    // Attente de /sante.
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

    // --- Préparation : église mère et annexe ---
    const mere = await appel('POST', '/auth/register', null, {
      nom_eglise: 'Église mère EXEMPLE',
      nom_complet: 'Admin EXEMPLE',
      email: 'admin-exemple-p5@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250102030405',
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonMere = mere.json?.token;

    const annexe = await appel('POST', '/auth/register', null, {
      nom_eglise: 'Annexe EXEMPLE',
      nom_complet: 'Admin annexe EXEMPLE',
      email: 'admin-annexe-exemple-p5@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250504030201',
      code_tutelle: mere.json?.church?.code,
    });
    verifier('inscription annexe', annexe.statut === 201, annexe.texte);
    const jetonAnnexe = annexe.json?.token;

    // --- GET /moi/eglise-mere ---
    const sansJeton = await appel('GET', '/moi/eglise-mere', null);
    verifier(
      'GET /moi/eglise-mere sans jeton = 401',
      sansJeton.statut === 401,
    );

    const mereAnnexe = await appel('GET', '/moi/eglise-mere', jetonAnnexe);
    verifier(
      'annexe : mère nommée, e-mail nul (À compléter)',
      mereAnnexe.statut === 200 &&
        mereAnnexe.json?.nom === 'Église mère EXEMPLE' &&
        mereAnnexe.json?.email === null,
      mereAnnexe.texte,
    );

    // --- POST /moi/rapports-annexe ---
    const envoiMere = await appel('POST', '/moi/rapports-annexe', jetonMere, {
      type: 'bilan_annuel',
      membres: 0,
      recettes_fcfa: 0,
      depenses_fcfa: 0,
      solde_fcfa: 0,
    });
    verifier(
      'une mère n’envoie pas de rapport à elle-même = 403',
      envoiMere.statut === 403,
      envoiMere.texte,
    );

    const envoiType = await appel(
      'POST',
      '/moi/rapports-annexe',
      jetonAnnexe,
      {
        type: 'bilan_inventé',
        membres: 0,
        recettes_fcfa: 0,
        depenses_fcfa: 0,
        solde_fcfa: 0,
      },
    );
    verifier(
      'type de rapport invalide = 400',
      envoiType.statut === 400,
      envoiType.texte,
    );

    const envoi = await appel('POST', '/moi/rapports-annexe', jetonAnnexe, {
      type: 'bilan_annuel',
      message: 'Message EXEMPLE',
      membres: 0,
      recettes_fcfa: 0,
      depenses_fcfa: 0,
      solde_fcfa: 0,
    });
    verifier(
      'annexe : rapport enregistré, en attente d’envoi par e-mail',
      envoi.statut === 200 &&
        envoi.json?.type === 'bilan_annuel' &&
        envoi.json?.statut === 'en_attente_envoi' &&
        envoi.json?.envoi_email === 'en_attente_lot_b',
      envoi.texte,
    );

    // --- GET /moi/rapports-annexe/recus ---
    const recusAnnexe = await appel(
      'GET',
      '/moi/rapports-annexe/recus',
      jetonAnnexe,
    );
    verifier(
      'une annexe ne lit pas les rapports reçus = 403',
      recusAnnexe.statut === 403,
      recusAnnexe.texte,
    );

    const recus = await appel(
      'GET',
      '/moi/rapports-annexe/recus',
      jetonMere,
    );
    verifier(
      'mère : un rapport reçu, avec le nom de l’annexe',
      recus.statut === 200 &&
        Array.isArray(recus.json) &&
        recus.json.length === 1 &&
        recus.json[0]?.type === 'bilan_annuel' &&
        recus.json[0]?.eglise_nom === 'Annexe EXEMPLE' &&
        recus.json[0]?.statut === 'en_attente_envoi',
      recus.texte,
    );
  } finally {
    api.kill();
    await once(api, 'exit').catch(() => {});
  }
  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ÉCHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
