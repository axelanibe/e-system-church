// Test d'intégration de la tranche T8 (Lot B) — Paiements automatiques,
// webhooks (migration 026).
//
// Périmètre : webhook Wave (signature HMAC + re-interrogation de la
// session), webhook Orange Money (statut + montant), webhook MTN MoMo
// (re-interrogation obligatoire, le callback n'est pas signé) ;
// confirmation automatique des contributions en_attente avec les mêmes
// effets que la confirmation manuelle (reçu REC-AAAA-NNNN, écriture
// automatique en caisse, valide_par NULL, audit
// contribution.confirmee_webhook) ; idempotence (une même notification
// ne confirme pas deux fois ; une contribution déjà confirmée ne
// produit aucun double effet) ; journal des événements de paiement
// (sans secret ni signature) ; rôles (le webhook est public mais signé
// — un membre ne peut pas l'appeler comme une route authentifiée).
//
// Les fournisseurs réels ne sont JAMAIS appelés : deux faux serveurs
// locaux (Wave, MTN) répondent à la place, pilotés par des modes
// modifiables entre les cas. Aucun vrai paiement, aucun identifiant réel.
//
// Base fraîche, application du schéma puis des migrations avec le vrai
// moteur (dist/migrate.js), démarrage de l'API, appels HTTP. Aucun vrai
// envoi, aucun appel Wave / Orange / MTN.
//
// Usage (depuis la racine du dépôt, après `npm run build` dans server/) :
//   `node server/test-lot-b-t8-webhooks-paiements.mjs`
// Variables : PORT (défaut 4110). PostgreSQL local requis
// (utilisateur postgres / postgres).

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { createHmac } from 'node:crypto';
import { createServer } from 'node:http';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);
const JWT_SECRET = 'test-secret-t8-webhooks-32-caracteres';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const ADMIN = 'postgres://postgres:postgres@127.0.0.1:5432/postgres';
const NOM_DB = 'e_system_church_test_t8';
const PORT_FAUX_WAVE = 4111;
const PORT_FAUX_MTN = 4112;

// Secrets de TEST (fictifs, jamais réels) — utilisés aussi pour vérifier
// qu'aucun secret ne fuite dans les journaux.
const CLE_WAVE = 'cle-wave-test-t8';
const SECRET_WEBHOOK_WAVE = 'whsec_test_t8_123456';
const CLE_ABONNEMENT_MTN = 'cle-abonnement-mtn-test';
const UTILISATEUR_MTN = 'utilisateur-mtn-test';
const CLE_API_MTN = 'cle-api-mtn-test';

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

// -- Faux serveurs ------------------------------------------------------------
// Modes pilotés par le test, cas par cas.
let modeWave = 'complete'; // complete | open | expired | notfound | error | wrongamount | wrongcurrency
let modeJetonMtn = 'ok'; // ok | error
let modeStatutMtn = 'successful'; // successful | pending | failed | wrongamount | wrongcurrency | notfound | error

function fauxWave(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  const m = url.pathname.match(/^\/v1\/checkout\/sessions\/(.+)$/);
  if (req.method !== 'GET' || !m) {
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'introuvable' }));
    return;
  }
  // Le serveur doit appeler Wave avec la clé API de l'église (la sienne).
  if (req.headers.authorization !== `Bearer ${CLE_WAVE}`) {
    res.writeHead(401, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'non autorisé' }));
    return;
  }
  const sessionId = decodeURIComponent(m[1]);
  if (modeWave === 'notfound') {
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'session introuvable' }));
    return;
  }
  if (modeWave === 'error') {
    res.writeHead(500, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'panne Wave' }));
    return;
  }
  const session = {
    id: sessionId,
    amount: modeWave === 'wrongamount' ? 4500 : 5000,
    currency: modeWave === 'wrongcurrency' ? 'EUR' : 'XOF',
    checkout_status:
      modeWave === 'open' ? 'open' : modeWave === 'expired' ? 'expired' : 'complete',
    when_completed: modeWave === 'complete' ? new Date().toISOString() : null,
  };
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify(session));
}

