// Test d'intégration de l'envoi des rapports d'annexe par courriel
// (tranche P5, Lot B) : le PDF du rapport est généré et envoyé en
// pièce jointe à l'église mère, puis le statut passe à `envoye`.
//
// AUCUN vrai courriel n'est envoyé :
//   - Partie A (mailer, en processus) : transport simulé injecté
//     (streamTransport nodemailer) ; le message est capturé en mémoire.
//   - Partie B (routes) : le serveur est démarré avec
//     NODE_ENV=test + MAIL_TRANSPORT=stream (transport en mémoire) ;
//     un second serveur, sans ces variables, couvre le cas « SMTP non
//     configuré ».
//   - Partie D (PDF, en processus) : le message libre tient
//     intégralement dans le PDF, découpé en lignes de 94 caractères
//     maximum (correctif relecture PR #67).
//   - Les bases sont éphémères (créées puis supprimées).
//
// Usage (depuis la racine du dépôt, après `npm run build` dans
// server/) : `node server/test-lot-b-p5-envoi-courriel.mjs`
// Variables : PORT (défaut 4106), PORT_SANS_SMTP (défaut 4107).
// PostgreSQL local requis (utilisateur postgres / postgres).

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import nodemailer from 'nodemailer';
import {
  envoiCourrielDisponible,
  sendMail,
  setTransportCourrielPourTests,
} from './dist/mailer.js';
import {
  construirePdfRapport,
  decouperLignesMessage,
} from './dist/routes/rapports_annexe.js';

const exec = promisify(execFile);
const JWT_SECRET = 'test-secret-p5-envoi-32-caracteres';
const ADMIN = 'postgres://postgres:postgres@127.0.0.1:5432/postgres';

let echecs = 0;
function verifier(nom, condition, detail = '') {
  if (condition) {
    console.log(`  OK ${nom}`);
  } else {
    echecs += 1;
    console.log(`  ECHEC ${nom} ${detail}`);
  }
}

