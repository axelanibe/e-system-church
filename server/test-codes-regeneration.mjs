// Test d'intégration de la régénération des codes d'invitation
// (branche codes-regeneration).
//
// Périmètre : POST /eglises/moi/codes/regenerer (admin de sa propre
// église, body {type: "fidele" | "tutelle"}) — nouveau code différent,
// ancien code invalide (inscription fidèle, rattachement, présentation
// publique), unicité du suffixe à 4 chiffres entre les deux colonnes et
// les églises, erreurs 400/401/403, journalisation sans valeur de code.
//
// Note 404 : la branche 404 de la route est défensive et inaccessible
// par HTTP — requireAuth exige une ligne church_users (user, église),
// et church_users.church_id est ON DELETE CASCADE : supprimer l'église
// supprime l'appartenance, donc requireAuth répond 401 avant la route.
// Elle n'est donc pas testée par HTTP ici (vérifiée par lecture).
//
// Base fraîche, application du schéma puis des migrations avec le vrai
// moteur (dist/migrate.js), démarrage de l'API, appels HTTP, droits
// 401/403 et isolation entre églises. Aucun vrai envoi.
//
// Usage (depuis la racine du dépôt, après `npm run build` dans server/) :
//   `node server/test-codes-regeneration.mjs`
// Variables : PORT (défaut 4110). PostgreSQL local requis
// (utilisateur postgres / postgres).

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);
const JWT_SECRET = process.env.JWT_SECRET ?? 'a'.repeat(32);
const ADMIN = 'postgres://postgres:postgres@127.0.0.1:5432/postgres';
const NOM_DB = 'e_system_church_test_regen';

let echecs = 0;
function verifier(nom, condition, detail = '') {
  if (condition) {
    console.log(`  OK ${nom}`);
  } else {
    echecs += 1;
    console.log(`  ECHEC ${nom} ${detail}`);
  }
}

async function creerBase(nomDb) {
  const admin = new Client({ connectionString: ADMIN });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${nomDb}`);
  await admin.query(`CREATE DATABASE ${nomDb}`);
  await admin.end();
}

async function detruireBase(nomDb) {
  const admin = new Client({ connectionString: ADMIN });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${nomDb}`);
  await admin.end();
}