function fauxMtn(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (req.method === 'POST' && url.pathname === '/collection/token/') {
    const attendu = `Basic ${Buffer.from(`${UTILISATEUR_MTN}:${CLE_API_MTN}`, 'utf8').toString('base64')}`;
    if (
      modeJetonMtn === 'error' ||
      req.headers.authorization !== attendu ||
      req.headers['ocp-apim-subscription-key'] !== CLE_ABONNEMENT_MTN
    ) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'non autorisé' }));
      return;
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ access_token: 'jeton-faux-mtn', token_type: 'Bearer', expires_in: 3600 }));
    return;
  }
  const m = url.pathname.match(/^\/collection\/v1_0\/requesttopay\/(.+)$/);
  if (req.method === 'GET' && m) {
    if (
      req.headers.authorization !== 'Bearer jeton-faux-mtn' ||
      req.headers['ocp-apim-subscription-key'] !== CLE_ABONNEMENT_MTN
    ) {
      res.writeHead(401, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'non autorisé' }));
      return;
    }
    if (modeStatutMtn === 'notfound') {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'transaction inconnue' }));
      return;
    }
    if (modeStatutMtn === 'error') {
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'panne MTN' }));
      return;
    }
    const statut = {
      status:
        modeStatutMtn === 'pending'
          ? 'PENDING'
          : modeStatutMtn === 'failed'
            ? 'FAILED'
            : 'SUCCESSFUL',
      amount: modeStatutMtn === 'wrongamount' ? '3500' : '4000',
      currency: modeStatutMtn === 'wrongcurrency' ? 'EUR' : 'XOF',
      financialTransactionId: `fin-${decodeURIComponent(m[1])}`,
    };
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(statut));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'introuvable' }));
}