async function appel(base, methode, chemin, jeton, corps) {
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

// ---------------------------------------------------------------------------
// Partie A — mailer.ts, en processus, transport simulé.
// ---------------------------------------------------------------------------
async function partieA() {
  console.log('A. mailer.ts (transport simulé, aucun vrai courriel) :');
  delete process.env.MAIL_TRANSPORT;

  verifier(
    'sans SMTP ni transport injecté : envoi indisponible',
    envoiCourrielDisponible() === false,
  );
  verifier(
    'sans SMTP ni transport injecté : sendMail renvoie faux',
    (await sendMail('mere@test.ci', 'Sujet', 'Texte')) === false,
  );

  // Transport simulé en mémoire, message capturé.
  const transport = nodemailer.createTransport({
    streamTransport: true,
    buffer: true,
  });
  const captures = [];
  const envoyerOrigine = transport.sendMail.bind(transport);
  transport.sendMail = async (mail) => {
    const info = await envoyerOrigine(mail);
    captures.push(info);
    return info;
  };
  setTransportCourrielPourTests(transport);
  try {
    verifier(
      'transport injecté : envoi disponible',
      envoiCourrielDisponible() === true,
    );
    const pdf = Buffer.from('%PDF-1.4 test');
    const ok = await sendMail('mere@test.ci', 'Rapport Bilan annuel', 'Texte', [
      {
        filename: 'rapport-annexe-bilan_annuel-2026-11-12.pdf',
        content: pdf,
        contentType: 'application/pdf',
      },
    ]);
    verifier('sendMail avec pièce jointe PDF : vrai', ok === true);
    const message = String(captures[0]?.message ?? '');
    verifier(
      'message capturé : pièce jointe PDF (nom, type, contenu)',
      message.includes('application/pdf') &&
        message.includes('rapport-annexe-bilan_annuel-2026-11-12.pdf') &&
        message.includes(pdf.toString('base64')),
      message.slice(0, 200),
    );
    verifier(
      'message capturé : destinataire et sujet',
      message.includes('mere@test.ci') &&
        message.includes('Rapport Bilan annuel'),
    );
  } finally {
    setTransportCourrielPourTests(null);
  }
  verifier(
    'transport retiré : envoi de nouveau indisponible',
    envoiCourrielDisponible() === false,
  );

  // Transport en panne : sendMail renvoie faux, sans lever.
  setTransportCourrielPourTests({
    sendMail: async () => {
      throw new Error('SMTP simulé en panne');
    },
  });
  try {
    verifier(
      'transport en panne : sendMail renvoie faux',
      (await sendMail('mere@test.ci', 'Sujet', 'Texte')) === false,
    );
  } finally {
    setTransportCourrielPourTests(null);
  }
}

// ---------------------------------------------------------------------------
// Partie D — PDF du rapport (en processus) : le message libre tient
// intégralement dans le PDF, découpé en lignes de 94 caractères max.
// ---------------------------------------------------------------------------

/** Texte littéral d'un PDF minimal (chaînes entre parenthèses, échappements défaits). */
function extraireTextePdf(pdf) {
  const texte = pdf.toString('latin1');
  const morceaux = [];
  const re = /\((?:\\.|[^\\()])*\)/g;
  let m;
  while ((m = re.exec(texte)) !== null) {
    morceaux.push(m[0].slice(1, -1).replace(/\\([()\\])/g, '$1'));
  }
  return morceaux;
}

const MESSAGE_LONG =
  "Message de test pour vérifier que le rapport complet parvient bien à l'église mère : " +
  'bilan annuel positif, quarante-deux membres actifs, recettes en hausse, dépenses maîtrisées, ' +
  "merci pour votre accompagnement et vos prières tout au long de l'année écoulée.";

function normaliser(texte) {
  return texte.replace(/\s+/g, ' ').trim();
}

async function partieD() {
  console.log('D. PDF du rapport (message libre intégral, en processus) :');

  // Découpe : chaque ligne ≤ 94 caractères, préfixe sur la première.
  const lignes = decouperLignesMessage(MESSAGE_LONG);
  verifier(
    'découpe : première ligne préfixée « Message : »',
    lignes.length > 1 && lignes[0].startsWith('Message : '),
    lignes.join(' | '),
  );
  verifier(
    'découpe : chaque ligne ≤ 94 caractères',
    lignes.every((l) => l.length <= 94),
    lignes.map((l) => l.length).join(','),
  );
  verifier(
    'découpe : le message est conservé intégralement',
    normaliser(lignes.join(' ').replace('Message : ', '')) ===
      normaliser(MESSAGE_LONG),
  );

  // Mot isolé plus long qu'une ligne : coupé, rien perdu.
  const motLong = 'a'.repeat(200);
  const lignesMot = decouperLignesMessage(motLong);
  verifier(
    'mot de 200 caractères : découpé en lignes ≤ 94, rien perdu',
    lignesMot.every((l) => l.length <= 94) &&
      lignesMot.join('').replace('Message : ', '') === motLong,
  );
  verifier(
    'message vide : aucune ligne',
    decouperLignesMessage('   ').length === 0,
  );

  // PDF généré : le message intégral s'y retrouve.
  const { pdf } = construirePdfRapport(
    {
      id: '00000000-0000-0000-0000-000000000000',
      type: 'bilan_annuel',
      message: MESSAGE_LONG,
      membres: 42,
      recettes_fcfa: 120000,
      depenses_fcfa: 80000,
      solde_fcfa: 40000,
      statut: 'en_attente_envoi',
      cree_le: '2026-11-12T00:00:00.000Z',
    },
    'Annexe ENVOI',
    'Église mère ENVOI',
  );
  const extraits = extraireTextePdf(pdf);
  const texteJoint = normaliser(extraits.join(' '));
  verifier(
    'PDF : le message intégral est présent',
    texteJoint.includes(normaliser(MESSAGE_LONG)),
    texteJoint.slice(0, 200),
  );
  // Chaque ligne du message dans le PDF fait ≤ 94 caractères.
  const debut = extraits.findIndex((t) => t.startsWith('Message : '));
  const fin = extraits.findIndex(
    (t, i) => i > debut && t === 'Chiffres du rapport',
  );
  const lignesMessage = extraits.slice(debut, fin === -1 ? undefined : fin);
  verifier(
    'PDF : chaque ligne du message ≤ 94 caractères',
    debut !== -1 &&
      lignesMessage.length > 1 &&
      lignesMessage.every((l) => l.length <= 94),
    lignesMessage.map((l) => l.length).join(','),
  );
}

// ---------------------------------------------------------------------------
// Partie B — routes, serveur démarré.
// ---------------------------------------------------------------------------
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

async function preparerReseau({ nomDb, port, envServeur, suffixe }) {
  const databaseUrl = `postgres://postgres:postgres@127.0.0.1:5432/${nomDb}`;
  await creerBase(nomDb);
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL: databaseUrl },
  });
  const base = `http://127.0.0.1:${port}`;
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: {
      ...process.env,
      DATABASE_URL: databaseUrl,
      PORT: String(port),
      JWT_SECRET,
      ...envServeur,
    },
    stdio: 'pipe',
  });
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
  verifier(`API démarrée sur ${port} (/sante)`, pret);
  if (!pret) throw new Error(`API non démarrée sur ${port}`);
  const pool = new Client({ connectionString: databaseUrl });
  await pool.connect();

  // Mère + annexe (inscription imbriquée, rattachement accepté).
  const mere = await appel(base, 'POST', '/auth/register', null, {
    eglise: { name: 'Église mère ENVOI', city: 'Abidjan' },
    admin: {
      full_name: 'Admin mère ENVOI',
      email: `admin-mere-envoi-${suffixe}@example.com`,
      password: 'MotDePasse123!',
    },
  });
  verifier('inscription église mère', mere.statut === 201, mere.texte);
  const jetonMere = mere.json?.token;
  const mereId = mere.json?.church?.id;
  const annexe = await appel(base, 'POST', '/auth/register', null, {
    eglise: {
      name: 'Annexe ENVOI',
      city: 'Abidjan',
      parent_code: mere.json?.church?.code,
    },
    admin: {
      full_name: 'Admin annexe ENVOI',
      email: `admin-annexe-envoi-${suffixe}@example.com`,
      password: 'MotDePasse123!',
    },
  });
  verifier('inscription annexe', annexe.statut === 201, annexe.texte);
  const jetonAnnexe = annexe.json?.token;
  const acceptation = await appel(
    base,
    'POST',
    `/rattachements/${annexe.json?.rattachement?.id}/accepter`,
    jetonMere,
  );
  verifier(
    'rattachement de l’annexe accepté',
    acceptation.statut === 200 && acceptation.json?.status === 'acceptee',
    acceptation.texte,
  );
  return { base, api, pool, jetonMere, jetonAnnexe, mereId };
}

