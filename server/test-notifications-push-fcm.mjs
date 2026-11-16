// Test d'intégration de la tranche Notifications push FCM (lot serveur) :
// migration 035 (table device_tokens, idempotence), routes POST / GET /
// DELETE /messagerie/jetons avec isolation par église et par membre,
// envoi FCM simulé au bon destinataire (transport de test, sans appeler
// FCM réellement), jeton invalide marqué inactif, et absence de panne
// quand le compte de service Firebase est absent (message créé
// normalement). Même forme que server/test-messagerie-t0.mjs : base
// fraîche créée puis vidée par le test lui-même, application du schéma
// puis des migrations avec le vrai moteur de migration, démarrage de
// l'API, appels HTTP, plus des vérifications en processus sur le module
// compilé dist/fcm.js (jamais src).
//
// Usage : `node server/test-notifications-push-fcm.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4113).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_push_fcm.
// Base locale : PostgreSQL est nécessaire.
// Aucun appel FCM réel : le compte de service n'est jamais configuré
// pour l'API lancée ici, et l'envoi simulé passe par un transport de
// test en processus.

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Client, Pool } from 'pg';
import argon2 from 'argon2';
import {
  notifierNouveauMessage,
  definirTransportFcmPourTest,
  reinitialiserFcmPourTest,
} from './dist/fcm.js';

const exec = promisify(execFile);

const PORT = Number(process.env.PORT ?? 4113);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_push_fcm';
// Nom de la base visée par DATABASE_URL : c'est elle que le test recrée.
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0.mjs).
const JWT_SECRET = 'test-jwt-secret-pour-t11-seulement-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