/** Signature Wave-Signature d'un corps brut (même calcul que Wave). */
function signerWave(secret, corps, decalageSecondes = 0) {
  const t = Math.floor(Date.now() / 1000) + decalageSecondes;
  const sig = createHmac('sha256', secret).update(`${t}${corps}`, 'utf8').digest('hex');
  return `t=${t},v1=${sig}`;
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

  const serveurWave = createServer(fauxWave);
  const serveurMtn = createServer(fauxMtn);
  await new Promise((resolve) => serveurWave.listen(PORT_FAUX_WAVE, '127.0.0.1', resolve));
  await new Promise((resolve) => serveurMtn.listen(PORT_FAUX_MTN, '127.0.0.1', resolve));

  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: {
      ...process.env,
      DATABASE_URL: databaseUrl,
      PORT: String(port),
      JWT_SECRET,
      PAYMENT_SECRETS_KEY,
      WAVE_API_BASE_URL: `http://127.0.0.1:${PORT_FAUX_WAVE}`,
      MTN_API_BASE_URL: `http://127.0.0.1:${PORT_FAUX_MTN}`,
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

    /** Appel avec un corps brut exact (signature Wave calculée dessus). */
    async function appelBrut(methode, chemin, corpsBrut, entetes = {}) {
      const reponse = await fetch(`${base}${chemin}`, {
        method: methode,
        headers: { 'content-type': 'application/json', ...entetes },
        body: corpsBrut,
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

    const annee = new Date().getFullYear();

    // --- Préparation : églises, rôles, configurations marchandes ----------
    const mere = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère T8', city: 'Abidjan' },
      admin: {
        full_name: 'Admin mère T8',
        email: 'admin-mere-t8@example.com',
        password: 'MotDePasse123!',
      },
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonAdmin = mere.json?.token;
    const egliseId = mere.json?.church?.id;

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
      return rows[0].id;
    }
    await creerCompte('tresorier-t8@example.com', 'tresorier');
    await creerCompte('membre-t8@example.com', 'membre');
    const jetonTresorier = await login('tresorier-t8@example.com');
    const jetonMembre = await login('membre-t8@example.com');

    async function configurer(code, secrets, churchId = egliseId, jeton = jetonAdmin) {
      return appel('POST', `/eglises/${churchId}/paiements`, jeton, {
        fournisseur_code: code,
        pays: 'CI',
        secrets: secrets.map(([nom_champ, valeur]) => ({ nom_champ, valeur })),
      });
    }
    const cfgWave = await configurer('wave', [
      ['api_key', CLE_WAVE],
      ['webhook_secret', SECRET_WEBHOOK_WAVE],
    ]);
    verifier('configuration Wave (clé + secret webhook)', cfgWave.statut === 201, cfgWave.texte);
    const cfgOrange = await configurer('orange_money', [
      ['client_id', 'client-orange-test'],
      ['client_secret', 'secret-orange-test'],
      ['merchant_key', 'marchand-orange-test'],
    ]);
    verifier('configuration Orange Money', cfgOrange.statut === 201, cfgOrange.texte);
    const cfgMtn = await configurer('mtn_momo', [
      ['subscription_key', CLE_ABONNEMENT_MTN],
      ['api_user', UTILISATEUR_MTN],
      ['api_key', CLE_API_MTN],
    ]);
    verifier('configuration MTN MoMo', cfgMtn.statut === 201, cfgMtn.texte);

    // Deuxième église : Wave configuré SANS secret de webhook (401 attendu).
    const autre = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église T8 sans secret', city: 'Abidjan' },
      admin: {
        full_name: 'Admin T8 sans secret',
        email: 'admin-sans-secret-t8@example.com',
        password: 'MotDePasse123!',
      },
    });
    verifier('inscription deuxième église', autre.statut === 201, autre.texte);
    const jetonAdmin2 = autre.json?.token;
    const egliseId2 = autre.json?.church?.id;
    const cfgWave2 = await configurer('wave', [['api_key', CLE_WAVE]], egliseId2, jetonAdmin2);
    verifier('configuration Wave sans secret (2e église)', cfgWave2.statut === 201, cfgWave2.texte);

    async function creerContribution(paymentMethod, paymentRef, montant, jeton = jetonTresorier) {
      const r = await appel('POST', '/contributions', jeton, {
        type: 'don',
        amount_fcfa: montant,
        payment_method: paymentMethod,
        payment_ref: paymentRef,
      });
      if (r.statut !== 201) throw new Error(`contribution ${paymentRef}: ${r.texte}`);
      return r.json.id;
    }

    async function lireContribution(id, jeton = jetonAdmin) {
      const r = await appel('GET', `/contributions/${id}`, jeton);
      // L'API enveloppe la contribution sous la clé `recu`.
      return r.json?.recu ?? null;
    }

    async function compterCaisse() {
      const r = await appel('GET', '/finances/caisse', jetonAdmin);
      return { solde: r.json?.solde, mouvements: r.json?.mouvements };
    }

    async function evenements(fournisseur) {
      const { rows } = await pool.query(
        `SELECT fournisseur, evenement_id, statut, contribution_id, montant_fcfa, devise, reference_externe, payload_hash
           FROM evenements_paiement WHERE fournisseur = $1 ORDER BY recu_at`,
        [fournisseur],
      );
      return rows;
    }

    // --- Webhook Wave -------------------------------------------------------
    const corpsWave = (sessionId) =>
      JSON.stringify({
        id: `evt-${sessionId}`,
        type: 'checkout.session.completed',
        data: { id: sessionId, amount: 5000, currency: 'XOF', checkout_status: 'complete' },
      });

    // 1) Signature invalide → 401, rien n'est confirmé ni journalisé.
    const w1 = await creerContribution('wave', 'cos-test-w1', 5000);
    const faux1 = await appelBrut('POST', '/webhooks/wave', corpsWave('cos-test-w1'), {
      'wave-signature': 't=123,v1=00',
    });
    verifier('Wave : signature invalide → 401', faux1.statut === 401, faux1.texte);
    verifier(
      'Wave : signature invalide → contribution toujours en_attente',
      (await lireContribution(w1)).status === 'en_attente',
    );
    verifier('Wave : signature invalide → aucun événement journalisé', (await evenements('wave')).length === 0);

    // 2) Signature absente → 401.
    const faux2 = await appelBrut('POST', '/webhooks/wave', corpsWave('cos-test-w1'));
    verifier('Wave : signature absente → 401', faux2.statut === 401, faux2.texte);

    // 3) Signature expirée (10 min) → 401.
    const faux3 = await appelBrut('POST', '/webhooks/wave', corpsWave('cos-test-w1'), {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsWave('cos-test-w1'), -600),
    });
    verifier('Wave : signature expirée → 401', faux3.statut === 401, faux3.texte);

    // 4) Un membre ne peut pas appeler le webhook comme une route
    //    authentifiée : sans signature, même avec son jeton, c'est 401.
    const faux4 = await appelBrut('POST', '/webhooks/wave', corpsWave('cos-test-w1'), {
      authorization: `Bearer ${jetonMembre}`,
    });
    verifier('Wave : jeton membre sans signature → 401', faux4.statut === 401, faux4.texte);

    // 5) GET sur un webhook → 404 (aucune route GET).
    const faux5 = await appel('GET', '/webhooks/wave', null);
    verifier('Wave : GET /webhooks/wave → 404', faux5.statut === 404, faux5.texte);

    // 6) Type d'événement non concerné → 200 ignoré, sans effet.
    const corpsExpire = JSON.stringify({
      id: 'evt-expire',
      type: 'checkout.session.expired',
      data: { id: 'cos-test-w1' },
    });
    const faux6 = await appelBrut('POST', '/webhooks/wave', corpsExpire, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsExpire),
    });
    verifier('Wave : événement expiré → 200 ignoré', faux6.statut === 200 && faux6.json?.traite === 'ignore', faux6.texte);
    verifier(
      'Wave : événement expiré → contribution toujours en_attente',
      (await lireContribution(w1)).status === 'en_attente',
    );

    // 7) Payload valide → confirmation automatique + reçu + caisse.
    modeWave = 'complete';
    const corpsValide = corpsWave('cos-test-w1');
    const ok1 = await appelBrut('POST', '/webhooks/wave', corpsValide, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsValide),
    });
    verifier(
      'Wave : payload valide → 200 confirmé',
      ok1.statut === 200 && ok1.json?.traite === 'confirme' && typeof ok1.json?.recu_numero === 'string',
      ok1.texte,
    );
    const apresW1 = await lireContribution(w1);
    verifier('Wave : contribution confirmée', apresW1.status === 'confirme', JSON.stringify(apresW1));
    verifier(
      'Wave : reçu numéroté REC-AAAA-NNNN',
      typeof apresW1.recu_numero === 'string' && apresW1.recu_numero.startsWith(`REC-${annee}-`),
      apresW1.recu_numero,
    );
    verifier('Wave : valide_par NULL (aucun humain)', apresW1.valide_par === null, JSON.stringify(apresW1));
    const { rows: valideParW1 } = await pool.query(
      `SELECT valide_par FROM contributions WHERE id = $1`,
      [w1],
    );
    verifier('Wave : valide_par NULL en base aussi', valideParW1[0].valide_par === null, JSON.stringify(valideParW1));
    const caisseApresW1 = await compterCaisse();
    verifier('Wave : caisse écrite (+5000)', caisseApresW1.solde === 5000 && caisseApresW1.mouvements === 1, JSON.stringify(caisseApresW1));
    const evW1 = await evenements('wave');
    verifier(
      'Wave : événement journalisé confirmé',
      evW1.length === 1 && evW1[0].statut === 'confirme' && evW1[0].contribution_id === w1,
      JSON.stringify(evW1),
    );

    // 8) Double notification (même événement) → deja_traite, sans effet.
    const ok2 = await appelBrut('POST', '/webhooks/wave', corpsValide, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsValide),
    });
    verifier(
      'Wave : double notification → 200 deja_traite',
      ok2.statut === 200 && ok2.json?.traite === 'deja_traite' && ok2.json?.deja_traite === true,
      ok2.texte,
    );
    const caisseApresDouble = await compterCaisse();
    verifier(
      'Wave : double notification → une seule écriture en caisse',
      caisseApresDouble.solde === 5000 && caisseApresDouble.mouvements === 1,
      JSON.stringify(caisseApresDouble),
    );

    // 9) Contribution déjà confirmée manuellement → pas de double effet.
    const w2 = await creerContribution('wave', 'cos-test-w2', 5000);
    const manuel = await appel('PATCH', `/contributions/${w2}/statut`, jetonAdmin, { status: 'confirme' });
    verifier('Wave : confirmation manuelle préalable', manuel.statut === 200, manuel.texte);
    const corpsW2 = corpsWave('cos-test-w2');
    const ok3 = await appelBrut('POST', '/webhooks/wave', corpsW2, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsW2),
    });
    verifier(
      'Wave : contribution déjà confirmée → 200 deja_confirme',
      ok3.statut === 200 && ok3.json?.traite === 'deja_confirme',
      ok3.texte,
    );
    const caisseApresW2 = await compterCaisse();
    verifier(
      'Wave : déjà confirmée → caisse inchangée par le webhook (10000 au total)',
      caisseApresW2.solde === 10000 && caisseApresW2.mouvements === 2,
      JSON.stringify(caisseApresW2),
    );

    // 10) Référence inconnue → 200 ignoré, événement journalisé.
    const corpsInconnu = corpsWave('cos-inconnu');
    const ok4 = await appelBrut('POST', '/webhooks/wave', corpsInconnu, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsInconnu),
    });
    verifier(
      'Wave : référence inconnue → 200 ignoré',
      ok4.statut === 200 && ok4.json?.traite === 'ignore' && ok4.json?.raison === 'reference_inconnue',
      ok4.texte,
    );

    // 11) Session encore ouverte côté Wave → 200 ignoré.
    modeWave = 'open';
    const w3 = await creerContribution('wave', 'cos-test-w3', 5000);
    const corpsW3 = corpsWave('cos-test-w3');
    const ok5 = await appelBrut('POST', '/webhooks/wave', corpsW3, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsW3),
    });
    verifier(
      'Wave : session ouverte → 200 ignoré',
      ok5.statut === 200 && ok5.json?.traite === 'ignore' && ok5.json?.raison === 'session_non_complete',
      ok5.texte,
    );
    verifier('Wave : session ouverte → en_attente', (await lireContribution(w3)).status === 'en_attente');

    // 12) Montant incohérent → 200 ignoré.
    modeWave = 'wrongamount';
    const w4 = await creerContribution('wave', 'cos-test-w4', 5000);
    const corpsW4 = corpsWave('cos-test-w4');
    const ok6 = await appelBrut('POST', '/webhooks/wave', corpsW4, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsW4),
    });
    verifier(
      'Wave : montant incohérent → 200 ignoré',
      ok6.statut === 200 && ok6.json?.traite === 'ignore' && ok6.json?.raison === 'montant_incoherent',
      ok6.texte,
    );
    verifier('Wave : montant incohérent → en_attente', (await lireContribution(w4)).status === 'en_attente');

    // 13) Session introuvable côté Wave → 200 ignoré.
    modeWave = 'notfound';
    const w5 = await creerContribution('wave', 'cos-test-w5', 5000);
    const corpsW5 = corpsWave('cos-test-w5');
    const ok7 = await appelBrut('POST', '/webhooks/wave', corpsW5, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsW5),
    });
    verifier(
      'Wave : session introuvable → 200 ignoré',
      ok7.statut === 200 && ok7.json?.traite === 'ignore' && ok7.json?.raison === 'session_non_complete',
      ok7.texte,
    );

    // 14) Re-interrogation Wave en panne → 500, événement à vérifier.
    modeWave = 'error';
    const w6 = await creerContribution('wave', 'cos-test-w6', 5000);
    const corpsW6 = corpsWave('cos-test-w6');
    const ok8 = await appelBrut('POST', '/webhooks/wave', corpsW6, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsW6),
    });
    verifier('Wave : re-interrogation en panne → 500', ok8.statut === 500, ok8.texte);
    verifier('Wave : re-interrogation en panne → en_attente', (await lireContribution(w6)).status === 'en_attente');
    modeWave = 'complete';

    // 15) Wave sans secret configuré (2e église) → 401.
    const w7 = await creerContribution('wave', 'cos-test-w7', 5000, jetonAdmin2);
    // La contribution de la 2e église : le trésorier de la 1re ne peut pas
    // la créer — on l'a créée avec le jeton admin de la 2e église.
    const corpsW7 = corpsWave('cos-test-w7');
    const ok9 = await appelBrut('POST', '/webhooks/wave', corpsW7, {
      'wave-signature': signerWave(SECRET_WEBHOOK_WAVE, corpsW7),
    });
    verifier('Wave : secret non configuré → 401', ok9.statut === 401, ok9.texte);
    verifier('Wave : secret non configuré → en_attente', (await lireContribution(w7, jetonAdmin2)).status === 'en_attente');

    // --- Webhook Orange Money ------------------------------------------------
    // 16) SUCCESS + montant OK → confirmation automatique.
    const o1 = await creerContribution('orange_money', 'ORD-T8-1', 3000);
    const okO1 = await appel('POST', '/webhooks/orange', null, {
      notif_token: 'jeton-notif-orange-1',
      transaction_id: 'txn-orange-1',
      order_id: 'ORD-T8-1',
      status: 'SUCCESS',
      amount: 3000,
      currency: 'XOF',
    });
    verifier(
      'Orange : SUCCESS → 200 confirmé',
      okO1.statut === 200 && okO1.json?.traite === 'confirme' && typeof okO1.json?.recu_numero === 'string',
      okO1.texte,
    );
    const apresO1 = await lireContribution(o1);
    verifier('Orange : contribution confirmée', apresO1.status === 'confirme', JSON.stringify(apresO1));

    // 17) Double notification Orange → deja_traite.
    const okO2 = await appel('POST', '/webhooks/orange', null, {
      notif_token: 'jeton-notif-orange-1',
      transaction_id: 'txn-orange-1',
      order_id: 'ORD-T8-1',
      status: 'SUCCESS',
      amount: 3000,
      currency: 'XOF',
    });
    verifier(
      'Orange : double notification → 200 deja_traite',
      okO2.statut === 200 && okO2.json?.traite === 'deja_traite',
      okO2.texte,
    );

    // 18) FAILED → 200 ignoré.
    const o2 = await creerContribution('orange_money', 'ORD-T8-2', 3000);
    const okO3 = await appel('POST', '/webhooks/orange', null, {
      transaction_id: 'txn-orange-2',
      order_id: 'ORD-T8-2',
      status: 'FAILED',
      amount: 3000,
      currency: 'XOF',
    });
    verifier(
      'Orange : FAILED → 200 ignoré',
      okO3.statut === 200 && okO3.json?.traite === 'ignore' && okO3.json?.raison === 'paiement_echoue',
      okO3.texte,
    );
    verifier('Orange : FAILED → en_attente', (await lireContribution(o2)).status === 'en_attente');

    // 19) Montant incohérent → 200 ignoré.
    const o3 = await creerContribution('orange_money', 'ORD-T8-3', 3000);
    const okO4 = await appel('POST', '/webhooks/orange', null, {
      transaction_id: 'txn-orange-3',
      order_id: 'ORD-T8-3',
      status: 'SUCCESS',
      amount: 3500,
      currency: 'XOF',
    });
    verifier(
      'Orange : montant incohérent → 200 ignoré',
      okO4.statut === 200 && okO4.json?.traite === 'ignore' && okO4.json?.raison === 'montant_incoherent',
      okO4.texte,
    );

    // 20) Référence inconnue → 200 ignoré.
    const okO5 = await appel('POST', '/webhooks/orange', null, {
      transaction_id: 'txn-orange-inconnu',
      order_id: 'ORD-INCONNU',
      status: 'SUCCESS',
      amount: 1000,
      currency: 'XOF',
    });
    verifier(
      'Orange : référence inconnue → 200 ignoré',
      okO5.statut === 200 && okO5.json?.traite === 'ignore',
      okO5.texte,
    );

    // 21) Notification sans référence → 400.
    const okO6 = await appel('POST', '/webhooks/orange', null, {
      status: 'SUCCESS',
      amount: 3000,
    });
    verifier('Orange : sans référence → 400', okO6.statut === 400, okO6.texte);

    // 22) Notification en formulaire (format réel d'Orange) → confirmé.
    const o4 = await creerContribution('orange_money', 'ORD-T8-4', 3000);
    const corpsForm = new URLSearchParams({
      notif_token: 'jeton-notif-orange-4',
      transaction_id: 'txn-orange-4',
      order_id: 'ORD-T8-4',
      status: 'SUCCESS',
      amount: '3000',
      currency: 'XOF',
    }).toString();
    const reponseForm = await fetch(`${base}/webhooks/orange`, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: corpsForm,
    });
    const texteForm = await reponseForm.text();
    let jsonForm = null;
    try {
      jsonForm = JSON.parse(texteForm);
    } catch {
      jsonForm = null;
    }
    verifier(
      'Orange : formulaire → 200 confirmé',
      reponseForm.status === 200 && jsonForm?.traite === 'confirme',
      texteForm,
    );
    verifier('Orange : formulaire → contribution confirmée', (await lireContribution(o4)).status === 'confirme');

    // --- Webhook MTN MoMo ------------------------------------------------------
    // 23) Callback (statut reçu ignoré) + re-interrogation SUCCESSFUL →
    //     confirmation automatique.
    modeStatutMtn = 'successful';
    const m1 = await creerContribution('mtn_momo', 'ref-mtn-1', 4000);
    const okM1 = await appel('POST', '/webhooks/mtn', null, {
      externalId: 'ref-mtn-1',
      referenceId: 'ref-mtn-1',
      status: 'FAILED',
      financialTransactionId: 'fin-ref-mtn-1',
      amount: '4000',
      currency: 'XOF',
    });
    verifier(
      'MTN : re-interrogation SUCCESSFUL → 200 confirmé (statut du callback ignoré)',
      okM1.statut === 200 && okM1.json?.traite === 'confirme' && typeof okM1.json?.recu_numero === 'string',
      okM1.texte,
    );
    const apresM1 = await lireContribution(m1);
    verifier('MTN : contribution confirmée', apresM1.status === 'confirme', JSON.stringify(apresM1));

    // 24) Double callback MTN → deja_traite.
    const okM2 = await appel('POST', '/webhooks/mtn', null, {
      externalId: 'ref-mtn-1',
      referenceId: 'ref-mtn-1',
      status: 'SUCCESSFUL',
      financialTransactionId: 'fin-ref-mtn-1',
      amount: '4000',
      currency: 'XOF',
    });
    verifier(
      'MTN : double callback → 200 deja_traite',
      okM2.statut === 200 && okM2.json?.traite === 'deja_traite',
      okM2.texte,
    );

    // 25) Re-interrogation PENDING → 200 à vérifier.
    modeStatutMtn = 'pending';
    const m2 = await creerContribution('mtn_momo', 'ref-mtn-2', 4000);
    const okM3 = await appel('POST', '/webhooks/mtn', null, {
      referenceId: 'ref-mtn-2',
      status: 'PENDING',
      amount: '4000',
      currency: 'XOF',
    });
    verifier(
      'MTN : re-interrogation PENDING → 200 a_verifier',
      okM3.statut === 200 && okM3.json?.traite === 'a_verifier' && okM3.json?.raison === 'paiement_en_cours',
      okM3.texte,
    );
    verifier('MTN : PENDING → en_attente', (await lireContribution(m2)).status === 'en_attente');

    // 26) Re-interrogation FAILED → 200 ignoré.
    modeStatutMtn = 'failed';
    const m3 = await creerContribution('mtn_momo', 'ref-mtn-3', 4000);
    const okM4 = await appel('POST', '/webhooks/mtn', null, {
      referenceId: 'ref-mtn-3',
      status: 'FAILED',
      amount: '4000',
      currency: 'XOF',
    });
    verifier(
      'MTN : re-interrogation FAILED → 200 ignoré',
      okM4.statut === 200 && okM4.json?.traite === 'ignore' && okM4.json?.raison === 'paiement_echoue',
      okM4.texte,
    );

    // 27) Re-interrogation MTN en panne → 500, événement à vérifier.
    modeStatutMtn = 'error';
    const m4 = await creerContribution('mtn_momo', 'ref-mtn-4', 4000);
    const okM5 = await appel('POST', '/webhooks/mtn', null, {
      referenceId: 'ref-mtn-4',
      status: 'SUCCESSFUL',
      amount: '4000',
      currency: 'XOF',
    });
    verifier('MTN : re-interrogation en panne → 500', okM5.statut === 500, okM5.texte);
    verifier('MTN : re-interrogation en panne → en_attente', (await lireContribution(m4)).status === 'en_attente');
    modeStatutMtn = 'successful';

    // 28) Callback en PUT (variante MTN) → confirmé.
    const m5 = await creerContribution('mtn_momo', 'ref-mtn-5', 4000);
    const okM6 = await appel('PUT', '/webhooks/mtn', null, {
      referenceId: 'ref-mtn-5',
      status: 'SUCCESSFUL',
      amount: '4000',
      currency: 'XOF',
    });
    verifier(
      'MTN : callback PUT → 200 confirmé',
      okM6.statut === 200 && okM6.json?.traite === 'confirme',
      okM6.texte,
    );
    verifier('MTN : callback PUT → contribution confirmée', (await lireContribution(m5)).status === 'confirme');

    // 29) Référence inconnue → 200 ignoré.
    const okM7 = await appel('POST', '/webhooks/mtn', null, {
      referenceId: 'ref-mtn-inconnu',
      status: 'SUCCESSFUL',
      amount: '1000',
      currency: 'XOF',
    });
    verifier(
      'MTN : référence inconnue → 200 ignoré',
      okM7.statut === 200 && okM7.json?.traite === 'ignore',
      okM7.texte,
    );

    // --- Bilan : caisse, événements, audit, absence de fuite ------------------
    const caisseFinale = await compterCaisse();
    verifier(
      'Bilan : caisse = 5000 (W1) + 5000 (W2 manuel) + 3000 (O1) + 3000 (O4) + 4000 (M1) + 4000 (M5) = 24000, 6 mouvements',
      caisseFinale.solde === 24000 && caisseFinale.mouvements === 6,
      JSON.stringify(caisseFinale),
    );
    const { rows: evTous } = await pool.query(
      `SELECT fournisseur, statut FROM evenements_paiement ORDER BY recu_at`,
    );
    const comptes = {};
    for (const ev of evTous) comptes[`${ev.fournisseur}:${ev.statut}`] = (comptes[`${ev.fournisseur}:${ev.statut}`] ?? 0) + 1;
    verifier(
      'Bilan : événements Wave = 1 confirmé (W1) + 5 ignorés (W2 déjà confirmée, inconnu, W3, W4, W5) + 1 à vérifier (W6)',
      comptes['wave:confirme'] === 1 && comptes['wave:ignore'] === 5 && comptes['wave:a_verifier'] === 1,
      JSON.stringify(comptes),
    );
    verifier(
      'Bilan : événements Orange = 2 confirmés (O1, O4) + 3 ignorés (O2, O3, inconnu)',
      comptes['orange_money:confirme'] === 2 && comptes['orange_money:ignore'] === 3,
      JSON.stringify(comptes),
    );
    verifier(
      'Bilan : événements MTN = 2 confirmés (M1, M5) + 2 ignorés (M3, inconnu) + 2 à vérifier (M2, M4)',
      comptes['mtn_momo:confirme'] === 2 && comptes['mtn_momo:ignore'] === 2 && comptes['mtn_momo:a_verifier'] === 2,
      JSON.stringify(comptes),
    );
    const { rows: evSecrets } = await pool.query(
      `SELECT count(*)::int AS n FROM evenements_paiement
        WHERE evenement_id LIKE $1 OR evenement_id LIKE $2 OR reference_externe LIKE $1 OR reference_externe LIKE $2
           OR (payload_hash LIKE $1 OR payload_hash LIKE $2)`,
      [`%${SECRET_WEBHOOK_WAVE}%`, `%${CLE_WAVE}%`],
    );
    verifier('Bilan : aucun secret dans evenements_paiement', evSecrets[0].n === 0, JSON.stringify(evSecrets));
    const { rows: evHash } = await pool.query(
      `SELECT count(*)::int AS n FROM evenements_paiement WHERE payload_hash IS NULL OR length(payload_hash) <> 64`,
    );
    verifier('Bilan : chaque événement porte une empreinte SHA-256 (64 hex)', evHash[0].n === 0, JSON.stringify(evHash));
    const { rows: auditWebhook } = await pool.query(
      `SELECT count(*)::int AS n FROM audit_logs WHERE action = 'contribution.confirmee_webhook'`,
    );
    verifier('Bilan : 5 confirmations webhook journalisées', auditWebhook[0].n === 5, JSON.stringify(auditWebhook));
    const { rows: auditRejet } = await pool.query(
      `SELECT count(*)::int AS n FROM audit_logs WHERE action = 'webhook.wave.signature_rejetee'`,
    );
    verifier('Bilan : 5 rejets de signature journalisés', auditRejet[0].n === 5, JSON.stringify(auditRejet));
    const { rows: auditSecrets } = await pool.query(
      `SELECT count(*)::int AS n FROM audit_logs WHERE details::text LIKE $1 OR details::text LIKE $2 OR details::text LIKE $3`,
      [`%${SECRET_WEBHOOK_WAVE}%`, `%${CLE_WAVE}%`, `%${CLE_API_MTN}%`],
    );
    verifier('Bilan : aucun secret dans audit_logs', auditSecrets[0].n === 0, JSON.stringify(auditSecrets));

    await pool.end();
  } finally {
    if (pool) await pool.end().catch(() => undefined);
    api.kill();
    await once(api, 'exit').catch(() => undefined);
    try {
      await new Promise((resolve) => serveurWave.close(resolve));
    } catch {
      /* déjà fermé */
    }
    try {
      await new Promise((resolve) => serveurMtn.close(resolve));
    } catch {
      /* déjà fermé */
    }
    await detruireBase(NOM_DB);
  }

  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ECHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
