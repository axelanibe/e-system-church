// Test d'intégration du correctif de sécurité CRITIQUE (22/11) —
// lien de réinitialisation généré par l'admin.
//
// Périmètre : POST /auth/admin/lien-reinitialisation ne peut viser
// qu'un utilisateur de LA PROPRE église de l'admin, jamais un compte
// Plateforme (super_admin, aide_plateforme). Un e-mail inconnu ou
// hors église reçoit le même 404, sans oracle supplémentaire.
//
// Cas :
//   1. Admin A → membre de sa propre église : 200 + lien ; le jeton
//      extrait du lien permet la réinitialisation puis la connexion
//      avec le nouveau mot de passe.
//   2. Admin A → admin de l'église B : 404.
//   3. Admin A → super_admin (lié à l'église A avec le rôle
//      super_admin) : 404 — et la connexion Plateforme de ce compte
//      avec l'ancien mot de passe fonctionne toujours.
//   4. Admin A → e-mail inconnu : 404.
//   5. Membre → POST /auth/admin/lien-reinitialisation : 403.
//
// Base fraîche, application du schéma puis des migrations avec le vrai
// moteur (dist/migrate.js), démarrage de l'API, appels HTTP. Aucun vrai
// envoi.
//
// Usage (depuis la racine du dépôt, après `npm run build` dans server/) :
//   `node server/test-securite-lien-reinitialisation.mjs`
// Variables : PORT (défaut 4113). PostgreSQL local requis
// (utilisateur postgres / postgres).

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);
const JWT_SECRET = 'test-secret-lien-reinit-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const ADMIN = 'postgres://postgres:postgres@127.0.0.1:5432/postgres';
const NOM_DB = 'e_system_church_test_lien_reinit';

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
  const port = Number(process.env.PORT ?? 4113);
  const base = `http://127.0.0.1:${port}`;
  const databaseUrl = `postgres://postgres:postgres@127.0.0.1:5432/${NOM_DB}`;
  await creerBase(NOM_DB);
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL: databaseUrl },
  });

  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: {
      ...process.env,
      DATABASE_URL: databaseUrl,
      PORT: String(port),
      JWT_SECRET,
      PAYMENT_SECRETS_KEY,
    },
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

    async function appel(methode, chemin, jeton, corps, entetes = {}) {
      const reponse = await fetch(`${base}${chemin}`, {
        method: methode,
        headers: {
          'content-type': 'application/json',
          ...(jeton ? { authorization: `Bearer ${jeton}` } : {}),
          ...entetes,
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

    // --- Préparation : deux églises, un membre, un super_admin -----------
    const egliseA = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église A lien', city: 'Abidjan' },
      admin: {
        full_name: 'Admin A lien',
        email: 'admin-a-lien@example.com',
        password: 'MotDePasse123!',
      },
    });
    verifier('inscription église A', egliseA.statut === 201, egliseA.texte);
    const jetonAdminA = egliseA.json?.token;
    const egliseIdA = egliseA.json?.church?.id;

    const egliseB = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église B lien', city: 'Bouaké' },
      admin: {
        full_name: 'Admin B lien',
        email: 'admin-b-lien@example.com',
        password: 'MotDePasse123!',
      },
    });
    verifier('inscription église B', egliseB.statut === 201, egliseB.texte);

    const hash = await argon2.hash('Test1234!');
    async function creerCompte(email, role, churchId = egliseIdA) {
      const { rows } = await pool.query(
        `INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id`,
        [email, hash, email],
      );
      await pool.query(
        `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
        [rows[0].id, churchId, role],
      );
      return rows[0].id;
    }
    await creerCompte('membre-a-lien@example.com', 'membre');
    const jetonMembre = await login('membre-a-lien@example.com');

    // Super_admin lié à l'église A (le cas le plus fort : même dans sa
    // propre église, l'admin ne peut pas viser un compte Plateforme).
    const hashSuper = await argon2.hash('AncienMot123!');
    const { rows: rowsSuper } = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id`,
      ['super-admin-lien@example.com', hashSuper, 'Super Admin Lien'],
    );
    await pool.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
      [rowsSuper[0].id, egliseIdA, 'super_admin'],
    );

    async function demanderLien(jeton, email) {
      return appel('POST', '/auth/admin/lien-reinitialisation', jeton, { email });
    }

    // --- Cas 1 : membre de sa propre église → 200 + lien utilisable ------
    const r1 = await demanderLien(jetonAdminA, 'membre-a-lien@example.com');
    verifier(
      'Cas 1 : admin → membre de sa propre église → 200 + lien',
      r1.statut === 200 && typeof r1.json?.lien === 'string' && typeof r1.json?.expires_at === 'string',
      r1.texte,
    );
    const jetonReset = new URL(r1.json?.lien ?? '', base).searchParams.get('token');
    verifier('Cas 1 : jeton extrait du lien', typeof jetonReset === 'string' && jetonReset.length > 0, r1.json?.lien ?? '');
    const reset = await appel('POST', '/auth/reinitialiser-mot-de-passe', null, {
      token: jetonReset,
      mot_de_passe: 'NouveauMot123!',
    });
    verifier('Cas 1 : réinitialisation avec le jeton → 200', reset.statut === 200, reset.texte);
    const loginNouveau = await appel('POST', '/auth/login', null, {
      email: 'membre-a-lien@example.com',
      password: 'NouveauMot123!',
    });
    verifier('Cas 1 : connexion avec le nouveau mot de passe → 200', loginNouveau.statut === 200, loginNouveau.texte);

    // --- Cas 2 : admin d'une autre église → 404 ---------------------------
    const r2 = await demanderLien(jetonAdminA, 'admin-b-lien@example.com');
    verifier("Cas 2 : admin → admin de l'église B → 404", r2.statut === 404, r2.texte);

    // --- Cas 3 : super_admin → 404, compte toujours utilisable ------------
    const r3 = await demanderLien(jetonAdminA, 'super-admin-lien@example.com');
    verifier('Cas 3 : admin → super_admin → 404', r3.statut === 404, r3.texte);
    const loginSuper = await appel('POST', '/auth/login', null, {
      email: 'super-admin-lien@example.com',
      password: 'AncienMot123!',
    });
    verifier('Cas 3 : connexion Plateforme du super_admin (ancien mot de passe) → 200', loginSuper.statut === 200, loginSuper.texte);

    // --- Cas 4 : e-mail inconnu → 404 --------------------------------------
    const r4 = await demanderLien(jetonAdminA, 'inconnu-lien@example.com');
    verifier('Cas 4 : admin → e-mail inconnu → 404', r4.statut === 404, r4.texte);

    // --- Cas 5 : un membre ne peut pas générer de lien → 403 --------------
    const r5 = await demanderLien(jetonMembre, 'membre-a-lien@example.com');
    verifier('Cas 5 : membre → lien de réinitialisation → 403', r5.statut === 403, r5.texte);

    await pool.end();
  } finally {
    if (pool) await pool.end().catch(() => undefined);
    api.kill();
    await once(api, 'exit').catch(() => undefined);
    await detruireBase(NOM_DB);
  }

  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ECHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
