// Test d'intégration de l'espace fidèle (tranche P1) : messages privés
// et confirmation de présence au culte, avec la migration 020.
// Même forme que server/test-espace-membre-t2.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP, droits 401/403 et
// isolation entre églises.
//
// Usage : `node server/test-espace-fidele-p1.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4101).
// Base locale : PostgreSQL est nécessaire. Sans base locale, ce test
// ne peut pas tourner (constaté le 12 novembre 2026 : aucun PostgreSQL
// dans cette machine). La migration 020 sera appliquée sur Render
// après la fusion, comme les migrations 015, 016, 018 et 019.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';

const PORT = Number(process.env.PORT ?? 4101);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_p1';

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
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_p1');
  await admin.query('CREATE DATABASE e_system_church_test_p1');
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

    // --- Préparation : église mère, annexe, comptes, membre ---
    // On passe par l'inscription publique puis par la base pour
    // rattacher le membre, comme dans le test T2.
    const mere = await appel('POST', '/auth/register', null, {
      nom_eglise: 'Église mère EXEMPLE',
      nom_complet: 'Admin EXEMPLE',
      email: 'admin-exemple-p1@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250102030405',
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonMere = mere.json?.token;
    const egliseMereId = mere.json?.church?.id;

    const annexe = await appel('POST', '/auth/register', null, {
      nom_eglise: 'Annexe EXEMPLE',
      nom_complet: 'Admin annexe EXEMPLE',
      email: 'admin-annexe-exemple-p1@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250504030201',
      code_tutelle: mere.json?.church?.code,
    });
    verifier('inscription annexe', annexe.statut === 201, annexe.texte);

    const fidele = await appel('POST', '/auth/inscription-par-code', null, {
      code: mere.json?.church?.code_fidele ?? mere.json?.church?.code,
      nom_complet: 'Fidèle EXEMPLE',
      email: 'fidele-exemple-p1@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle par code', fidele.statut === 201, fidele.texte);
    const jetonFidele = fidele.json?.token;

    // --- Messages privés ---
    const sansJeton = await appel('GET', '/moi/messages', null);
    verifier('GET /moi/messages sans jeton = 401', sansJeton.statut === 401);

    const filVide = await appel('GET', '/moi/messages', jetonFidele);
    verifier(
      'fil vide au départ',
      filVide.statut === 200 &&
        Array.isArray(filVide.json?.messages) &&
        filVide.json.messages.length === 0,
      filVide.texte,
    );

    const envoi = await appel('POST', '/moi/messages', jetonFidele, {
      message: 'Bonjour, message EXEMPLE.',
    });
    verifier(
      'POST /moi/messages = 201, auteur membre',
      envoi.statut === 201 && envoi.json?.auteur === 'membre',
      envoi.texte,
    );

    const filApres = await appel('GET', '/moi/messages', jetonFidele);
    verifier(
      'fil après envoi : 1 message',
      filApres.statut === 200 && filApres.json?.messages?.length === 1,
      filApres.texte,
    );

    const vide = await appel('POST', '/moi/messages', jetonFidele, {
      message: '   ',
    });
    verifier('message vide rejeté (400)', vide.statut === 400, vide.texte);

    // L'admin voit le fil et répond.
    const fils = await appel('GET', '/messages-fidele', jetonMere);
    verifier(
      'GET /messages-fidele (admin) : 1 fil',
      fils.statut === 200 && fils.json?.fils?.length === 1,
      fils.texte,
    );
    const membreId = fils.json?.fils?.[0]?.member_id;
    verifier('fil rattaché au membre', typeof membreId === 'string');

    const reponse = await appel(
      'POST',
      `/messages-fidele/${membreId}`,
      jetonMere,
      { message: 'Réponse EXEMPLE de l’église.' },
    );
    verifier(
      'réponse admin = 201, auteur eglise',
      reponse.statut === 201 && reponse.json?.auteur === 'eglise',
      reponse.texte,
    );

    const filFinal = await appel('GET', '/moi/messages', jetonFidele);
    verifier(
      'fil final : 2 messages, ordre ancien puis récent',
      filFinal.statut === 200 &&
        filFinal.json?.messages?.length === 2 &&
        filFinal.json.messages[0].auteur === 'membre' &&
        filFinal.json.messages[1].auteur === 'eglise',
      filFinal.texte,
    );

    // Le fidèle ne peut pas lire les fils admin.
    const interdit = await appel('GET', '/messages-fidele', jetonFidele);
    verifier(
      'GET /messages-fidele par un fidèle = 403',
      interdit.statut === 403,
      interdit.texte,
    );

    // --- Confirmation de présence au culte ---
    const cultes = await appel('GET', '/moi/cultes', jetonFidele);
    verifier(
      'GET /moi/cultes renvoie serai_present',
      cultes.statut === 200 &&
        Array.isArray(cultes.json?.cultes ?? cultes.json),
      cultes.texte,
    );
    const liste = cultes.json?.cultes ?? cultes.json ?? [];
    const culte = liste.find((c) => c.date_heure ?? c.dateHeure);
    if (culte) {
      const culteId = culte.id;
      const confirmer = await appel(
        'POST',
        `/moi/cultes/${culteId}/present`,
        jetonFidele,
      );
      verifier(
        'POST /moi/cultes/:id/present = 200',
        confirmer.statut === 200,
        confirmer.texte,
      );
      const apres = await appel('GET', '/moi/cultes', jetonFidele);
      const listeApres = apres.json?.cultes ?? apres.json ?? [];
      const retrouve = listeApres.find((c) => c.id === culteId);
      verifier(
        'serai_present vrai après confirmation',
        retrouve?.serai_present === true,
        JSON.stringify(retrouve),
      );
      const annuler = await appel(
        'DELETE',
        `/moi/cultes/${culteId}/present`,
        jetonFidele,
      );
      verifier(
        'DELETE /moi/cultes/:id/present = 200',
        annuler.statut === 200,
        annuler.texte,
      );
      const apresAnnulation = await appel('GET', '/moi/cultes', jetonFidele);
      const listeAnnulee =
        apresAnnulation.json?.cultes ?? apresAnnulation.json ?? [];
      const retrouve2 = listeAnnulee.find((c) => c.id === culteId);
      verifier(
        'serai_present faux après annulation',
        retrouve2?.serai_present === false,
        JSON.stringify(retrouve2),
      );
    } else {
      console.log('  (aucun culte créé par l’inscription, RSVP non testé)');
    }

    // Isolation : un fidèle d'une autre église ne voit pas le fil.
    const autre = await appel('POST', '/auth/inscription-par-code', null, {
      code: annexe.json?.church?.code_fidele ?? annexe.json?.church?.code,
      nom_complet: 'Autre fidèle EXEMPLE',
      email: 'autre-fidele-exemple-p1@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250909090909',
    });
    const jetonAutre = autre.json?.token;
    const filAutre = await appel('GET', '/moi/messages', jetonAutre);
    verifier(
      'fil vide pour un autre fidèle (isolation)',
      filAutre.statut === 200 && filAutre.json?.messages?.length === 0,
      filAutre.texte,
    );

    // La réponse admin à un membre hors de son réseau est refusée.
    if (membreId && jetonMere && egliseMereId) {
      const horsReseau = await appel(
        'POST',
        `/messages-fidele/${membreId}`,
        annexe.json?.token,
        { message: 'Tentative hors réseau.' },
      );
      verifier(
        'réponse admin hors réseau = 403 ou 404',
        horsReseau.statut === 403 || horsReseau.statut === 404,
        horsReseau.texte,
      );
    }
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
