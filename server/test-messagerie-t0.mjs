// Test d'intégration de la tranche T-Msg-0 (Messagerie et Signalement) :
// tables et RLS de la migration 034, conversations et messages texte,
// isolation entre églises (le cœur du test), super administrateur sans
// accès au contenu, et vérification RLS réelle avec un rôle restreint.
// Même forme que server/test-t11-confiance.mjs : base fraîche créée puis
// vidée par le test lui-même, application du schéma puis des migrations
// avec le vrai moteur de migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-messagerie-t0.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4112).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_msg0.
// Base locale : PostgreSQL est nécessaire.

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);

const PORT = Number(process.env.PORT ?? 4112);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_msg0';
// Nom de la base visée par DATABASE_URL : c'est elle que le test recrée.
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-t11).
const JWT_SECRET = 'test-jwt-secret-pour-t11-seulement-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const TABLES_MSG = [
  'conversations',
  'conversation_participants',
  'messages',
  'message_attachments',
  'reports',
  'moderation_actions',
  'appeals',
  'blocks',
  'minor_flags',
];

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

  // Démarrage de l'API.
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, PORT: String(PORT), JWT_SECRET, PAYMENT_SECRETS_KEY },
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

    // --- 1. Tables et RLS (requêtes directes en base) ----------------------
    const direct = new Client({ connectionString: DATABASE_URL });
    await direct.connect();
    const tables = await direct.query(
      `SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = ANY($1)`,
      [TABLES_MSG],
    );
    verifier('migration 034 : 9 tables créées', tables.rowCount === 9, `reçu ${tables.rowCount}`);
    const rls = await direct.query(
      `SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = ANY($1) AND c.relrowsecurity`,
      [TABLES_MSG],
    );
    verifier('migration 034 : RLS activée sur les 9 tables', rls.rowCount === 9, `reçu ${rls.rowCount}`);
    const politiquesIsolement = await direct.query(
      `SELECT tablename FROM pg_policies
        WHERE policyname = 'isolement_eglise' AND tablename = ANY($1)`,
      [TABLES_MSG],
    );
    verifier('migration 034 : 9 politiques isolement_eglise', politiquesIsolement.rowCount === 9, `reçu ${politiquesIsolement.rowCount}`);
    const politiqueEscalade = await direct.query(
      `SELECT tablename FROM pg_policies WHERE policyname = 'escalade_mere' AND tablename = 'reports'`,
    );
    verifier('migration 034 : 1 politique escalade_mere sur reports', politiqueEscalade.rowCount === 1, `reçu ${politiqueEscalade.rowCount}`);
    const index = await direct.query(
      `SELECT indexname FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname IN ('idx_messages_church_conversation', 'idx_reports_church_status')`,
    );
    verifier('migration 034 : index messages et reports présents', index.rowCount === 2, `reçu ${index.rowCount}`);
    const migration = await direct.query(
      `SELECT 1 FROM schema_migrations WHERE name = '034_messagerie_signalement'`,
    );
    verifier('migration 034 enregistrée dans schema_migrations', migration.rowCount === 1);
    await direct.end();

    // --- 2. Préparation par API : deux églises, quatre comptes -------------
    const mereA = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan', phone: '+2250102030405' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-msg0@example.com',
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
      email: 'fidele-exemple-msg0@example.com',
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
        email: 'admin-exemple-msg0-autre@example.com',
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
      email: 'fidele-exemple-msg0-autre@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080919',
    });
    verifier('inscription fidèle B par code', fideleB.statut === 201, fideleB.texte);
    const jetonFideleB = fideleB.json?.token;
    const fideleBUserId = fideleB.json?.user?.id;

    // Fiche membre pour chaque compte (POST /membres, par l'admin de son
    // église), puis liaison users.member_id en base : POST /membres ne
    // lie pas le compte, et la messagerie exige une fiche membre.
    const fiches = [
      { jeton: jetonAdminA, userId: adminAUserId, nom: 'Admin EXEMPLE', phone: '+2250708080910', email: 'admin-exemple-msg0@example.com' },
      { jeton: jetonAdminA, userId: fideleAUserId, nom: 'Fidèle EXEMPLE', phone: '+2250708080911', email: 'fidele-exemple-msg0@example.com' },
      { jeton: jetonAdminB, userId: adminBUserId, nom: 'Autre Admin EXEMPLE', phone: '+2250708080920', email: 'admin-exemple-msg0-autre@example.com' },
      { jeton: jetonAdminB, userId: fideleBUserId, nom: 'Autre Fidèle EXEMPLE', phone: '+2250708080921', email: 'fidele-exemple-msg0-autre@example.com' },
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
    const lies = await liaison.query(
      `SELECT count(*)::int AS n FROM users WHERE id = ANY($1) AND member_id IS NOT NULL`,
      [[adminAUserId, fideleAUserId, adminBUserId, fideleBUserId]],
    );
    verifier('4 comptes liés à leur fiche membre', lies.rows[0]?.n === 4, `reçu ${lies.rows[0]?.n}`);
    await liaison.end();

    const membreFideleA = membreIds['fidele-exemple-msg0@example.com'];

    // --- 3. Conversations et messages (église A) ---------------------------
    const conv = await appel('POST', '/messagerie/conversations', jetonAdminA, {
      type: 'directe',
      participant_member_ids: [membreFideleA],
    });
    verifier('création conversation directe A', conv.statut === 201 && typeof conv.json?.id === 'string', conv.texte);
    const convId = conv.json?.id;

    const message = await appel('POST', `/messagerie/conversations/${convId}/messages`, jetonAdminA, {
      content: 'Bonjour EXEMPLE, bienvenue.',
    });
    verifier('envoi message par admin A', message.statut === 201 && message.json?.content === 'Bonjour EXEMPLE, bienvenue.', message.texte);

    const lectureFidele = await appel('GET', `/messagerie/conversations/${convId}`, jetonFideleA);
    verifier('fidèle A lit la conversation', lectureFidele.statut === 200 && lectureFidele.json?.id === convId, lectureFidele.texte);
    const listeFidele = await appel('GET', '/messagerie/conversations', jetonFideleA);
    verifier(
      'fidèle A liste 1 conversation',
      listeFidele.statut === 200 && Array.isArray(listeFidele.json) && listeFidele.json.length === 1,
      listeFidele.texte.slice(0, 200),
    );
    const listeAdmin = await appel('GET', '/messagerie/conversations', jetonAdminA);
    verifier(
      'admin A liste 1 conversation',
      listeAdmin.statut === 200 && Array.isArray(listeAdmin.json) && listeAdmin.json.length === 1,
      listeAdmin.texte.slice(0, 200),
    );
    const messagesFidele = await appel('GET', `/messagerie/conversations/${convId}/messages`, jetonFideleA);
    verifier(
      'fidèle A lit 1 message',
      messagesFidele.statut === 200 &&
        Array.isArray(messagesFidele.json) &&
        messagesFidele.json.length === 1 &&
        messagesFidele.json[0]?.content === 'Bonjour EXEMPLE, bienvenue.',
      messagesFidele.texte.slice(0, 200),
    );

    // --- 4. Isolation entre églises -----------------------------------------
    const listeB = await appel('GET', '/messagerie/conversations', jetonAdminB);
    verifier(
      'admin B liste zéro conversation',
      listeB.statut === 200 && Array.isArray(listeB.json) && listeB.json.length === 0,
      listeB.texte.slice(0, 200),
    );
    const lectureB = await appel('GET', `/messagerie/conversations/${convId}`, jetonAdminB);
    verifier('admin B lit la conversation de A = 404', lectureB.statut === 404, lectureB.texte);
    const messagesB = await appel('GET', `/messagerie/conversations/${convId}/messages`, jetonAdminB);
    verifier('admin B liste les messages de A = 404', messagesB.statut === 404, messagesB.texte);
    const envoiB = await appel('POST', `/messagerie/conversations/${convId}/messages`, jetonAdminB, {
      content: 'Message EXEMPLE depuis B.',
    });
    verifier('admin B envoie dans la conversation de A = 404', envoiB.statut === 404, envoiB.texte);
    const lectureFideleB = await appel('GET', `/messagerie/conversations/${convId}`, jetonFideleB);
    verifier('fidèle B lit la conversation de A = 404', lectureFideleB.statut === 404, lectureFideleB.texte);
    const sansJeton = await appel('GET', '/messagerie/conversations', null);
    verifier('sans jeton = 401', sansJeton.statut === 401, sansJeton.texte);

    // --- 5. Super administrateur : aucun accès au contenu --------------------
    // Pas de création par API : insertion directe en base (même motif que
    // test-bascule-espaces.mjs), puis connexion Plateforme réelle.
    const directSuper = new Client({ connectionString: DATABASE_URL });
    await directSuper.connect();
    const hashSuper = await argon2.hash('MotDePasse123!');
    const superLigne = await directSuper.query(
      `INSERT INTO users (email, password_hash, full_name)
       VALUES ($1, $2, $3) RETURNING id`,
      ['super-exemple-msg0@example.com', hashSuper, 'Super EXEMPLE'],
    );
    const superUserId = superLigne.rows[0]?.id;
    await directSuper.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'super_admin')`,
      [superUserId, egliseAId],
    );
    await directSuper.end();
    const loginSuper = await appel('POST', '/auth/login', null, {
      identifiant: 'super-exemple-msg0@example.com',
      password: 'MotDePasse123!',
      channel: 'web',
      plateforme: true,
    });
    verifier(
      'connexion Plateforme super_admin',
      loginSuper.statut === 200 && typeof loginSuper.json?.token === 'string',
      loginSuper.texte.slice(0, 200),
    );
    const listeSuper = await appel('GET', '/messagerie/conversations', loginSuper.json?.token);
    verifier('super_admin liste les conversations = 403', listeSuper.statut === 403, listeSuper.texte);
    const lectureSuper = await appel('GET', `/messagerie/conversations/${convId}`, loginSuper.json?.token);
    verifier('super_admin lit la conversation de A = 403', lectureSuper.statut === 403, lectureSuper.texte);

    // --- 6. RLS avec un rôle restreint (requêtes directes en base) ----------
    // Le rôle propriétaire (postgres) contourne la RLS : un rôle restreint
    // avec SELECT sur les 9 tables prouve que les politiques filtrent.
    const directRls = new Client({ connectionString: DATABASE_URL });
    await directRls.connect();
    // Nettoyage du rôle : DROP ROLE échoue tant que le rôle garde des
    // privilèges (code 2BP01), il faut révoquer avant de supprimer.
    const nettoyerRole = async () => {
      await directRls
        .query(`REVOKE ALL PRIVILEGES ON ${TABLES_MSG.join(', ')}, users, church_users FROM esc_test_msg0`)
        .catch(() => undefined);
      await directRls.query(`DROP ROLE IF EXISTS esc_test_msg0`).catch(() => undefined);
    };
    await nettoyerRole();
    await directRls.query(`CREATE ROLE esc_test_msg0 LOGIN PASSWORD 'msg0-test-rls'`);
    await directRls.query(`GRANT SELECT ON ${TABLES_MSG.join(', ')} TO esc_test_msg0`);
    // La politique escalade_mere lit users et church_users : le rôle doit
    // pouvoir les lire pour que son expression s'évalue.
    await directRls.query(`GRANT SELECT ON users, church_users TO esc_test_msg0`);
    let rlsOk = false;
    let rlsDetail = '';
    const rlsClient = new Client({
      connectionString: 'postgres://esc_test_msg0:msg0-test-rls@127.0.0.1:5432/' + DB_NAME,
    });
    try {
      await rlsClient.connect();
      await rlsClient.query(`SELECT set_config('app.church_id', $1, false)`, [egliseAId]);
      const convA = await rlsClient.query(`SELECT id FROM conversations`);
      const msgA = await rlsClient.query(`SELECT id FROM messages`);
      verifier(
        'RLS rôle restreint, église A : 1 conversation, 1 message',
        convA.rowCount === 1 && msgA.rowCount === 1,
        `conversations=${convA.rowCount} messages=${msgA.rowCount}`,
      );
      await rlsClient.query(`SELECT set_config('app.church_id', $1, false)`, [egliseBId]);
      const convB = await rlsClient.query(`SELECT id FROM conversations`);
      const msgB = await rlsClient.query(`SELECT id FROM messages`);
      verifier(
        'RLS rôle restreint, église B : zéro ligne',
        convB.rowCount === 0 && msgB.rowCount === 0,
        `conversations=${convB.rowCount} messages=${msgB.rowCount}`,
      );
      rlsOk = true;
    } catch (e) {
      rlsDetail = String(e?.message ?? e);
      verifier('RLS rôle restreint : connexion et lectures', false, rlsDetail);
    } finally {
      await rlsClient.end().catch(() => undefined);
      await nettoyerRole();
      await directRls.end();
    }
    if (!rlsOk) {
      // Repli documenté : la vérification réelle a échoué, on contrôle au
      // moins que les politiques existent dans pg_policies.
      const directRepli = new Client({ connectionString: DATABASE_URL });
      await directRepli.connect();
      const politiques = await directRepli.query(
        `SELECT count(*)::int AS n FROM pg_policies
          WHERE policyname IN ('isolement_eglise', 'escalade_mere')
            AND tablename = ANY($1)`,
        [TABLES_MSG],
      );
      verifier(
        'repli : 10 politiques messagerie dans pg_policies',
        politiques.rows[0]?.n === 10,
        `reçu ${politiques.rows[0]?.n} (vérification RLS réelle en échec : ${rlsDetail})`,
      );
      await directRepli.end();
    }
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
