// Test d'intégration de Mon abonnement (tranche P3) : lecture de
// l'abonnement de l'église mère, vue annexe couverte par la mère, et
// validation d'un code promo, avec la migration 021.
// Même forme que server/test-espace-fidele-p1.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP, droits 401/403.
//
// Usage : `node server/test-abonnements-p3.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4103).
// Base locale : PostgreSQL est nécessaire. Sans base locale, ce test
// ne peut pas tourner (constaté le 12 novembre 2026 : aucun PostgreSQL
// dans cette machine). La migration 021 sera appliquée sur Render
// après la fusion, comme les migrations 015, 016, 018, 019 et 020.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';

const PORT = Number(process.env.PORT ?? 4103);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_p3';

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
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_p3');
  await admin.query('CREATE DATABASE e_system_church_test_p3');
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
      email: 'admin-exemple-p3@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250102030405',
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonMere = mere.json?.token;
    const egliseMereId = mere.json?.church?.id;

    const annexe = await appel('POST', '/auth/register', null, {
      nom_eglise: 'Annexe EXEMPLE',
      nom_complet: 'Admin annexe EXEMPLE',
      email: 'admin-annexe-exemple-p3@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250504030201',
      code_tutelle: mere.json?.church?.code,
    });
    verifier('inscription annexe', annexe.statut === 201, annexe.texte);
    const jetonAnnexe = annexe.json?.token;

    // --- GET /moi/abonnement ---
    const sansJeton = await appel('GET', '/moi/abonnement', null);
    verifier('GET /moi/abonnement sans jeton = 401', sansJeton.statut === 401);

    const aboMere = await appel('GET', '/moi/abonnement', jetonMere);
    verifier(
      'mère sans ligne : actif, 200 000, expiration nulle',
      aboMere.statut === 200 &&
        aboMere.json?.est_annexe === false &&
        aboMere.json?.abonnement?.statut === 'actif' &&
        aboMere.json?.abonnement?.montant_fcfa === 200000 &&
        aboMere.json?.abonnement?.date_expiration === null &&
        aboMere.json?.abonnement?.lecture_seule === false,
      aboMere.texte,
    );

    const aboAnnexe = await appel('GET', '/moi/abonnement', jetonAnnexe);
    verifier(
      'annexe couverte par la mère, sans abonnement propre',
      aboAnnexe.statut === 200 &&
        aboAnnexe.json?.est_annexe === true &&
        aboAnnexe.json?.abonnement === null &&
        typeof aboAnnexe.json?.eglise_mere_nom === 'string',
      aboAnnexe.texte,
    );

    // Ligne d'abonnement expirée depuis plus de 30 jours : lecture seule.
    const base = new Client({ connectionString: DATABASE_URL });
    await base.connect();
    await base.query(
      `INSERT INTO abonnements
         (church_id, plan, duree_annees, montant_fcfa, statut,
          date_debut, date_expiration)
       VALUES ($1, 'annuel', 1, 200000, 'expire',
               '2025-01-01', '2025-06-01')`,
      [egliseMereId],
    );

    // --- POST /moi/abonnement/code-promo ---
    const codeInconnu = await appel(
      'POST',
      '/moi/abonnement/code-promo',
      jetonMere,
      { code: 'INCONNU', duree_annees: 1 },
    );
    verifier(
      'code inconnu = 404',
      codeInconnu.statut === 404,
      codeInconnu.texte,
    );

    const dureeInvalide = await appel(
      'POST',
      '/moi/abonnement/code-promo',
      jetonMere,
      { code: 'LANCEMENT10', duree_annees: 5 },
    );
    verifier(
      'durée invalide = 400',
      dureeInvalide.statut === 400,
      dureeInvalide.texte,
    );

    await base.query(
      `INSERT INTO codes_promo (code, type_reduction, valeur)
       VALUES ('LANCEMENT10', 'pourcentage', 10)`,
    );
    const codeValide = await appel(
      'POST',
      '/moi/abonnement/code-promo',
      jetonMere,
      { code: 'lancement10', duree_annees: 1 },
    );
    verifier(
      'code valide, insensible à la casse : 200 000 → 180 000',
      codeValide.statut === 200 &&
        codeValide.json?.valide === true &&
        codeValide.json?.total_avant === 200000 &&
        codeValide.json?.total_apres === 180000,
      codeValide.texte,
    );

    await base.query(
      `INSERT INTO codes_promo (code, type_reduction, valeur, actif)
       VALUES ('FIXE50000', 'montant', 50000, false)`,
    );
    const codeInactif = await appel(
      'POST',
      '/moi/abonnement/code-promo',
      jetonMere,
      { code: 'FIXE50000', duree_annees: 3 },
    );
    verifier(
      'code inactif = 404',
      codeInactif.statut === 404,
      codeInactif.texte,
    );

    const aboExpire = await appel('GET', '/moi/abonnement', jetonMere);
    verifier(
      'abonnement expiré : lecture_seule vraie',
      aboExpire.statut === 200 &&
        aboExpire.json?.abonnement?.statut === 'expire' &&
        aboExpire.json?.abonnement?.lecture_seule === true,
      aboExpire.texte,
    );
    await base.end();
  } finally {
    api.kill();
    await once(api, 'exit').catch(() => undefined);
  }

  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ÉCHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