async function main() {
  const port = Number(process.env.PORT ?? 4110);
  const base = `http://127.0.0.1:${port}`;
  const databaseUrl = `postgres://postgres:postgres@127.0.0.1:5432/${NOM_DB}`;
  await creerBase(NOM_DB);
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL: databaseUrl },
  });
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL: databaseUrl, PORT: String(port), JWT_SECRET },
    stdio: 'pipe',
  });
  let pool = null;
  try {
    let pret = false;
    for (let i = 0; i < 30 && !pret; i += 1) {
      await sleep(500);
      try {
        const r = await fetch(`${base}/sante`);
        pret = r.ok;
      } catch {
        pret = false;
      }
    }
    verifier('API démarrée (/sante)', pret);
    if (!pret) return;

    const poolClient = new Client({ connectionString: databaseUrl });
    await poolClient.connect();
    pool = poolClient;

    async function appel(methode, chemin, jeton, corps) {
      const reponse = await fetch(`${base}${chemin}`, {
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

    async function login(email, motDePasse = 'Test1234!') {
      const r = await appel('POST', '/auth/login', null, { email, password: motDePasse });
      if (r.statut !== 200) throw new Error(`login ${email}: ${r.texte}`);
      return r.json.token;
    }

    async function inscrireEglise(nom, email) {
      const r = await appel('POST', '/auth/register', null, {
        eglise: { name: nom, city: 'Abidjan' },
        admin: { full_name: `Admin ${nom}`, email, password: 'Test1234!' },
      });
      if (r.statut !== 201) throw new Error(`inscription ${nom}: ${r.texte}`);
      return r.json;
    }

    // --- Préparation : deux églises, rôles ---------------------------------
    const mere = await inscrireEglise('Église mère Regen', 'admin-mere-regen@example.com');
    const jetonAdmin = mere.token;
    const egliseId = mere.church.id;
    const codeTutelleInitial = mere.church.code;
    const codeFideleInitial = mere.church.code_fidele;
    verifier('inscription église mère (codes initiaux)', Boolean(codeTutelleInitial) && Boolean(codeFideleInitial), mere.texte ?? '');

    const autre = await inscrireEglise('Autre église Regen', 'admin-autre-regen@example.com');
    const jetonAutreAdmin = autre.token;
    const codeTutelleAutre = autre.church.code;
    const codeFideleAutre = autre.church.code_fidele;

    const hash = await argon2.hash('Test1234!');
    async function creerCompte(email, role) {
      const { rows } = await pool.query(
        `INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id`,
        [email, hash, email],
      );
      await pool.query(
        `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
        [rows[0].id, egliseId, role],
      );
    }
    await creerCompte('tresorier-regen@example.com', 'tresorier');
    await creerCompte('membre-regen@example.com', 'membre');
    const jetonTresorier = await login('tresorier-regen@example.com');
    const jetonMembre = await login('membre-regen@example.com');

    async function regenerer(jeton, corps) {
      return appel('POST', '/eglises/moi/codes/regenerer', jeton, corps);
    }

    // --- A. Régénération du code fidèle -------------------------------------
    console.log('A. Régénération du code fidèle :');
    const regenFidele = await regenerer(jetonAdmin, { type: 'fidele' });
    const nouveauFidele = regenFidele.json?.nouveau_code;
    verifier(
      'admin régénère le code fidèle : 200, format ESC-F-XXXX, différent, tutelle inchangée',
      regenFidele.statut === 200 &&
        /^ESC-F-\d{4}$/.test(nouveauFidele ?? '') &&
        nouveauFidele !== codeFideleInitial &&
        regenFidele.json?.code === codeTutelleInitial &&
        regenFidele.json?.code_fidele === nouveauFidele,
      regenFidele.texte,
    );
    verifier(
      'suffixe unique : différent des deux codes de l’autre église',
      nouveauFidele.slice(-4) !== codeTutelleAutre.slice(-4) &&
        nouveauFidele.slice(-4) !== codeFideleAutre.slice(-4),
    );

    const inscriptionAncien = await appel('POST', '/auth/inscription-par-code', null, {
      nom_prenom: 'Ancien Code Regen',
      email: 'ancien-code-regen@example.com',
      telephone: '+2250700000001',
      mot_de_passe: 'Test1234!',
      code_eglise: codeFideleInitial,
    });
    verifier(
      'ancien code fidèle : inscription 404 invalid_code',
      inscriptionAncien.statut === 404 && inscriptionAncien.json?.error === 'invalid_code',
      inscriptionAncien.texte,
    );

    const inscriptionNouveau = await appel('POST', '/auth/inscription-par-code', null, {
      nom_prenom: 'Nouveau Code Regen',
      email: 'nouveau-code-regen@example.com',
      telephone: '+2250700000002',
      mot_de_passe: 'Test1234!',
      code_eglise: nouveauFidele,
    });
    verifier(
      'nouveau code fidèle : inscription 201 dans la bonne église',
      inscriptionNouveau.statut === 201 && inscriptionNouveau.json?.church?.id === egliseId,
      inscriptionNouveau.texte,
    );

    const regenFidele2 = await regenerer(jetonAdmin, { type: 'fidele' });
    verifier(
      'deuxième régénération fidèle : nouveau code encore différent',
      regenFidele2.statut === 200 &&
        /^ESC-F-\d{4}$/.test(regenFidele2.json?.nouveau_code ?? '') &&
        regenFidele2.json?.nouveau_code !== nouveauFidele,
      regenFidele2.texte,
    );

    // --- B. Régénération du code de tutelle ---------------------------------
    console.log('B. Régénération du code de tutelle :');
    const regenTutelle = await regenerer(jetonAdmin, { type: 'tutelle' });
    const nouveauTutelle = regenTutelle.json?.nouveau_code;
    verifier(
      'admin régénère le code de tutelle : 200, format ESC-XXXX, différent, fidèle inchangé',
      regenTutelle.statut === 200 &&
        /^ESC-\d{4}$/.test(nouveauTutelle ?? '') &&
        nouveauTutelle !== codeTutelleInitial &&
        regenTutelle.json?.code === nouveauTutelle &&
        regenTutelle.json?.code_fidele === regenFidele2.json?.nouveau_code,
      regenTutelle.texte,
    );

    const rattachementAncien = await appel('POST', '/rattachements', jetonAutreAdmin, {
      parent_code: codeTutelleInitial,
    });
    verifier(
      'ancien code de tutelle : rattachement 400 invalid_parent',
      rattachementAncien.statut === 400 && rattachementAncien.json?.error === 'invalid_parent',
      rattachementAncien.texte,
    );

    const rattachementNouveau = await appel('POST', '/rattachements', jetonAutreAdmin, {
      parent_code: nouveauTutelle,
    });
    verifier(
      'nouveau code de tutelle : rattachement 201',
      rattachementNouveau.statut === 201,
      rattachementNouveau.texte,
    );

    const presentationAncienne = await appel('GET', `/eglises/${codeTutelleInitial}/presentation`, null);
    verifier(
      'ancien code de tutelle : présentation publique 404',
      presentationAncienne.statut === 404,
      presentationAncienne.texte,
    );
    const presentationNouvelle = await appel('GET', `/eglises/${nouveauTutelle}/presentation`, null);
    verifier(
      'nouveau code de tutelle : présentation publique 200',
      presentationNouvelle.statut === 200 && presentationNouvelle.json?.eglise?.id === egliseId,
      presentationNouvelle.texte,
    );

    // --- C. Erreurs 400 / 401 / 403 ------------------------------------------
    console.log('C. Erreurs :');
    const typeInvalide = await regenerer(jetonAdmin, { type: 'autre' });
    verifier('type invalide : 400', typeInvalide.statut === 400, typeInvalide.texte);
    const sansCorps = await regenerer(jetonAdmin, undefined);
    verifier('sans body : 400', sansCorps.statut === 400, sansCorps.texte);
    const sansJeton = await regenerer(null, { type: 'fidele' });
    verifier('sans jeton : 401', sansJeton.statut === 401, sansJeton.texte);
    const tresorier = await regenerer(jetonTresorier, { type: 'fidele' });
    verifier('trésorier : 403', tresorier.statut === 403, tresorier.texte);
    const membre = await regenerer(jetonMembre, { type: 'fidele' });
    verifier('simple membre : 403', membre.statut === 403, membre.texte);

    // --- D. Journalisation : le type seulement, jamais les valeurs -----------
    console.log('D. Journalisation :');
    const { rows: audits } = await pool.query(
      `SELECT action, details FROM audit_logs WHERE church_id = $1 AND action = 'eglise.code_regenere' ORDER BY created_at ASC`,
      [egliseId],
    );
    verifier('3 régénérations journalisées', audits.length === 3, `trouvé ${audits.length}`);
    const valeursInterdites = [
      codeTutelleInitial, codeFideleInitial, nouveauFidele,
      regenFidele2.json?.nouveau_code, nouveauTutelle,
    ].filter(Boolean);
    const detailsPropres = audits.every((a) => {
      const texte = JSON.stringify(a.details);
      const typeSeul = a.details && typeof a.details === 'object' && Object.keys(a.details).length === 1 && ['fidele', 'tutelle'].includes(a.details.type);
      return typeSeul && !valeursInterdites.some((v) => texte.includes(v));
    });
    verifier('audit : type seulement, aucune valeur de code', detailsPropres, JSON.stringify(audits.map((a) => a.details)));
  } finally {
    api.kill();
    await once(api, 'exit').catch(() => undefined);
    if (pool) await pool.end().catch(() => undefined);
    await detruireBase(NOM_DB);
  }
}

main()
  .then(() => {
    console.log(echecs === 0 ? 'TOUT EST OK' : `${echecs} ÉCHEC(S)`);
    process.exit(echecs === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('ERREUR FATALE', e);
    process.exit(1);
  });
