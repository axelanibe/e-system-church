// Test d'intégration du rendez-vous membre (tranche P4) : demande de
// rendez-vous auprès du pasteur, avec la migration 022.
// Même forme que server/test-espace-fidele-p1.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP, droits 401/403 et
// isolation entre églises.
//
// Usage : `node server/test-rendez-vous-p4.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4102).
// Base locale : PostgreSQL est nécessaire. Sans base locale, ce test
// ne peut pas tourner (constaté le 12 novembre 2026 : aucun PostgreSQL
// dans cette machine). La migration 022 sera appliquée sur Render
// après la fusion, comme les migrations 015, 016, 018, 019 et 020.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';

const PORT = Number(process.env.PORT ?? 4102);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_p4';

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
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_p4');
  await admin.query('CREATE DATABASE e_system_church_test_p4');
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

    // --- Préparation : église mère, compte, membre ---
    const mere = await appel('POST', '/auth/register', null, {
      nom_eglise: 'Église mère EXEMPLE',
      nom_complet: 'Admin EXEMPLE',
      email: 'admin-exemple-p4@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250102030405',
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);

    const fidele = await appel('POST', '/auth/inscription-par-code', null, {
      code: mere.json?.church?.code_fidele ?? mere.json?.church?.code,
      nom_complet: 'Fidèle EXEMPLE',
      email: 'fidele-exemple-p4@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle par code', fidele.statut === 201, fidele.texte);
    const jetonFidele = fidele.json?.token;

    // --- Demandes de rendez-vous ---
    const sansJeton = await appel('GET', '/moi/rendez-vous', null);
    verifier('GET /moi/rendez-vous sans jeton = 401', sansJeton.statut === 401);

    const listeVide = await appel('GET', '/moi/rendez-vous', jetonFidele);
    verifier(
      'liste vide au départ',
      listeVide.statut === 200 &&
        Array.isArray(listeVide.json?.rendez_vous) &&
        listeVide.json.rendez_vous.length === 0,
      listeVide.texte,
    );

    const demain = new Date(Date.now() + 86400000)
      .toISOString()
      .substring(0, 10);
    const demande = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: demain,
      motif: 'Motif EXEMPLE de rendez-vous.',
    });
    verifier(
      'POST /moi/rendez-vous = 201, statut en_attente',
      demande.statut === 201 &&
        demande.json?.rendez_vous?.statut === 'en_attente' &&
        demande.json?.rendez_vous?.date_souhaitee?.substring(0, 10) === demain,
      demande.texte,
    );

    const listeApres = await appel('GET', '/moi/rendez-vous', jetonFidele);
    verifier(
      'liste après demande : 1 rendez-vous',
      listeApres.statut === 200 &&
        listeApres.json?.rendez_vous?.length === 1,
      listeApres.texte,
    );

    const sansMotif = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: demain,
      motif: '   ',
    });
    verifier('motif vide rejeté (400)', sansMotif.statut === 400, sansMotif.texte);

    const sansDate = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      motif: 'Motif EXEMPLE.',
    });
    verifier('date manquante rejetée (400)', sansDate.statut === 400, sansDate.texte);

    const hier = new Date(Date.now() - 86400000)
      .toISOString()
      .substring(0, 10);
    const datePassee = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: hier,
      motif: 'Motif EXEMPLE.',
    });
    verifier('date passée rejetée (400)', datePassee.statut === 400, datePassee.texte);

    // Isolation : un fidèle d'une autre église ne voit pas la demande.
    const autre = await appel('POST', '/auth/inscription-par-code', null, {
      code: mere.json?.church?.code_fidele ?? mere.json?.church?.code,
      nom_complet: 'Autre fidèle EXEMPLE',
      email: 'autre-fidele-exemple-p4@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250909090909',
    });
    const jetonAutre = autre.json?.token;
    const listeAutre = await appel('GET', '/moi/rendez-vous', jetonAutre);
    verifier(
      'liste vide pour un autre fidèle (isolation)',
      listeAutre.statut === 200 &&
        listeAutre.json?.rendez_vous?.length === 0,
      listeAutre.texte,
    );
  } finally {
    api.kill();
    await once(api, 'exit').catch(() => undefined);
  }

  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ECHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