// Jetons FCM factices (format plausible, jamais des jetons réels).
const JETON_FIDELE_A = `fcm-jeton-test-fidele-a-${'a'.repeat(140)}`;
const JETON_FIDELE_A_2 = `fcm-jeton-test-fidele-a-2-${'b'.repeat(140)}`;
const JETON_ADMIN_A = `fcm-jeton-test-admin-a-${'c'.repeat(140)}`;
const JETON_FIDELE_B = `fcm-jeton-test-fidele-b-${'d'.repeat(140)}`;

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

  // Schéma + migrations avec le vrai moteur.
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, JWT_SECRET, PAYMENT_SECRETS_KEY },
  });

  // Démarrage de l'API, sans compte de service Firebase : l'envoi FCM
  // doit être désactivé proprement. Sortie capturée pour vérifier le
  // journal « FCM désactivé ».
  let sortieApi = '';
  const envApi = { ...process.env, DATABASE_URL, PORT: String(PORT), JWT_SECRET, PAYMENT_SECRETS_KEY };
  delete envApi.FIREBASE_SERVICE_ACCOUNT_JSON;
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: envApi,
    stdio: 'pipe',
  });
  api.stdout.on('data', (d) => { sortieApi += d.toString(); });
  api.stderr.on('data', (d) => { sortieApi += d.toString(); });
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

    // --- 1. Migration 035 (requêtes directes en base) ----------------------
    const direct = new Client({ connectionString: DATABASE_URL });
    await direct.connect();
    const table = await direct.query(
      `SELECT column_name, data_type FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'device_tokens'`,
    );
    const colonnes = new Set(table.rows.map((r) => r.column_name));
    verifier(
      'migration 035 : table device_tokens avec les 8 colonnes',
      table.rowCount === 8 &&
        ['id', 'member_id', 'church_id', 'token', 'platform', 'created_at', 'last_used_at', 'is_active']
          .every((c) => colonnes.has(c)),
      `reçu ${table.rowCount} colonnes : ${[...colonnes].join(', ')}`,
    );
    const unique = await direct.query(
      `SELECT indexname FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'device_tokens'
          AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%(token)%'`,
    );
    verifier('migration 035 : contrainte d\u2019unicité sur le jeton', unique.rowCount === 1, `reçu ${unique.rowCount}`);
    const index = await direct.query(
      `SELECT indexname FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_device_tokens_church_member'`,
    );
    verifier('migration 035 : index (church_id, member_id)', index.rowCount === 1, `reçu ${index.rowCount}`);
    const rls = await direct.query(
      `SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'device_tokens' AND c.relrowsecurity`,
    );
    verifier('migration 035 : RLS activée sur device_tokens', rls.rowCount === 1);
    const politique = await direct.query(
      `SELECT 1 FROM pg_policies WHERE policyname = 'isolement_eglise' AND tablename = 'device_tokens'`,
    );
    verifier('migration 035 : politique isolement_eglise', politique.rowCount === 1);
    const migration = await direct.query(
      `SELECT 1 FROM schema_migrations WHERE name = '035_jetons_appareil_fcm'`,
    );
    verifier('migration 035 enregistrée dans schema_migrations', migration.rowCount === 1);
    // Idempotence : le fichier 035 appliqué deux fois de suite ne doit
    // rien changer et ne pas échouer.
    const sql035 = readFileSync(
      fileURLToPath(new URL('../db/migrations/035_jetons_appareil_fcm.sql', import.meta.url)),
      'utf8',
    );
    let rejouable = true;
    let detailRejeu = '';
    try {
      await direct.query(sql035);
      await direct.query(sql035);
    } catch (e) {
      rejouable = false;
      detailRejeu = String(e?.message ?? e);
    }
    verifier('migration 035 rejouée deux fois sans erreur', rejouable, detailRejeu);
    const lignes = await direct.query(`SELECT count(*)::int AS n FROM device_tokens`);
    verifier('migration 035 rejouée : table toujours vide', lignes.rows[0]?.n === 0, `reçu ${lignes.rows[0]?.n}`);
    await direct.end();

    // --- 2. Préparation par API : deux églises, quatre comptes -------------
    // Même motif que test-messagerie-t0.mjs (inscription église, fidèle
    // par code, fiches membres, liaison users.member_id).
    const mereA = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan', phone: '+2250102030405' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-push@example.com',
        phone: '+2250102030405',
        password: 'MotDePasse123!',
      },
      channel: 'web',
    });
    verifier('inscription église A', mereA.statut === 201, mereA.texte);
    const jetonAdminA = mereA.json?.token;
    const egliseAId = mereA.json?.church?.id;
    const adminAUserId = mereA.json?.user?.id;

    const fideleA = await appel('POST', '/auth/inscription-par-code', null, {
      code_eglise: mereA.json?.church?.code_fidele ?? mereA.json?.church?.code,
      nom_prenom: 'Fidèle EXEMPLE',
      email: 'fidele-exemple-push@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle A par code', fideleA.statut === 201, fideleA.texte);
    const jetonFideleA = fideleA.json?.token;
    const fideleAUserId = fideleA.json?.user?.id;

    const mereB = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Autre église EXEMPLE', city: 'Abidjan', phone: '+2250102030406' },
      admin: {
        full_name: 'Autre Admin EXEMPLE',
        email: 'admin-exemple-push-autre@example.com',
        phone: '+2250102030406',
        password: 'MotDePasse123!',
      },
      channel: 'web',
    });
    verifier('inscription église B', mereB.statut === 201, mereB.texte);
    const jetonAdminB = mereB.json?.token;
    const egliseBId = mereB.json?.church?.id;
    const adminBUserId = mereB.json?.user?.id;

    const fideleB = await appel('POST', '/auth/inscription-par-code', null, {
      code_eglise: mereB.json?.church?.code_fidele ?? mereB.json?.church?.code,
      nom_prenom: 'Autre Fidèle EXEMPLE',
      email: 'fidele-exemple-push-autre@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080919',
    });
    verifier('inscription fidèle B par code', fideleB.statut === 201, fideleB.texte);
    const jetonFideleB = fideleB.json?.token;
    const fideleBUserId = fideleB.json?.user?.id;

    const fiches = [
      { jeton: jetonAdminA, userId: adminAUserId, nom: 'Admin EXEMPLE', phone: '+2250708080910', email: 'admin-exemple-push@example.com' },
      { jeton: jetonAdminA, userId: fideleAUserId, nom: 'Fidèle EXEMPLE', phone: '+2250708080911', email: 'fidele-exemple-push@example.com' },
      { jeton: jetonAdminB, userId: adminBUserId, nom: 'Autre Admin EXEMPLE', phone: '+2250708080920', email: 'admin-exemple-push-autre@example.com' },
      { jeton: jetonAdminB, userId: fideleBUserId, nom: 'Autre Fidèle EXEMPLE', phone: '+2250708080921', email: 'fidele-exemple-push-autre@example.com' },
    ];
    const membreIds = {};
    for (const fiche of fiches) {
      const creee = await appel('POST', '/membres', fiche.jeton, {
        full_name: fiche.nom,
        phone: fiche.phone,
        email: fiche.email,
      });
      verifier(`fiche membre ${fiche.nom}`, creee.statut === 201, creee.texte);
      membreIds[fiche.email] = creee.json?.id;
    }
    const liaison = new Client({ connectionString: DATABASE_URL });
    await liaison.connect();
    for (const fiche of fiches) {
      await liaison.query(`UPDATE users SET member_id = $1 WHERE id = $2`, [
        membreIds[fiche.email],
        fiche.userId,
      ]);
    }
    await liaison.end();
    const membreAdminA = membreIds['admin-exemple-push@example.com'];
    const membreFideleA = membreIds['fidele-exemple-push@example.com'];

    // Conversation directe A (admin A + fidèle A), avec un titre.
    const conv = await appel('POST', '/messagerie/conversations', jetonAdminA, {
      type: 'directe',
      title: 'Conversation EXEMPLE',
      participant_member_ids: [membreFideleA],
    });
    verifier('création conversation directe A', conv.statut === 201 && typeof conv.json?.id === 'string', conv.texte);
    const convId = conv.json?.id;

    // --- 3. Enregistrement et retrait d'un jeton ---------------------------
    const enregistre = await appel('POST', '/messagerie/jetons', jetonFideleA, {
      token: JETON_FIDELE_A,
      platform: 'web',
    });
    verifier(
      'enregistrement jeton fidèle A = 201',
      enregistre.statut === 201 && enregistre.json?.token_suffix === JETON_FIDELE_A.slice(-8),
      enregistre.texte.slice(0, 200),
    );
    verifier(
      'le jeton complet n\u2019est jamais renvoyé',
      enregistre.json?.token === undefined,
      enregistre.texte.slice(0, 200),
    );
    const reenregistre = await appel('POST', '/messagerie/jetons', jetonFideleA, {
      token: JETON_FIDELE_A,
      platform: 'android',
    });
    verifier(
      'ré-enregistrement du même jeton = 200 (doublon géré, pas de 409)',
      reenregistre.statut === 200 && reenregistre.json?.platform === 'android' && reenregistre.json?.is_active === true,
      reenregistre.texte.slice(0, 200),
    );
    const jetonCourt = await appel('POST', '/messagerie/jetons', jetonFideleA, {
      token: 'court',
      platform: 'web',
    });
    verifier('jeton trop court = 400', jetonCourt.statut === 400, jetonCourt.texte);
    const mauvaisePlateforme = await appel('POST', '/messagerie/jetons', jetonFideleA, {
      token: JETON_FIDELE_A_2,
      platform: 'ios',
    });
    verifier('plateforme autre que web/android = 400', mauvaisePlateforme.statut === 400, mauvaisePlateforme.texte);
    const sansJeton = await appel('POST', '/messagerie/jetons', null, {
      token: JETON_FIDELE_A_2,
      platform: 'web',
    });
    verifier('sans jeton d\u2019authentification = 401', sansJeton.statut === 401, sansJeton.texte);
    const listeA = await appel('GET', '/messagerie/jetons', jetonFideleA);
    verifier(
      'fidèle A liste 1 jeton',
      listeA.statut === 200 && Array.isArray(listeA.json) && listeA.json.length === 1,
      listeA.texte.slice(0, 200),
    );

    // --- 4. Isolation entre églises -----------------------------------------
    const jetonB = await appel('POST', '/messagerie/jetons', jetonFideleB, {
      token: JETON_FIDELE_B,
      platform: 'android',
    });
    verifier('fidèle B enregistre son propre jeton = 201', jetonB.statut === 201, jetonB.texte);
    const listeB = await appel('GET', '/messagerie/jetons', jetonFideleB);
    verifier(
      'fidèle B liste 1 jeton (le sien seulement)',
      listeB.statut === 200 && Array.isArray(listeB.json) && listeB.json.length === 1 &&
        listeB.json[0]?.token_suffix === JETON_FIDELE_B.slice(-8),
      listeB.texte.slice(0, 200),
    );
    const listeAdminB = await appel('GET', '/messagerie/jetons', jetonAdminB);
    verifier(
      'admin B liste zéro jeton',
      listeAdminB.statut === 200 && Array.isArray(listeAdminB.json) && listeAdminB.json.length === 0,
      listeAdminB.texte.slice(0, 200),
    );
    const retraitParB = await appel('DELETE', '/messagerie/jetons', jetonFideleB, {
      token: JETON_FIDELE_A,
    });
    verifier('fidèle B retire le jeton de A = 404', retraitParB.statut === 404, retraitParB.texte);
    const listeApresTentative = await appel('GET', '/messagerie/jetons', jetonFideleA);
    verifier(
      'jeton de A toujours présent après la tentative de B',
      listeApresTentative.statut === 200 && Array.isArray(listeApresTentative.json) &&
        listeApresTentative.json.length === 1,
      listeApresTentative.texte.slice(0, 200),
    );
    const retrait = await appel('DELETE', '/messagerie/jetons', jetonFideleA, {
      token: JETON_FIDELE_A,
    });
    verifier('fidèle A retire son jeton = 204', retrait.statut === 204, retrait.texte);
    const listeVide = await appel('GET', '/messagerie/jetons', jetonFideleA);
    verifier(
      'fidèle A liste zéro jeton après retrait',
      listeVide.statut === 200 && Array.isArray(listeVide.json) && listeVide.json.length === 0,
      listeVide.texte.slice(0, 200),
    );
    const retraitInconnu = await appel('DELETE', '/messagerie/jetons', jetonFideleA, {
      token: JETON_FIDELE_A,
    });
    verifier('retrait d\u2019un jeton déjà retiré = 404', retraitInconnu.statut === 404, retraitInconnu.texte);

    // --- 5. Super administrateur : aucun accès aux jetons --------------------
    const directSuper = new Client({ connectionString: DATABASE_URL });
    await directSuper.connect();
    const hashSuper = await argon2.hash('MotDePasse123!');
    const superLigne = await directSuper.query(
      `INSERT INTO users (email, password_hash, full_name)
       VALUES ($1, $2, $3) RETURNING id`,
      ['super-exemple-push@example.com', hashSuper, 'Super EXEMPLE'],
    );
    const superUserId = superLigne.rows[0]?.id;
    await directSuper.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'super_admin')`,
      [superUserId, egliseAId],
    );
    await directSuper.end();
    const loginSuper = await appel('POST', '/auth/login', null, {
      identifiant: 'super-exemple-push@example.com',
      password: 'MotDePasse123!',
      channel: 'web',
      plateforme: true,
    });
    verifier(
      'connexion Plateforme super_admin',
      loginSuper.statut === 200 && typeof loginSuper.json?.token === 'string',
      loginSuper.texte.slice(0, 200),
    );
    const jetonSuper = await appel('POST', '/messagerie/jetons', loginSuper.json?.token, {
      token: JETON_FIDELE_A_2,
      platform: 'web',
    });
    verifier('super_admin enregistre un jeton = 403', jetonSuper.statut === 403, jetonSuper.texte);

    // --- 6. Message créé normalement sans FCM -------------------------------
    // Le fidèle A ré-enregistre un jeton, puis l'admin A envoie un
    // message : FCM est désactivé (pas de compte de service), le
    // message doit être créé en 201 et le jeton rester actif.
    const reenregistreA = await appel('POST', '/messagerie/jetons', jetonFideleA, {
      token: JETON_FIDELE_A,
      platform: 'web',
    });
    verifier('fidèle A ré-enregistre son jeton', reenregistreA.statut === 201, reenregistreA.texte);
    const message = await appel('POST', `/messagerie/conversations/${convId}/messages`, jetonAdminA, {
      content: 'Bonjour EXEMPLE, bienvenue.',
    });
    verifier(
      'message créé en 201 sans FCM',
      message.statut === 201 && message.json?.content === 'Bonjour EXEMPLE, bienvenue.',
      message.texte,
    );
    await sleep(1000);
    verifier(
      'journal API : FCM désactivé proprement',
      sortieApi.includes('FCM désactivé'),
      sortieApi.slice(0, 300),
    );
    const directActif = new Client({ connectionString: DATABASE_URL });
    await directActif.connect();
    const actif = await directActif.query(
      `SELECT is_active FROM device_tokens WHERE token = $1`,
      [JETON_FIDELE_A],
    );
    verifier(
      'jeton de A toujours actif après un message sans FCM',
      actif.rowCount === 1 && actif.rows[0]?.is_active === true,
      `reçu ${actif.rowCount} ligne(s)`,
    );
    await directActif.end();

    // --- 7. Envoi simulé au bon destinataire (en processus) -----------------
    // L'admin A a aussi un jeton : il ne doit pas être notifié de son
    // propre message. Le fidèle A a deux jetons : l'un livré, l'autre
    // invalide (à marquer inactif). Aucun appel FCM réel.
    const jetonAdmin = await appel('POST', '/messagerie/jetons', jetonAdminA, {
      token: JETON_ADMIN_A,
      platform: 'android',
    });
    verifier('admin A enregistre son jeton', jetonAdmin.statut === 201, jetonAdmin.texte);
    const jetonA2 = await appel('POST', '/messagerie/jetons', jetonFideleA, {
      token: JETON_FIDELE_A_2,
      platform: 'android',
    });
    verifier('fidèle A enregistre un deuxième jeton', jetonA2.statut === 201, jetonA2.texte);
    const appelsSimules = [];
    // Dernier usage du jeton de l'expéditeur avant l'envoi : il ne doit
    // pas bouger (l'expéditeur n'est jamais notifié de son message).
    const avantEnvoi = new Client({ connectionString: DATABASE_URL });
    await avantEnvoi.connect();
    const usageAdminAvant = await avantEnvoi.query(
      `SELECT last_used_at FROM device_tokens WHERE token = $1`,
      [JETON_ADMIN_A],
    );
    await avantEnvoi.end();
    const dernierUsageAdminAvant = usageAdminAvant.rows[0]?.last_used_at?.toISOString() ?? null;
    definirTransportFcmPourTest(async (jetons, charge) => {
      appelsSimules.push({ jetons: [...jetons], charge });
      return { livres: [JETON_FIDELE_A], invalides: [JETON_FIDELE_A_2] };
    });
    const pool = new Pool({ connectionString: DATABASE_URL });
    const contenuLong = `Message EXEMPLE très long : ${'mot '.repeat(40)}fin.`;
    const resultat = await notifierNouveauMessage(pool, {
      churchId: egliseAId,
      conversationId: convId,
      expediteurMemberId: membreAdminA,
      titre: 'Conversation EXEMPLE',
      contenu: contenuLong,
    });
    verifier(
      'envoi simulé : 1 livré sur 2 jetons',
      resultat.envoye === 1 && resultat.jetons === 2 && resultat.desactive === false,
      JSON.stringify(resultat),
    );
    verifier('transport simulé appelé une fois', appelsSimules.length === 1, `reçu ${appelsSimules.length}`);
    const appelSimule = appelsSimules[0];
    verifier(
      'envoi au bon destinataire : les 2 jetons du fidèle A seulement',
      appelSimule !== undefined &&
        appelSimule.jetons.length === 2 &&
        appelSimule.jetons.includes(JETON_FIDELE_A) &&
        appelSimule.jetons.includes(JETON_FIDELE_A_2) &&
        !appelSimule.jetons.includes(JETON_ADMIN_A),
      JSON.stringify(appelSimule?.jetons),
    );
    verifier(
      'titre = titre de la conversation, sans contenu de message',
      appelSimule?.charge?.titre === 'Conversation EXEMPLE',
      JSON.stringify(appelSimule?.charge),
    );
    verifier(
      'aperçu tronqué à 100 caractères + « … »',
      typeof appelSimule?.charge?.corps === 'string' &&
        appelSimule.charge.corps.length === 101 &&
        appelSimule.charge.corps.endsWith('…'),
      `reçu ${appelSimule?.charge?.corps?.length} caractères`,
    );
    const directJetons = new Client({ connectionString: DATABASE_URL });
    await directJetons.connect();
    const etats = await directJetons.query(
      `SELECT token, is_active, last_used_at, last_used_at IS NOT NULL AS utilise
         FROM device_tokens WHERE token = ANY($1)`,
      [[JETON_FIDELE_A, JETON_FIDELE_A_2, JETON_ADMIN_A]],
    );
    const parJeton = Object.fromEntries(etats.rows.map((r) => [r.token, r]));
    verifier(
      'jeton invalide marqué inactif',
      parJeton[JETON_FIDELE_A_2]?.is_active === false,
      JSON.stringify(parJeton[JETON_FIDELE_A_2]),
    );
    verifier(
      'jeton livré resté actif avec dernier usage renseigné',
      parJeton[JETON_FIDELE_A]?.is_active === true && parJeton[JETON_FIDELE_A]?.utilise === true,
      JSON.stringify(parJeton[JETON_FIDELE_A]),
    );
    verifier(
      'jeton de l\u2019expéditeur intact (jamais notifié, dernier usage inchangé)',
      parJeton[JETON_ADMIN_A]?.is_active === true &&
        (parJeton[JETON_ADMIN_A]?.last_used_at?.toISOString() ?? null) === dernierUsageAdminAvant,
      JSON.stringify(parJeton[JETON_ADMIN_A]),
    );
    await directJetons.end();

    // --- 8. Compte de service invalide : désactivé, sans panne --------------
    definirTransportFcmPourTest(null);
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON = 'ceci-n-est-pas-du-json';
    reinitialiserFcmPourTest();
    const resultatInvalide = await notifierNouveauMessage(pool, {
      churchId: egliseAId,
      conversationId: convId,
      expediteurMemberId: membreAdminA,
      titre: 'Conversation EXEMPLE',
      contenu: 'Message EXEMPLE après compte invalide.',
    });
    verifier(
      'compte de service invalide : envoi désactivé, sans exception',
      resultatInvalide.desactive === true && resultatInvalide.envoye === 0,
      JSON.stringify(resultatInvalide),
    );
    verifier(
      'compte de service invalide : le transport simulé n\u2019a pas été rappelé',
      appelsSimules.length === 1,
      `reçu ${appelsSimules.length}`,
    );
    delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    reinitialiserFcmPourTest();
    await pool.end();
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