async function arreterReseau(reseau) {
  reseau.api.kill();
  await once(reseau.api, 'exit').catch(() => {});
  await reseau.pool.end().catch(() => {});
}

async function main() {
  await partieA();
  await partieD();

  // --- Réseau 1 : transport simulé (NODE_ENV=test + MAIL_TRANSPORT=stream).
  console.log('B. routes avec transport simulé :');
  const port1 = Number(process.env.PORT ?? 4106);
  const reseau1 = await preparerReseau({
    nomDb: 'e_system_church_test_p5_envoi',
    port: port1,
    envServeur: { NODE_ENV: 'test', MAIL_TRANSPORT: 'stream' },
    suffixe: 's1',
  });
  try {
    const { base, pool, jetonMere, jetonAnnexe, mereId } = reseau1;

    // La mère a une adresse e-mail : l'envoi part, statut envoye.
    await pool.query('UPDATE churches SET email = $1 WHERE id = $2', [
      'mere-envoi@example.ci',
      mereId,
    ]);
    const envoi = await appel(base, 'POST', '/moi/rapports-annexe', jetonAnnexe, {
      type: 'bilan_annuel',
      message: 'Bilan ENVOI',
      membres: 42,
      recettes_fcfa: 120000,
      depenses_fcfa: 80000,
      solde_fcfa: 40000,
    });
    verifier(
      'mère avec e-mail : rapport envoyé (statut envoye)',
      envoi.statut === 200 &&
        envoi.json?.statut === 'envoye' &&
        envoi.json?.envoi_email === 'envoye' &&
        envoi.json?.type === 'bilan_annuel' &&
        envoi.json?.membres === 42,
      envoi.texte,
    );
    const idEnvoye = envoi.json?.id;
    const recus = await appel(base, 'GET', '/moi/rapports-annexe/recus', jetonMere);
    verifier(
      'mère : rapport reçu avec le statut envoye',
      recus.statut === 200 &&
        recus.json?.length === 1 &&
        recus.json[0]?.statut === 'envoye' &&
        recus.json[0]?.eglise_nom === 'Annexe ENVOI',
      recus.texte,
    );
    const audits = await pool.query(
      `SELECT action FROM audit_logs WHERE action = 'rapport_annexe.envoye'`,
    );
    verifier(
      'envoi journalisé (audit_logs rapport_annexe.envoye)',
      audits.rowCount === 1,
      `lignes=${audits.rowCount}`,
    );

    // Renvoi d'un rapport déjà envoyé : 409.
    const deja = await appel(
      base,
      'POST',
      `/moi/rapports-annexe/${idEnvoye}/envoyer`,
      jetonAnnexe,
    );
    verifier(
      'renvoi d’un rapport déjà envoyé = 409',
      deja.statut === 409 && deja.json?.error === 'rapport_deja_envoye',
      deja.texte,
    );

    // Sans adresse e-mail pour la mère : le rapport reste en attente.
    await pool.query('UPDATE churches SET email = NULL WHERE id = $1', [mereId]);
    const envoi2 = await appel(base, 'POST', '/moi/rapports-annexe', jetonAnnexe, {
      type: 'rapport_financier',
      membres: 10,
      recettes_fcfa: 5000,
      depenses_fcfa: 5000,
      solde_fcfa: 0,
    });
    verifier(
      'mère sans e-mail : rapport en attente (email_mere_manquant)',
      envoi2.statut === 200 &&
        envoi2.json?.statut === 'en_attente_envoi' &&
        envoi2.json?.envoi_email === 'email_mere_manquant',
      envoi2.texte,
    );
    const idAttente = envoi2.json?.id;

    // Renvoi sans adresse : toujours en attente, sans erreur.
    const renvoiSansEmail = await appel(
      base,
      'POST',
      `/moi/rapports-annexe/${idAttente}/envoyer`,
      jetonAnnexe,
    );
    verifier(
      'renvoi sans e-mail : toujours en attente',
      renvoiSansEmail.statut === 200 &&
        renvoiSansEmail.json?.statut === 'en_attente_envoi' &&
        renvoiSansEmail.json?.envoi_email === 'email_mere_manquant',
      renvoiSansEmail.texte,
    );

    // L'adresse est renseignée après coup : le renvoi part.
    await pool.query('UPDATE churches SET email = $1 WHERE id = $2', [
      'mere-envoi@example.ci',
      mereId,
    ]);
    const renvoi = await appel(
      base,
      'POST',
      `/moi/rapports-annexe/${idAttente}/envoyer`,
      jetonAnnexe,
    );
    verifier(
      'renvoi après ajout de l’e-mail : rapport envoyé',
      renvoi.statut === 200 &&
        renvoi.json?.statut === 'envoye' &&
        renvoi.json?.envoi_email === 'envoye',
      renvoi.texte,
    );

    // Renvoi : rapport inconnu (404), rapport d'une autre église (404),
    // sans jeton (401).
    const inconnu = await appel(
      base,
      'POST',
      '/moi/rapports-annexe/00000000-0000-0000-0000-000000000000/envoyer',
      jetonAnnexe,
    );
    verifier(
      'renvoi d’un rapport inconnu = 404',
      inconnu.statut === 404,
      inconnu.texte,
    );
    const autreEglise = await appel(
      base,
      'POST',
      `/moi/rapports-annexe/${idAttente}/envoyer`,
      jetonMere,
    );
    verifier(
      'renvoi par la mère (pas son rapport) = 404',
      autreEglise.statut === 404,
      autreEglise.texte,
    );
    const sansJeton = await appel(
      base,
      'POST',
      `/moi/rapports-annexe/${idAttente}/envoyer`,
      null,
    );
    verifier('renvoi sans jeton = 401', sansJeton.statut === 401, sansJeton.texte);
  } finally {
    await arreterReseau(reseau1);
    await detruireBase('e_system_church_test_p5_envoi');
  }

  // --- Réseau 2 : aucun transport (ni SMTP, ni simulé).
  console.log('C. routes sans SMTP (échec d’envoi, statut conservé) :');
  const port2 = Number(process.env.PORT_SANS_SMTP ?? 4107);
  const reseau2 = await preparerReseau({
    nomDb: 'e_system_church_test_p5_envoi_smtp',
    port: port2,
    envServeur: {},
    suffixe: 's2',
  });
  try {
    const { base, pool, jetonAnnexe, mereId } = reseau2;
    await pool.query('UPDATE churches SET email = $1 WHERE id = $2', [
      'mere-envoi-s2@example.ci',
      mereId,
    ]);
    const envoi = await appel(base, 'POST', '/moi/rapports-annexe', jetonAnnexe, {
      type: 'bilan_activite',
      membres: 5,
      recettes_fcfa: 1000,
      depenses_fcfa: 1000,
      solde_fcfa: 0,
    });
    verifier(
      'sans SMTP : rapport enregistré, en attente (smtp_non_configure)',
      envoi.statut === 200 &&
        envoi.json?.statut === 'en_attente_envoi' &&
        envoi.json?.envoi_email === 'smtp_non_configure',
      envoi.texte,
    );
    const renvoi = await appel(
      base,
      'POST',
      `/moi/rapports-annexe/${envoi.json?.id}/envoyer`,
      jetonAnnexe,
    );
    verifier(
      'renvoi sans SMTP : toujours en attente (smtp_non_configure)',
      renvoi.statut === 200 &&
        renvoi.json?.statut === 'en_attente_envoi' &&
        renvoi.json?.envoi_email === 'smtp_non_configure',
      renvoi.texte,
    );
  } finally {
    await arreterReseau(reseau2);
    await detruireBase('e_system_church_test_p5_envoi_smtp');
  }

  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ÉCHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
