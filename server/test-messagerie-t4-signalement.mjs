// Test d'intégration de la tranche T-Msg-4 (Messagerie : signalement /
// modération / recours + modifier / supprimer un message) :
// routes de signalement (motif, description 500 caractères maximum,
// preuve figée, routage local / mère / référent protection de
// l'enfance), file de modération (note motivée exigée, sourdine et
// suspension avec durée, escalade), recours (15 jours pour contester,
// 30 jours pour répondre), modification et suppression douce des
// messages, isolation entre églises et audit.
// Même forme que server/test-messagerie-t0.mjs : base fraîche créée
// puis vidée par le test lui-même, application du schéma puis des
// migrations avec le vrai moteur de migration, démarrage de l'API,
// appels HTTP.
//
// Usage : `node server/test-messagerie-t4-signalement.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4114).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_msg4.
// Base locale : PostgreSQL est nécessaire.

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);

const PORT = Number(process.env.PORT ?? 4114);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_msg4';
// Nom de la base visée par DATABASE_URL : c'est elle que le test recrée.
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-t11).
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

    // --- 1. Tables du schéma 034 ------------------------------------------
    const direct = new Client({ connectionString: DATABASE_URL });
    await direct.connect();
    const tables = await direct.query(
      `SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN ('reports', 'moderation_actions', 'appeals')`,
    );
    verifier('migration 034 : 3 tables signalement présentes', tables.rowCount === 3, `reçu ${tables.rowCount}`);
    await direct.end();

    // --- 2. Préparation par API : deux églises, quatre comptes -------------
    // L'église B devient fille de l'église A (escalade vers la mère).
    const mereA = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan', phone: '+2250102030405' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-msg4@example.com',
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
      email: 'fidele-exemple-msg4@example.com',
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
        email: 'admin-exemple-msg4-autre@example.com',
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
      email: 'fidele-exemple-msg4-autre@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080919',
    });
    verifier('inscription fidèle B par code', fideleB.statut === 201, fideleB.texte);
    const jetonFideleB = fideleB.json?.token;
    const fideleBUserId = fideleB.json?.user?.id;

    // Fiches membres + liaison users.member_id, puis rattachement de
    // l'église B à l'église A (église mère).
    const fiches = [
      { jeton: jetonAdminA, userId: adminAUserId, nom: 'Admin EXEMPLE', phone: '+2250708080910', email: 'admin-exemple-msg4@example.com' },
      { jeton: jetonAdminA, userId: fideleAUserId, nom: 'Fidèle EXEMPLE', phone: '+2250708080911', email: 'fidele-exemple-msg4@example.com' },
      { jeton: jetonAdminB, userId: adminBUserId, nom: 'Autre Admin EXEMPLE', phone: '+2250708080920', email: 'admin-exemple-msg4-autre@example.com' },
      { jeton: jetonAdminB, userId: fideleBUserId, nom: 'Autre Fidèle EXEMPLE', phone: '+2250708080921', email: 'fidele-exemple-msg4-autre@example.com' },
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
    await liaison.query(`UPDATE churches SET parent_church_id = $1 WHERE id = $2`, [
      egliseAId,
      egliseBId,
    ]);
    const rattachee = await liaison.query(
      `SELECT parent_church_id FROM churches WHERE id = $1`,
      [egliseBId],
    );
    verifier(
      'église B rattachée à l\'église A (mère)',
      rattachee.rows[0]?.parent_church_id === egliseAId,
    );
    await liaison.end();

    const membreFideleB = membreIds['fidele-exemple-msg4-autre@example.com'];
    const membreFideleA = membreIds['fidele-exemple-msg4@example.com'];

    // Conversations : directe B (adminB / fideleB) et directe A.
    const convB = await appel('POST', '/messagerie/conversations', jetonAdminB, {
      type: 'directe',
      participant_member_ids: [membreFideleB],
    });
    verifier('création conversation directe B', convB.statut === 201, convB.texte);
    const convBId = convB.json?.id;

    const convA = await appel('POST', '/messagerie/conversations', jetonAdminA, {
      type: 'directe',
      participant_member_ids: [membreFideleA],
    });
    verifier('création conversation directe A', convA.statut === 201, convA.texte);
    const convAId = convA.json?.id;

    const messageA = await appel('POST', `/messagerie/conversations/${convAId}/messages`, jetonAdminA, {
      content: 'Message de A, ne pas toucher.',
    });
    verifier('envoi message dans A', messageA.statut === 201, messageA.texte);

    // --- 3. Modifier / supprimer un message (église B) --------------------
    const m1 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Bonjour, version un.',
    });
    verifier('fidèle B envoie m1', m1.statut === 201, m1.texte);
    const m1Id = m1.json?.id;

    const m2 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonAdminB, {
      content: 'Réponse de l\'admin.',
    });
    verifier('admin B envoie m2', m2.statut === 201, m2.texte);
    const m2Id = m2.json?.id;

    const modif = await appel('PATCH', `/messagerie/conversations/${convBId}/messages/${m1Id}`, jetonFideleB, {
      content: 'Bonjour, version deux.',
    });
    verifier(
      'auteur modifie m1 (edited_at renseigné)',
      modif.statut === 200 && modif.json?.content === 'Bonjour, version deux.' && modif.json?.edited_at != null,
      modif.texte.slice(0, 200),
    );
    const modifAutre = await appel('PATCH', `/messagerie/conversations/${convBId}/messages/${m1Id}`, jetonAdminB, {
      content: 'Tentative de l\'admin.',
    });
    verifier('non-auteur modifie m1 = 403', modifAutre.statut === 403, modifAutre.texte);
    const modifVide = await appel('PATCH', `/messagerie/conversations/${convBId}/messages/${m1Id}`, jetonFideleB, {
      content: '',
    });
    verifier('modification vide = 400', modifVide.statut === 400, modifVide.texte);
    const modifAutreEglise = await appel('PATCH', `/messagerie/conversations/${convBId}/messages/${m1Id}`, jetonAdminA, {
      content: 'Depuis A.',
    });
    verifier('admin A modifie m1 (autre église) = 404', modifAutreEglise.statut === 404, modifAutreEglise.texte);

    const supprM2 = await appel('DELETE', `/messagerie/conversations/${convBId}/messages/${m2Id}`, jetonAdminB);
    verifier(
      'auteur supprime m2 (doucement)',
      supprM2.statut === 200 && supprM2.json?.content === 'Message supprimé' && supprM2.json?.deleted_at != null,
      supprM2.texte.slice(0, 200),
    );
    const listeApresSuppr = await appel('GET', `/messagerie/conversations/${convBId}/messages`, jetonFideleB);
    const m2Lu = Array.isArray(listeApresSuppr.json)
      ? listeApresSuppr.json.find((m) => m.id === m2Id)
      : null;
    verifier(
      'liste : m2 reste visible, contenu masqué',
      listeApresSuppr.statut === 200 && m2Lu?.content === 'Message supprimé' && m2Lu?.deleted_at != null,
      listeApresSuppr.texte.slice(0, 200),
    );
    const modifSupprime = await appel('PATCH', `/messagerie/conversations/${convBId}/messages/${m2Id}`, jetonAdminB, {
      content: 'Trop tard.',
    });
    verifier('modifier un message supprimé = 409', modifSupprime.statut === 409, modifSupprime.texte);
    const supprDeuxFois = await appel('DELETE', `/messagerie/conversations/${convBId}/messages/${m2Id}`, jetonAdminB);
    verifier('supprimer deux fois = 409', supprDeuxFois.statut === 409, supprDeuxFois.texte);
    const supprPropre = await appel('DELETE', `/messagerie/conversations/${convBId}/messages/${m1Id}`, jetonFideleB);
    verifier(
      'fidèle B supprime son propre m1',
      supprPropre.statut === 200 && supprPropre.json?.content === 'Message supprimé',
      supprPropre.texte.slice(0, 200),
    );

    // Suppression par modération : l'admin supprime le message d'un autre.
    const m3 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Message à modérer.',
    });
    verifier('fidèle B envoie m3', m3.statut === 201, m3.texte);
    const m3Id = m3.json?.id;
    const supprModeration = await appel('DELETE', `/messagerie/conversations/${convBId}/messages/${m3Id}`, jetonAdminB);
    verifier(
      'admin B supprime m3 (modération, non auteur)',
      supprModeration.statut === 200 && supprModeration.json?.deleted_at != null,
      supprModeration.texte.slice(0, 200),
    );
    const m4 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Message que je garde.',
    });
    const m4Id = m4.json?.id;
    const supprFideleA = await appel('DELETE', `/messagerie/conversations/${convBId}/messages/${m4Id}`, jetonFideleA);
    verifier('fidèle A supprime m4 (non participant) = 404', supprFideleA.statut === 404, supprFideleA.texte);
    // Preuve en base : m2 et m3 existent toujours, avec deleted_at.
    const preuveBase = new Client({ connectionString: DATABASE_URL });
    await preuveBase.connect();
    const supprimes = await preuveBase.query(
      `SELECT count(*)::int AS n FROM messages WHERE id = ANY($1) AND deleted_at IS NOT NULL`,
      [[m2Id, m3Id]],
    );
    verifier(
      'suppression douce : m2 et m3 toujours en base',
      supprimes.rows[0]?.n === 2,
      `reçu ${supprimes.rows[0]?.n}`,
    );
    await preuveBase.end();

    // --- 4. Signalement ----------------------------------------------------
    const m5 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Message à signaler.',
    });
    verifier('fidèle B envoie m5', m5.statut === 201, m5.texte);
    const m5Id = m5.json?.id;

    const signalement = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m5Id,
      reason: 'harassment',
      description: 'Propos déplacés envers un membre.',
    });
    verifier(
      'signalement m5 par admin B (local, en attente)',
      signalement.statut === 201 &&
        signalement.json?.status === 'pending' &&
        signalement.json?.routed_to === 'local' &&
        signalement.json?.evidence_snapshot?.content === 'Message à signaler.' &&
        typeof signalement.json?.evidence_hash === 'string' &&
        signalement.json.evidence_hash.length === 64,
      signalement.texte.slice(0, 300),
    );
    const signalementId = signalement.json?.id;
    const marque = new Client({ connectionString: DATABASE_URL });
    await marque.connect();
    const signale = await marque.query(
      `SELECT is_reported FROM messages WHERE id = $1`,
      [m5Id],
    );
    verifier('message m5 marqué is_reported', signale.rows[0]?.is_reported === true);
    await marque.end();

    const mauvaisMotif = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m5Id,
      reason: 'erreur_doctrinale',
    });
    verifier('motif hors enum 034 = 400', mauvaisMotif.statut === 400, mauvaisMotif.texte);
    const tropLongue = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m5Id,
      reason: 'spam',
      description: 'x'.repeat(501),
    });
    verifier('description 501 caractères = 400', tropLongue.statut === 400, tropLongue.texte);
    const signaleA = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: messageA.json?.id,
      reason: 'spam',
    });
    verifier('signaler un message de A (autre église) = 404', signaleA.statut === 404, signaleA.texte);
    const signaleNonParticipant = await appel('POST', '/messagerie/signalements', jetonFideleA, {
      target_type: 'message',
      target_id: m5Id,
      reason: 'spam',
    });
    verifier('non participant signale m5 = 404', signaleNonParticipant.statut === 404, signaleNonParticipant.texte);

    // Sécurité d'un enfant : routage forcé vers le référent, hors circuit.
    const m6 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Message sensible.',
    });
    const m6Id = m6.json?.id;
    const signaleEnfant = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m6Id,
      reason: 'child_safety',
      routed_to: 'mother',
      description: 'Contenu inapproprié pour un mineur.',
    });
    verifier(
      'child_safety force le routage référent (même avec mother demandé)',
      signaleEnfant.statut === 201 &&
        signaleEnfant.json?.routed_to === 'child_safety_referent' &&
        signaleEnfant.json?.routed_to_church_id == null,
      signaleEnfant.texte.slice(0, 300),
    );

    // Signalement d'une conversation entière.
    const signaleConv = await appel('POST', '/messagerie/signalements', jetonFideleB, {
      target_type: 'conversation',
      target_id: convBId,
      reason: 'other',
      description: 'Conversation devenue hostile.',
    });
    verifier(
      'signalement de la conversation B',
      signaleConv.statut === 201 && signaleConv.json?.target_type === 'conversation',
      signaleConv.texte.slice(0, 300),
    );
    const signalementConvId = signaleConv.json?.id;

    // Signalement vers l'église mère.
    const m7 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Message pour la mère.',
    });
    const m7Id = m7.json?.id;
    const signaleMere = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m7Id,
      reason: 'misinformation',
      routed_to: 'mother',
    });
    verifier(
      'signalement vers la mère (routed_to_church_id = A)',
      signaleMere.statut === 201 &&
        signaleMere.json?.routed_to === 'mother' &&
        signaleMere.json?.routed_to_church_id === egliseAId,
      signaleMere.texte.slice(0, 300),
    );
    const signalementMereId = signaleMere.json?.id;

    // File de modération : accès et isolation.
    const listeFidele = await appel('GET', '/messagerie/signalements', jetonFideleB);
    verifier('fidèle B liste les signalements = 403', listeFidele.statut === 403, listeFidele.texte);
    const listeAdminB = await appel('GET', '/messagerie/signalements', jetonAdminB);
    verifier(
      'admin B liste 4 signalements de son église',
      listeAdminB.statut === 200 && Array.isArray(listeAdminB.json) && listeAdminB.json.length === 4,
      listeAdminB.texte.slice(0, 300),
    );
    const listeAdminA = await appel('GET', '/messagerie/signalements', jetonAdminA);
    verifier(
      'admin A liste 1 signalement transmis (escalade mère)',
      listeAdminA.statut === 200 &&
        Array.isArray(listeAdminA.json) &&
        listeAdminA.json.length === 1 &&
        listeAdminA.json[0]?.escalade === true &&
        listeAdminA.json[0]?.reporter_nom === undefined,
      listeAdminA.texte.slice(0, 300),
    );
    const listeFiltre = await appel('GET', '/messagerie/signalements?statut=pending', jetonAdminB);
    verifier(
      'filtre statut=pending : 4 signalements',
      listeFiltre.statut === 200 && Array.isArray(listeFiltre.json) && listeFiltre.json.length === 4,
      listeFiltre.texte.slice(0, 200),
    );
    const listeFiltreMauvais = await appel('GET', '/messagerie/signalements?statut=bogus', jetonAdminB);
    verifier('filtre statut invalide = 400', listeFiltreMauvais.statut === 400, listeFiltreMauvais.texte);
    const detailMere = await appel('GET', `/messagerie/signalements/${signalementMereId}`, jetonAdminA);
    verifier(
      'admin A lit le détail transmis (lecture seule, sans reporter_nom)',
      detailMere.statut === 200 && detailMere.json?.reporter_nom === undefined && detailMere.json?.actions === undefined,
      detailMere.texte.slice(0, 300),
    );
    const detailAutreEglise = await appel('GET', `/messagerie/signalements/${signalementId}`, jetonAdminA);
    verifier('admin A lit un signalement local de B = 404', detailAutreEglise.statut === 404, detailAutreEglise.texte);

    // --- 5. Modération -----------------------------------------------------
    const detailB = await appel('GET', `/messagerie/signalements/${signalementId}`, jetonAdminB);
    verifier(
      'admin B lit le détail (reporter_nom, actions, recours)',
      detailB.statut === 200 &&
        detailB.json?.reporter_nom === 'Autre Admin EXEMPLE' &&
        Array.isArray(detailB.json?.actions) &&
        Array.isArray(detailB.json?.recours),
      detailB.texte.slice(0, 300),
    );
    const actionSansNote = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonAdminB, {
      action: 'avertir',
      notes: '',
    });
    verifier('action sans note motivée = 400', actionSansNote.statut === 400, actionSansNote.texte);
    const actionInvalide = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonAdminB, {
      action: 'bannir',
      notes: 'Note.',
    });
    verifier('action inconnue = 400', actionInvalide.statut === 400, actionInvalide.texte);
    const sourdineSansDuree = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonAdminB, {
      action: 'sourdine',
      notes: 'Note.',
    });
    verifier('sourdine sans durée = 400', sourdineSansDuree.statut === 400, sourdineSansDuree.texte);
    const sourdineMauvaiseDuree = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonAdminB, {
      action: 'sourdine',
      notes: 'Note.',
      duree_heures: 25,
    });
    verifier('sourdine durée 25 h = 400', sourdineMauvaiseDuree.statut === 400, sourdineMauvaiseDuree.texte);
    const avertirAvecDuree = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonAdminB, {
      action: 'avertir',
      notes: 'Note.',
      duree_heures: 24,
    });
    verifier('avertir avec durée = 400', avertirAvecDuree.statut === 400, avertirAvecDuree.texte);
    const actionNonAdmin = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonFideleB, {
      action: 'avertir',
      notes: 'Note.',
    });
    verifier('fidèle B traite un signalement = 403', actionNonAdmin.statut === 403, actionNonAdmin.texte);
    const actionMere = await appel('POST', `/messagerie/signalements/${signalementMereId}/actions`, jetonAdminA, {
      action: 'avertir',
      notes: 'Note de la mère.',
    });
    verifier('admin A traite un signalement transmis = 403', actionMere.statut === 403, actionMere.texte);

    const avertir = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonAdminB, {
      action: 'avertir',
      notes: 'Avertissement : propos à modérer.',
    });
    verifier(
      'avertir : 201, signalement résolu',
      avertir.statut === 201 && avertir.json?.report_status === 'resolved',
      avertir.texte.slice(0, 300),
    );
    const actionDeuxFois = await appel('POST', `/messagerie/signalements/${signalementId}/actions`, jetonAdminB, {
      action: 'rejeter',
      notes: 'Trop tard.',
    });
    verifier('deuxième action sur signalement résolu = 409', actionDeuxFois.statut === 409, actionDeuxFois.texte);

    // Rejeter : ferme sans sanction.
    const rejeter = await appel('POST', `/messagerie/signalements/${signalementConvId}/actions`, jetonAdminB, {
      action: 'rejeter',
      notes: 'Conversation normale, rien à signaler.',
    });
    verifier(
      'rejeter : 201, signalement dismissed',
      rejeter.statut === 201 && rejeter.json?.report_status === 'dismissed',
      rejeter.texte.slice(0, 200),
    );

    // Sourdine : bloque l'auteur dans la conversation signalée.
    const signaleSourdine = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m7Id,
      reason: 'spam',
    });
    const sourdineId = signaleSourdine.json?.id;
    verifier('signalement pour sourdine', signaleSourdine.statut === 201, signaleSourdine.texte);
    const sourdine = await appel('POST', `/messagerie/signalements/${sourdineId}/actions`, jetonAdminB, {
      action: 'sourdine',
      notes: 'Sourdine 24 h dans cette conversation.',
      duree_heures: 24,
    });
    verifier('sourdine 24 h : 201', sourdine.statut === 201, sourdine.texte.slice(0, 200));
    const muet = new Client({ connectionString: DATABASE_URL });
    await muet.connect();
    const muetLigne = await muet.query(
      `SELECT muted_until FROM conversation_participants WHERE conversation_id = $1 AND member_id = $2`,
      [convBId, membreFideleB],
    );
    verifier(
      'muted_until posé pour fidèle B dans la conversation',
      muetLigne.rows[0]?.muted_until != null &&
        new Date(muetLigne.rows[0].muted_until).getTime() > Date.now(),
    );
    await muet.end();
    const envoiMuet = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Je suis muet ?',
    });
    verifier('fidèle B muet : envoi refusé 403', envoiMuet.statut === 403, envoiMuet.texte);
    const envoiAdminOk = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonAdminB, {
      content: 'L\'admin écrit toujours.',
    });
    verifier('admin B non muet : envoi 201', envoiAdminOk.statut === 201, envoiAdminOk.texte);
    // Levée de la sourdine pour la suite des tests.
    const levee = new Client({ connectionString: DATABASE_URL });
    await levee.connect();
    await levee.query(
      `UPDATE conversation_participants SET muted_until = NULL WHERE member_id = $1`,
      [membreFideleB],
    );
    await levee.end();

    // Suspension : bloque l'auteur dans toute la messagerie de l'église.
    const convB2 = await appel('POST', '/messagerie/conversations', jetonAdminB, {
      type: 'directe',
      participant_member_ids: [membreFideleB],
    });
    const convB2Id = convB2.json?.id;
    const m8 = await appel('POST', `/messagerie/conversations/${convB2Id}/messages`, jetonFideleB, {
      content: 'Message dans la deuxième conversation.',
    });
    const m8Id = m8.json?.id;
    const signaleSuspension = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m8Id,
      reason: 'threat',
    });
    const suspensionId = signaleSuspension.json?.id;
    verifier('signalement pour suspension', signaleSuspension.statut === 201, signaleSuspension.texte);
    const suspendre = await appel('POST', `/messagerie/signalements/${suspensionId}/actions`, jetonAdminB, {
      action: 'suspendre',
      notes: 'Suspension 168 h de la messagerie.',
      duree_heures: 168,
    });
    verifier('suspendre 168 h : 201', suspendre.statut === 201, suspendre.texte.slice(0, 200));
    const suspendu = new Client({ connectionString: DATABASE_URL });
    await suspendu.connect();
    const suspenduLignes = await suspendu.query(
      `SELECT count(*)::int AS n FROM conversation_participants
        WHERE church_id = $1 AND member_id = $2 AND muted_until > NOW()`,
      [egliseBId, membreFideleB],
    );
    verifier(
      'suspension : muted_until sur les 2 conversations de fidèle B',
      suspenduLignes.rows[0]?.n === 2,
      `reçu ${suspenduLignes.rows[0]?.n}`,
    );
    await suspendu.end();
    const envoiSuspendu = await appel('POST', `/messagerie/conversations/${convB2Id}/messages`, jetonFideleB, {
      content: 'Je suis suspendu ?',
    });
    verifier('fidèle B suspendu : envoi refusé 403', envoiSuspendu.statut === 403, envoiSuspendu.texte);
    const levee2 = new Client({ connectionString: DATABASE_URL });
    await levee2.connect();
    await levee2.query(
      `UPDATE conversation_participants SET muted_until = NULL WHERE member_id = $1`,
      [membreFideleB],
    );
    await levee2.end();

    // Escalade par le modérateur.
    const signaleEscalade = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m7Id,
      reason: 'hate_speech',
    });
    const escaladeId = signaleEscalade.json?.id;
    verifier('signalement pour escalade', signaleEscalade.statut === 201, signaleEscalade.texte);
    const escalade = await appel('POST', `/messagerie/signalements/${escaladeId}/escalade`, jetonAdminB, {
      destination: 'mother',
    });
    verifier(
      'escalade vers la mère : 200, statut escalated',
      escalade.statut === 200 && escalade.json?.status === 'escalated' && escalade.json?.routed_to_church_id === egliseAId,
      escalade.texte.slice(0, 300),
    );
    const actionApresEscalade = await appel('POST', `/messagerie/signalements/${escaladeId}/actions`, jetonAdminB, {
      action: 'avertir',
      notes: 'Trop tard.',
    });
    verifier('action après escalade = 409', actionApresEscalade.statut === 409, actionApresEscalade.texte);
    // Escalade impossible sans église mère (église A).
    const signaleA2 = await appel('POST', '/messagerie/signalements', jetonAdminA, {
      target_type: 'message',
      target_id: messageA.json?.id,
      reason: 'spam',
    });
    const signaleA2Id = signaleA2.json?.id;
    verifier('signalement dans A', signaleA2.statut === 201, signaleA2.texte);
    const escaladeSansMere = await appel('POST', `/messagerie/signalements/${signaleA2Id}/escalade`, jetonAdminA, {
      destination: 'mother',
    });
    verifier('escalade sans église mère = 409', escaladeSansMere.statut === 409, escaladeSansMere.texte);
    const escaladeReferent = await appel('POST', `/messagerie/signalements/${signaleA2Id}/escalade`, jetonAdminA, {
      destination: 'child_safety_referent',
    });
    verifier(
      'escalade vers le référent : 200',
      escaladeReferent.statut === 200 && escaladeReferent.json?.routed_to === 'child_safety_referent',
      escaladeReferent.texte.slice(0, 200),
    );

    // --- 6. Recours ---------------------------------------------------------
    // Mes sanctions : fidèle B a été averti (m5), mis en sourdine (m7)
    // et suspendu (m8).
    const mesSanctions = await appel('GET', '/messagerie/mes-sanctions', jetonFideleB);
    verifier(
      'fidèle B voit ses 3 sanctions (avertir, sourdine, suspendre), sans nom de rapporteur',
      mesSanctions.statut === 200 &&
        Array.isArray(mesSanctions.json) &&
        mesSanctions.json.length === 3 &&
        mesSanctions.json.every((s) => s.contestable === true && s.contester_avant != null) &&
        mesSanctions.json.every((s) => s.reporter_nom === undefined),
      mesSanctions.texte.slice(0, 400),
    );
    const mesSanctionsAdmin = await appel('GET', '/messagerie/mes-sanctions', jetonAdminB);
    verifier(
      'admin B voit zéro sanction',
      mesSanctionsAdmin.statut === 200 && Array.isArray(mesSanctionsAdmin.json) && mesSanctionsAdmin.json.length === 0,
      mesSanctionsAdmin.texte.slice(0, 200),
    );
    // Contester l'avertissement (signalement m5, résolu).
    const recours = await appel('POST', `/messagerie/signalements/${signalementId}/recours`, jetonFideleB, {
      reason: 'Je conteste : mes propos ont été mal compris.',
    });
    verifier(
      'recours de fidèle B : 201, repondre_avant (30 jours) présent',
      recours.statut === 201 && recours.json?.status === 'pending' && recours.json?.repondre_avant != null,
      recours.texte.slice(0, 300),
    );
    const recoursId = recours.json?.id;
    const recoursDeuxFois = await appel('POST', `/messagerie/signalements/${signalementId}/recours`, jetonFideleB, {
      reason: 'Encore.',
    });
    verifier('deuxième recours en cours = 409', recoursDeuxFois.statut === 409, recoursDeuxFois.texte);
    const recoursAutre = await appel('POST', `/messagerie/signalements/${signalementId}/recours`, jetonAdminB, {
      reason: 'Pas moi.',
    });
    verifier('recours par une autre personne = 403', recoursAutre.statut === 403, recoursAutre.texte);
    const detailAppeal = await appel('GET', `/messagerie/signalements/${signalementId}`, jetonAdminB);
    verifier(
      'signalement contesté : statut appealed',
      detailAppeal.statut === 200 && detailAppeal.json?.status === 'appealed',
      detailAppeal.texte.slice(0, 200),
    );
    const listeRecours = await appel('GET', `/messagerie/signalements/${signalementId}/recours`, jetonAdminB);
    verifier(
      'modérateur liste 1 recours',
      listeRecours.statut === 200 && Array.isArray(listeRecours.json) && listeRecours.json.length === 1,
      listeRecours.texte.slice(0, 200),
    );
    const traiterMauvaisStatut = await appel('POST', `/messagerie/recours/${recoursId}/traiter`, jetonAdminB, {
      statut: 'en_cours',
    });
    verifier('traiter recours avec statut invalide = 400', traiterMauvaisStatut.statut === 400, traiterMauvaisStatut.texte);
    const traiterRejet = await appel('POST', `/messagerie/recours/${recoursId}/traiter`, jetonAdminB, {
      statut: 'dismissed',
    });
    verifier('recours rejeté : 200', traiterRejet.statut === 200, traiterRejet.texte.slice(0, 200));
    const detailApresRejet = await appel('GET', `/messagerie/signalements/${signalementId}`, jetonAdminB);
    verifier(
      'après rejet du recours : signalement de nouveau resolved',
      detailApresRejet.statut === 200 && detailApresRejet.json?.status === 'resolved',
      detailApresRejet.texte.slice(0, 200),
    );
    const traiterDeuxFois = await appel('POST', `/messagerie/recours/${recoursId}/traiter`, jetonAdminB, {
      statut: 'resolved',
    });
    verifier('traiter un recours déjà traité = 409', traiterDeuxFois.statut === 409, traiterDeuxFois.texte);

    // Recours accepté : la sanction est annulée, la sourdine levée.
    const signaleRecoursOk = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m7Id,
      reason: 'spam',
    });
    const recoursOkId = signaleRecoursOk.json?.id;
    verifier('signalement pour recours accepté', signaleRecoursOk.statut === 201, signaleRecoursOk.texte);
    await appel('POST', `/messagerie/signalements/${recoursOkId}/actions`, jetonAdminB, {
      action: 'sourdine',
      notes: 'Sourdine 24 h.',
      duree_heures: 24,
    });
    const envoiMuet2 = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Toujours muet ?',
    });
    verifier('fidèle B muet après sourdine (recours à venir) = 403', envoiMuet2.statut === 403, envoiMuet2.texte);
    const recoursOk = await appel('POST', `/messagerie/signalements/${recoursOkId}/recours`, jetonFideleB, {
      reason: 'Erreur de modération, je demande réparation.',
    });
    verifier('recours sur la sourdine : 201', recoursOk.statut === 201, recoursOk.texte.slice(0, 200));
    const recoursOkTraite = await appel('POST', `/messagerie/recours/${recoursOk.json?.id}/traiter`, jetonAdminB, {
      statut: 'resolved',
    });
    verifier('recours accepté : 200', recoursOkTraite.statut === 200, recoursOkTraite.texte.slice(0, 200));
    const detailRecoursOk = await appel('GET', `/messagerie/signalements/${recoursOkId}`, jetonAdminB);
    verifier(
      'après recours accepté : signalement dismissed',
      detailRecoursOk.statut === 200 && detailRecoursOk.json?.status === 'dismissed',
      detailRecoursOk.texte.slice(0, 200),
    );
    const envoiApresRecours = await appel('POST', `/messagerie/conversations/${convBId}/messages`, jetonFideleB, {
      content: 'Je peux de nouveau écrire.',
    });
    verifier('sourdine levée après recours accepté : envoi 201', envoiApresRecours.statut === 201, envoiApresRecours.texte);

    // Délai de recours dépassé (15 jours) : sanction vieillie en base.
    const signaleDelai = await appel('POST', '/messagerie/signalements', jetonAdminB, {
      target_type: 'message',
      target_id: m7Id,
      reason: 'spam',
    });
    const delaiId = signaleDelai.json?.id;
    verifier('signalement pour délai dépassé', signaleDelai.statut === 201, signaleDelai.texte);
    await appel('POST', `/messagerie/signalements/${delaiId}/actions`, jetonAdminB, {
      action: 'avertir',
      notes: 'Avertissement ancien.',
    });
    const vieilli = new Client({ connectionString: DATABASE_URL });
    await vieilli.connect();
    await vieilli.query(
      `UPDATE moderation_actions SET created_at = NOW() - INTERVAL '16 days' WHERE report_id = $1`,
      [delaiId],
    );
    await vieilli.end();
    const recoursTard = await appel('POST', `/messagerie/signalements/${delaiId}/recours`, jetonFideleB, {
      reason: 'Trop tard.',
    });
    verifier('recours après 15 jours = 409', recoursTard.statut === 409, recoursTard.texte);
    const sanctionsApresDelai = await appel('GET', '/messagerie/mes-sanctions', jetonFideleB);
    const sanctionVieille = Array.isArray(sanctionsApresDelai.json)
      ? sanctionsApresDelai.json.find((s) => s.report_id === delaiId)
      : null;
    verifier(
      'mes-sanctions : sanction de 16 jours non contestable',
      sanctionsApresDelai.statut === 200 && sanctionVieille?.contestable === false,
      sanctionsApresDelai.texte.slice(0, 300),
    );

    // --- 7. Super administrateur : aucun accès ----------------------------
    const directSuper = new Client({ connectionString: DATABASE_URL });
    await directSuper.connect();
    const hashSuper = await argon2.hash('MotDePasse123!');
    const superLigne = await directSuper.query(
      `INSERT INTO users (email, password_hash, full_name)
       VALUES ($1, $2, $3) RETURNING id`,
      ['super-exemple-msg4@example.com', hashSuper, 'Super EXEMPLE'],
    );
    const superUserId = superLigne.rows[0]?.id;
    await directSuper.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'super_admin')`,
      [superUserId, egliseAId],
    );
    await directSuper.end();
    const loginSuper = await appel('POST', '/auth/login', null, {
      identifiant: 'super-exemple-msg4@example.com',
      password: 'MotDePasse123!',
      channel: 'web',
      plateforme: true,
    });
    verifier('connexion Plateforme super_admin', loginSuper.statut === 200, loginSuper.texte.slice(0, 200));
    const listeSuper = await appel('GET', '/messagerie/signalements', loginSuper.json?.token);
    verifier('super_admin liste les signalements = 403', listeSuper.statut === 403, listeSuper.texte);

    // --- 8. Audit ----------------------------------------------------------
    const audit = new Client({ connectionString: DATABASE_URL });
    await audit.connect();
    const traces = await audit.query(
      `SELECT action, count(*)::int AS n FROM audit_logs
        WHERE church_id = $1
          AND action IN ('messagerie.signalement_cree', 'messagerie.moderation_action',
                         'messagerie.signalement_escalade', 'messagerie.recours_cree',
                         'messagerie.recours_traite', 'messagerie.message_modifie',
                         'messagerie.message_supprime')
        GROUP BY action`,
      [egliseBId],
    );
    const parAction = Object.fromEntries(traces.rows.map((r) => [r.action, r.n]));
    verifier(
      'audit : signalements, modérations, escalades, recours, modifications, suppressions journalisés',
      (parAction['messagerie.signalement_cree'] ?? 0) >= 6 &&
        (parAction['messagerie.moderation_action'] ?? 0) >= 5 &&
        (parAction['messagerie.signalement_escalade'] ?? 0) >= 1 &&
        (parAction['messagerie.recours_cree'] ?? 0) >= 2 &&
        (parAction['messagerie.recours_traite'] ?? 0) >= 2 &&
        (parAction['messagerie.message_modifie'] ?? 0) >= 1 &&
        (parAction['messagerie.message_supprime'] ?? 0) >= 3,
      JSON.stringify(parAction),
    );
    await audit.end();
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
