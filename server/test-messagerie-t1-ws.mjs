// Test d'intégration de la tranche T-Msg-1 (Messagerie et Signalement) :
// WebSocket authentifié par jeton JWT en ?token=, abonnement par
// conversation avec vérification de participation et journalisation
// des tentatives hors périmètre, diffusion aux participants seulement
// après un POST HTTP, limite de débit (30/min, 300/h par membre).
// Même forme que server/test-messagerie-t0.mjs : base fraîche créée puis
// vidée par le test lui-même, application du schéma puis des migrations
// avec le vrai moteur de migration, démarrage de l'API, appels HTTP et
// clients WebSocket (paquet `ws`, devDependency).
//
// Usage : `node server/test-messagerie-t1-ws.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4113).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_msg1.
// Base locale : PostgreSQL est nécessaire.

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import WebSocket from 'ws';

const exec = promisify(execFile);

const PORT = Number(process.env.PORT ?? 4113);
const BASE = `http://127.0.0.1:${PORT}`;
const WS_BASE = `ws://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_msg1';
// Nom de la base visée par DATABASE_URL : c'est elle que le test recrée.
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0).
const JWT_SECRET = 'test-jwt-secret-pour-t11-seulement-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

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

/** Ouvre un WebSocket et garde tous les messages JSON reçus. */
function ouvrirWs(url) {
  const ws = new WebSocket(url);
  const messages = [];
  const ouvert = new Promise((resolve) => ws.on('open', () => resolve(true)));
  const ferme = new Promise((resolve) =>
    ws.on('close', (code, raison) => resolve({ code, raison: raison.toString() })),
  );
  ws.on('message', (donnees) => {
    try {
      messages.push(JSON.parse(donnees.toString()));
    } catch {
      // Trame non JSON : ignorée, le serveur n'en envoie pas.
    }
  });
  ws.on('error', () => {});
  return { ws, messages, ouvert, ferme };
}

/** Attend l'ouverture d'un WebSocket, ou échoue vite s'il se ferme avant. */
async function attendreOuverture(connexion, nom) {
  const fermeTropTot = connexion.ferme.then((f) => {
    throw new Error(`${nom} : fermé avant ouverture (code ${f.code}, ${f.raison})`);
  });
  await Promise.race([
    connexion.ouvert,
    fermeTropTot,
    sleep(5000).then(() => {
      throw new Error(`${nom} : ouverture trop lente (5 s)`);
    }),
  ]);
}

/** Attend qu'un message vérifiant `predicat` arrive, ou null après `delai`. */
async function attendreMessage(messages, predicat, delai = 3000) {
  const fin = Date.now() + delai;
  while (Date.now() < fin) {
    const trouve = messages.find(predicat);
    if (trouve) return trouve;
    await sleep(25);
  }
  return null;
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
  const sockets = [];
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

    // --- 1. Préparation par API : deux églises, quatre comptes -------------
    const mereA = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan', phone: '+2250102030405' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-msg1@example.com',
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
      email: 'fidele-exemple-msg1@example.com',
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
        email: 'admin-exemple-msg1-autre@example.com',
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
      email: 'fidele-exemple-msg1-autre@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080919',
    });
    verifier('inscription fidèle B par code', fideleB.statut === 201, fideleB.texte);
    const jetonFideleB = fideleB.json?.token;
    const fideleBUserId = fideleB.json?.user?.id;

    // Fiche membre pour chaque compte, puis liaison users.member_id.
    const fiches = [
      { jeton: jetonAdminA, userId: adminAUserId, nom: 'Admin EXEMPLE', phone: '+2250708080910', email: 'admin-exemple-msg1@example.com' },
      { jeton: jetonAdminA, userId: fideleAUserId, nom: 'Fidèle EXEMPLE', phone: '+2250708080911', email: 'fidele-exemple-msg1@example.com' },
      { jeton: jetonAdminB, userId: adminBUserId, nom: 'Autre Admin EXEMPLE', phone: '+2250708080920', email: 'admin-exemple-msg1-autre@example.com' },
      { jeton: jetonAdminB, userId: fideleBUserId, nom: 'Autre Fidèle EXEMPLE', phone: '+2250708080921', email: 'fidele-exemple-msg1-autre@example.com' },
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

    const membreFideleA = membreIds['fidele-exemple-msg1@example.com'];
    const membreFideleB = membreIds['fidele-exemple-msg1-autre@example.com'];

    // Une conversation directe par église.
    const convA = await appel('POST', '/messagerie/conversations', jetonAdminA, {
      type: 'directe',
      participant_member_ids: [membreFideleA],
    });
    verifier('création conversation directe A', convA.statut === 201 && typeof convA.json?.id === 'string', convA.texte);
    const convAId = convA.json?.id;
    const convB = await appel('POST', '/messagerie/conversations', jetonAdminB, {
      type: 'directe',
      participant_member_ids: [membreFideleB],
    });
    verifier('création conversation directe B', convB.statut === 201 && typeof convB.json?.id === 'string', convB.texte);
    const convBId = convB.json?.id;

    // --- 2. Authentification WebSocket --------------------------------------
    const sansJeton = ouvrirWs(`${WS_BASE}/messagerie/ws`);
    sockets.push(sansJeton.ws);
    const fermetureSansJeton = await Promise.race([
      sansJeton.ferme,
      sleep(3000).then(() => null),
    ]);
    verifier(
      'WS sans jeton : fermeture 1008',
      fermetureSansJeton !== null && fermetureSansJeton.code === 1008,
      JSON.stringify(fermetureSansJeton),
    );

    const jetonBidon = ouvrirWs(`${WS_BASE}/messagerie/ws?token=jeton-bidon`);
    sockets.push(jetonBidon.ws);
    const fermetureBidon = await Promise.race([
      jetonBidon.ferme,
      sleep(3000).then(() => null),
    ]);
    verifier(
      'WS jeton invalide : fermeture 1008',
      fermetureBidon !== null && fermetureBidon.code === 1008,
      JSON.stringify(fermetureBidon),
    );

    // --- 3. Abonnement : participant, réabonnement, hors périmètre ---------
    const wsFideleA = ouvrirWs(`${WS_BASE}/messagerie/ws?token=${jetonFideleA}`);
    sockets.push(wsFideleA.ws);
    await attendreOuverture(wsFideleA, "fidèle A");
    wsFideleA.ws.send(JSON.stringify({ type: 'subscribe', conversation_id: convAId }));
    const ackA = await attendreMessage(
      wsFideleA.messages,
      (m) => m.type === 'subscribed' && m.conversation_id === convAId,
    );
    verifier('fidèle A abonné à la conversation A', ackA !== null);
    // Réabonnement idempotent : deuxième accusé, sans doublon d'abonnement.
    wsFideleA.ws.send(JSON.stringify({ type: 'subscribe', conversation_id: convAId }));
    let accuses = 0;
    const finAccuses = Date.now() + 3000;
    while (Date.now() < finAccuses && accuses < 2) {
      accuses = wsFideleA.messages.filter((m) => m.type === 'subscribed').length;
      if (accuses < 2) await sleep(25);
    }
    verifier(
      'réabonnement idempotent : deuxième accusé reçu',
      accuses === 2,
      `accusés reçus : ${accuses}`,
    );

    const wsAdminB = ouvrirWs(`${WS_BASE}/messagerie/ws?token=${jetonAdminB}`);
    sockets.push(wsAdminB.ws);
    await attendreOuverture(wsAdminB, "admin B");
    wsAdminB.ws.send(JSON.stringify({ type: 'subscribe', conversation_id: convAId }));
    const refusB = await attendreMessage(
      wsAdminB.messages,
      (m) => m.type === 'error' && m.code === 'forbidden',
    );
    verifier("admin B abonné à la conversation de A : rejet forbidden", refusB !== null);
    verifier(
      'admin B reste connecté après le rejet',
      wsAdminB.ws.readyState === WebSocket.OPEN,
      `readyState=${wsAdminB.ws.readyState}`,
    );
    // Tentative hors périmètre journalisée dans l'audit de l'église B.
    const directAudit = new Client({ connectionString: DATABASE_URL });
    await directAudit.connect();
    const audit = await directAudit.query(
      `SELECT count(*)::int AS n FROM audit_logs
        WHERE action = 'messagerie.abonnement_refuse' AND church_id = $1
          AND details ->> 'conversation_id' = $2`,
      [egliseBId, convAId],
    );
    verifier(
      'tentative hors périmètre journalisée en audit',
      audit.rows[0]?.n === 1,
      `lignes=${audit.rows[0]?.n}`,
    );
    await directAudit.end();

    // Admin B s'abonne à sa propre conversation, pour le test de diffusion.
    wsAdminB.ws.send(JSON.stringify({ type: 'subscribe', conversation_id: convBId }));
    const ackB = await attendreMessage(
      wsAdminB.messages,
      (m) => m.type === 'subscribed' && m.conversation_id === convBId,
    );
    verifier('admin B abonné à la conversation B', ackB !== null);

    const wsAdminA = ouvrirWs(`${WS_BASE}/messagerie/ws?token=${jetonAdminA}`);
    sockets.push(wsAdminA.ws);
    await attendreOuverture(wsAdminA, "admin A");
    wsAdminA.ws.send(JSON.stringify({ type: 'subscribe', conversation_id: convAId }));
    const ackAdminA = await attendreMessage(
      wsAdminA.messages,
      (m) => m.type === 'subscribed' && m.conversation_id === convAId,
    );
    verifier('admin A abonné à la conversation A', ackAdminA !== null);

    // --- 4. Diffusion après POST HTTP ---------------------------------------
    const envoi = await appel('POST', `/messagerie/conversations/${convAId}/messages`, jetonAdminA, {
      content: 'Bonjour EXEMPLE, diffusion.',
    });
    verifier('envoi HTTP dans la conversation A', envoi.statut === 201, envoi.texte);
    const recuFideleA = await attendreMessage(
      wsFideleA.messages,
      (m) => m.type === 'message' && m.conversation_id === convAId && m.message?.id === envoi.json?.id,
    );
    verifier(
      'diffusion reçue par le participant fidèle A',
      recuFideleA !== null && recuFideleA.message?.content === 'Bonjour EXEMPLE, diffusion.',
      JSON.stringify(recuFideleA),
    );
    const recuAdminA = await attendreMessage(
      wsAdminA.messages,
      (m) => m.type === 'message' && m.conversation_id === convAId && m.message?.id === envoi.json?.id,
    );
    verifier('diffusion reçue par le participant admin A', recuAdminA !== null);
    // Le réabonnement n'a pas doublé la diffusion.
    await sleep(500);
    verifier(
      'une seule diffusion malgré le réabonnement',
      wsFideleA.messages.filter(
        (m) => m.type === 'message' && m.conversation_id === convAId && m.message?.id === envoi.json?.id,
      ).length === 1,
      `reçus : ${wsFideleA.messages.filter((m) => m.type === 'message').length}`,
    );
    // Non participant connecté (admin B, abonné à B) : rien reçu.
    const avantB = wsAdminB.messages.length;
    await sleep(700);
    verifier(
      'rien reçu par le non participant connecté (admin B)',
      wsAdminB.messages.length === avantB,
      `messages B : ${wsAdminB.messages.length} (avant ${avantB})`,
    );

    // --- 5. Connecté sans abonnement : rien reçu ----------------------------
    const wsFideleA2 = ouvrirWs(`${WS_BASE}/messagerie/ws?token=${jetonFideleA}`);
    sockets.push(wsFideleA2.ws);
    await attendreOuverture(wsFideleA2, "fidèle A (2e connexion)");
    const envoi2 = await appel('POST', `/messagerie/conversations/${convAId}/messages`, jetonAdminA, {
      content: 'Deuxième message EXEMPLE.',
    });
    verifier('deuxième envoi HTTP dans la conversation A', envoi2.statut === 201, envoi2.texte);
    const recuFideleA2 = await attendreMessage(
      wsFideleA.messages,
      (m) => m.type === 'message' && m.message?.id === envoi2.json?.id,
    );
    verifier('abonné reçoit le deuxième message', recuFideleA2 !== null);
    await sleep(700);
    verifier(
      'connecté sans abonnement : rien reçu',
      wsFideleA2.messages.length === 0,
      `messages reçus : ${wsFideleA2.messages.length}`,
    );

    // --- 6. Limite de débit : 30/min par membre ------------------------------
    // Fidèle A n'a encore rien envoyé : 30 envois acceptés, le 31e refusé.
    let statut30 = null;
    let statut31 = null;
    for (let i = 1; i <= 31; i += 1) {
      const r = await appel('POST', `/messagerie/conversations/${convAId}/messages`, jetonFideleA, {
        content: `Message débit ${i}.`,
      });
      if (i === 30) statut30 = r.statut;
      if (i === 31) statut31 = r;
    }
    verifier('30e message du membre : accepté (201)', statut30 === 201, `reçu ${statut30}`);
    verifier(
      '31e message du membre : refusé 429 rate_limited',
      statut31?.statut === 429 && statut31?.json?.error === 'rate_limited',
      statut31?.texte ?? '',
    );
  } finally {
    for (const ws of sockets) {
      try {
        ws.close();
      } catch {
        // Déjà fermée.
      }
    }
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
