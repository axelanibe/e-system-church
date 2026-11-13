// Test d'intégration des rapports à mon église mère (tranche P5) :
// contact de l'église mère, envoi d'un rapport par une annexe,
// lecture des rapports reçus par la mère, avec la migration 023.
// Même forme que server/test-abonnements-p3.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP, droits 401/403.
//
// Lot B (tranche P5, envoi par courriel) : la mère n'a pas d'adresse
// e-mail en base dans ce test, donc l'envoi ne peut pas partir — le
// rapport reste en_attente_envoi avec envoi_email=email_mere_manquant.
// Le cas nominal (envoi réussi, statut envoye) est couvert par
// server/test-lot-b-p5-envoi-courriel.mjs (transport simulé).
//
// Usage : `node server/test-rapports-annexe-p5.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4105).

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

  // Démarrage de l'API (JWT_SECRET requis : 32 caractères minimum).
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: {
      ...process.env,
      DATABASE_URL,
      PORT: String(PORT),
      JWT_SECRET:
        process.env.JWT_SECRET ?? 'test-secret-rapports-p5-32-caracteres',
    },
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
    // Inscription au format actuel (schéma imbriqué eglise/admin) ;
    // l'annexe rejoint la mère par son code, puis la mère accepte le
    // rattachement (sinon l'annexe reste sa propre racine).
    const mere = await appel('POST', '/auth/register', null, {
      eglise: {
        name: 'Église mère EXEMPLE',
        city: 'Abidjan',
        phone: '+2250102030405',
      },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-p5@example.com',
        password: 'MotDePasse123!',
      },
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonMere = mere.json?.token;

    const annexe = await appel('POST', '/auth/register', null, {
      eglise: {
        name: 'Annexe EXEMPLE',
        city: 'Abidjan',
        phone: '+2250504030201',
        parent_code: mere.json?.church?.code,
      },
      admin: {
        full_name: 'Admin annexe EXEMPLE',
        email: 'admin-annexe-exemple-p5@example.com',
        password: 'MotDePasse123!',
      },
    });
    verifier('inscription annexe', annexe.statut === 201, annexe.texte);
    const jetonAnnexe = annexe.json?.token;

    const acceptation = await appel(
      'POST',
      `/rattachements/${annexe.json?.rattachement?.id}/accepter`,
      jetonMere,
    );
    verifier(
      'mère : rattachement de l’annexe accepté',
      acceptation.statut === 200 &&
        acceptation.json?.status === 'acceptee',
      acceptation.texte,
    );

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
      'annexe : rapport enregistré, en attente d’envoi par e-mail (mère sans adresse)',
      envoi.statut === 200 &&
        envoi.json?.type === 'bilan_annuel' &&
        envoi.json?.statut === 'en_attente_envoi' &&
        envoi.json?.envoi_email === 'email_mere_manquant',
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
