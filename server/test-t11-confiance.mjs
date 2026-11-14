// Test d'intégration du socle de confiance (tranche T11) : 2FA TOTP
// (activation, connexion avec et sans code, désactivation), journal
// d'audit à hash chaîné (lecture, vérification, immuabilité),
// lectures sensibles (US17), sauvegarde chiffrée avec restauration
// testée, notifications sans fournisseur (échec propre, rien ne part),
// file d'actions hors ligne (soumission idempotente, rejeu ordonné),
// politiques RLS, droits 401/403 et isolation entre églises.
// Même forme que server/test-t10-gouvernance.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-t11-confiance.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4108).
// Base locale : PostgreSQL est nécessaire.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';
import { createDecipheriv, createHash, createHmac } from 'node:crypto';

const PORT = Number(process.env.PORT ?? 4108);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_t11';
// Secret de test seulement, jamais utilisé en production.
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
  return { statut: reponse.status, json, texte, entetes: reponse.headers };
}

// -- TOTP de test (RFC 6238, même calcul que le serveur) --------------------
const ALPHABET_BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function decoderBase32(secret) {
  const propre = secret.toUpperCase().replace(/=+$/, '');
  let bits = 0;
  let valeur = 0;
  const octets = [];
  for (const c of propre) {
    const index = ALPHABET_BASE32.indexOf(c);
    valeur = (valeur << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      octets.push((valeur >> bits) & 255);
    }
  }
  return Buffer.from(octets);
}
function codeTotp(secret) {
  const cle = decoderBase32(secret);
  const compteur = Math.floor(Date.now() / 1000 / 30);
  const tampon = Buffer.alloc(8);
  tampon.writeBigUInt64BE(BigInt(compteur));
  const hmac = createHmac('sha1', cle).update(tampon).digest();
  const decalage = hmac[hmac.length - 1] & 0x0f;
  const valeur =
    ((hmac[decalage] & 0x7f) << 24) |
    ((hmac[decalage + 1] & 0xff) << 16) |
    ((hmac[decalage + 2] & 0xff) << 8) |
    (hmac[decalage + 3] & 0xff);
  return String(valeur % 1000000).padStart(6, '0');
}

function dechiffrerSecret(chiffre) {
  const cle = Buffer.from(PAYMENT_SECRETS_KEY, 'hex');
  const decipher = createDecipheriv('aes-256-gcm', cle, Buffer.from(chiffre.iv, 'hex'));
  decipher.setAuthTag(Buffer.from(chiffre.tag, 'hex'));
  return Buffer.concat([
    decipher.update(Buffer.from(chiffre.valeur_chiffree, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

async function main() {
  // Base fraîche.
  const admin = new Client({
    connectionString: 'postgres://postgres:postgres@127.0.0.1:5432/postgres',
  });
  await admin.connect();
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_t11');
  await admin.query('CREATE DATABASE e_system_church_test_t11');
  await admin.end();

  // Schéma + migrations avec le vrai moteur.
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const exec = promisify(execFile);
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

    // --- Vérification de la migration 029 (structure) ----------------------
    const direct = new Client({ connectionString: DATABASE_URL });
    await direct.connect();
    const tables = await direct.query(
      `SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN ('consultations_sensibles', 'auth_2fa', 'sauvegardes', 'notifications', 'actions_hors_ligne')`,
    );
    verifier('migration 029 : 5 tables créées', tables.rowCount === 5, `reçu ${tables.rowCount}`);
    const colonnes = await direct.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'audit_logs'
          AND column_name IN ('hash', 'hash_precedent', 'seq')`,
    );
    verifier('migration 029 : colonnes hash sur audit_logs', colonnes.rowCount === 3, `reçu ${colonnes.rowCount}`);
    const politiques = await direct.query(
      `SELECT tablename FROM pg_policies WHERE policyname = 'isolement_eglise'`,
    );
    verifier('migration 029 : 6 politiques RLS', politiques.rowCount === 6, `reçu ${politiques.rowCount}`);
    const declencheur = await direct.query(
      `SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_logs_immutable'`,
    );
    verifier('migration 029 : déclencheur immuabilité audit', declencheur.rowCount === 1);
    await direct.end();

    // --- Préparation : église mère + membre + culte -------------------------
    const mere = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan', phone: '+2250102030405' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-t11@example.com',
        phone: '+2250102030405',
        password: 'MotDePasse123!',
      },
      channel: 'web',
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonMere = mere.json?.token;

    const fidele = await appel('POST', '/auth/inscription-par-code', null, {
      code_eglise: mere.json?.church?.code_fidele ?? mere.json?.church?.code,
      nom_prenom: 'Fidèle EXEMPLE',
      email: 'fidele-exemple-t11@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle par code', fidele.statut === 201, fidele.texte);
    const jetonFidele = fidele.json?.token;

    const membre = await appel('POST', '/membres', jetonMere, {
      full_name: 'Membre EXEMPLE',
      phone: '+2250708080910',
    });
    verifier('création membre', membre.statut === 201, membre.texte);
    const membreId = membre.json?.id;

    const culte = await appel('POST', '/cultes', jetonMere, {
      titre: 'Culte EXEMPLE',
      date_heure: '2026-11-15T10:00:00Z',
    });
    verifier('création culte', culte.statut === 201, culte.texte);
    const culteId = culte.json?.id;

    // --- 2FA TOTP ------------------------------------------------------------
    const etatAvant = await appel('GET', '/auth/2fa/etat', jetonMere);
    verifier('2FA inactive au départ', etatAvant.statut === 200 && etatAvant.json?.actif === false, etatAvant.texte);

    const demarrage = await appel('POST', '/auth/2fa/demarrer', jetonMere, {});
    verifier(
      'démarrage 2FA renvoie URI otpauth et secret',
      demarrage.statut === 200 &&
        typeof demarrage.json?.otpauth_uri === 'string' &&
        demarrage.json.otpauth_uri.startsWith('otpauth://totp/') &&
        typeof demarrage.json?.secret === 'string' &&
        demarrage.json.secret.length >= 20,
      demarrage.texte,
    );
    const secretTotp = demarrage.json?.secret;

    const demarrageFidele = await appel('POST', '/auth/2fa/demarrer', jetonFidele, {});
    verifier('2FA refusée au rôle membre', demarrageFidele.statut === 403, demarrageFidele.texte);

    const mauvaisCode = await appel('POST', '/auth/2fa/verifier', jetonMere, { code: '000000' });
    verifier('vérification 2FA avec code faux = 401', mauvaisCode.statut === 401, mauvaisCode.texte);

    const bonCode = codeTotp(secretTotp);
    const verification = await appel('POST', '/auth/2fa/verifier', jetonMere, { code: bonCode });
    verifier('vérification 2FA avec code juste = actif', verification.statut === 200 && verification.json?.actif === true, verification.texte);

    const etatApres = await appel('GET', '/auth/2fa/etat', jetonMere);
    verifier('2FA active après vérification', etatApres.statut === 200 && etatApres.json?.actif === true, etatApres.texte);

    // Le secret est chiffré en base, jamais en clair.
    const direct2 = new Client({ connectionString: DATABASE_URL });
    await direct2.connect();
    const ligne2fa = await direct2.query(`SELECT secret_chiffre, secret_iv, secret_tag FROM auth_2fa`);
    verifier('secret 2FA stocké chiffré', ligne2fa.rowCount === 1 && ligne2fa.rows[0].secret_chiffre !== secretTotp);
    verifier(
      'secret 2FA déchiffrable = secret renvoyé',
      dechiffrerSecret({
        valeur_chiffree: ligne2fa.rows[0].secret_chiffre,
        iv: ligne2fa.rows[0].secret_iv,
        tag: ligne2fa.rows[0].secret_tag,
      }) === secretTotp,
    );
    await direct2.end();

    // Connexion avec 2FA active.
    const loginSansCode = await appel('POST', '/auth/login', null, {
      identifiant: 'admin-exemple-t11@example.com',
      password: 'MotDePasse123!',
      channel: 'web',
    });
    verifier(
      'connexion sans code 2FA = 401 code_2fa_requis',
      loginSansCode.statut === 401 && loginSansCode.json?.error === 'code_2fa_requis',
      loginSansCode.texte,
    );
    const loginMauvaisCode = await appel('POST', '/auth/login', null, {
      identifiant: 'admin-exemple-t11@example.com',
      password: 'MotDePasse123!',
      code_2fa: '000000',
      channel: 'web',
    });
    verifier(
      'connexion avec code 2FA faux = 401 code_2fa_invalide',
      loginMauvaisCode.statut === 401 && loginMauvaisCode.json?.error === 'code_2fa_invalide',
      loginMauvaisCode.texte,
    );
    const loginBonCode = await appel('POST', '/auth/login', null, {
      identifiant: 'admin-exemple-t11@example.com',
      password: 'MotDePasse123!',
      code_2fa: codeTotp(secretTotp),
      channel: 'web',
    });
    verifier('connexion avec code 2FA juste = 200', loginBonCode.statut === 200 && typeof loginBonCode.json?.token === 'string', loginBonCode.texte);
    const jetonMere2fa = loginBonCode.json?.token;

    // Désactivation.
    const desactFaux = await appel('POST', '/auth/2fa/desactiver', jetonMere2fa, { code: '000000' });
    verifier('désactivation 2FA avec code faux = 401', desactFaux.statut === 401, desactFaux.texte);
    const desact = await appel('POST', '/auth/2fa/desactiver', jetonMere2fa, { code: codeTotp(secretTotp) });
    verifier('désactivation 2FA avec code juste', desact.statut === 200 && desact.json?.actif === false, desact.texte);
    const loginApres = await appel('POST', '/auth/login', null, {
      identifiant: 'admin-exemple-t11@example.com',
      password: 'MotDePasse123!',
      channel: 'web',
    });
    verifier('connexion normale après désactivation', loginApres.statut === 200, loginApres.texte);

    // --- Journal d'audit -------------------------------------------------------
    const audit = await appel('GET', '/audit', jetonMere);
    verifier(
      'journal audit lisible par admin, lignes avec hash',
      audit.statut === 200 &&
        (audit.json?.total ?? 0) > 0 &&
        audit.json?.items?.every((l) => typeof l.hash === 'string' && l.hash.length === 64),
      audit.texte.slice(0, 200),
    );
    const auditFidele = await appel('GET', '/audit', jetonFidele);
    verifier('journal audit refusé au fidèle', auditFidele.statut === 403, auditFidele.texte);

    const verificationChaine = await appel('GET', '/audit/verifier', jetonMere);
    verifier(
      'chaîne audit vérifiée',
      verificationChaine.statut === 200 &&
        verificationChaine.json?.ok === true &&
        (verificationChaine.json?.verifies ?? 0) > 0,
      verificationChaine.texte,
    );

    // Immuabilité : UPDATE et DELETE directs échouent.
    const direct3 = new Client({ connectionString: DATABASE_URL });
    await direct3.connect();
    let updateEchoue = false;
    try {
      await direct3.query(`UPDATE audit_logs SET action = 'pirate' WHERE id = (SELECT id FROM audit_logs LIMIT 1)`);
    } catch {
      updateEchoue = true;
    }
    verifier('UPDATE direct sur audit_logs refusé', updateEchoue);
    let deleteEchoue = false;
    try {
      await direct3.query(`DELETE FROM audit_logs WHERE id = (SELECT id FROM audit_logs LIMIT 1)`);
    } catch {
      deleteEchoue = true;
    }
    verifier('DELETE direct sur audit_logs refusé', deleteEchoue);
    await direct3.end();

    // Lectures sensibles (US17) : la fiche membre est journalisée.
    const lectureMembre = await appel('GET', `/membres/${membreId}`, jetonMere);
    verifier('lecture fiche membre', lectureMembre.statut === 200, lectureMembre.texte);
    const consultations = await appel('GET', '/audit/consultations', jetonMere);
    verifier(
      'consultation sensible journalisée',
      consultations.statut === 200 &&
        (consultations.json?.total ?? 0) >= 1 &&
        consultations.json?.items?.some((c) => c.ressource === 'membre' && c.ressource_id === membreId),
      consultations.texte.slice(0, 200),
    );

    // --- Sauvegarde chiffrée et restauration -----------------------------------
    const contribution = await appel('POST', '/contributions', jetonMere, {
      type: 'offrande',
      amount_fcfa: 5000,
      payment_method: 'especes',
    });
    verifier('contribution pour la sauvegarde', contribution.statut === 201, contribution.texte);

    const sauvegarde = await appel('POST', '/sauvegardes', jetonMere, {});
    verifier(
      'sauvegarde créée, chiffrée, avec empreinte',
      sauvegarde.statut === 201 &&
        (sauvegarde.json?.taille_octets ?? 0) > 0 &&
        /^[0-9a-f]{64}$/.test(sauvegarde.json?.empreinte ?? '') &&
        (sauvegarde.json?.nb_tables ?? 0) > 0,
      sauvegarde.texte.slice(0, 200),
    );
    const sauvegardeId = sauvegarde.json?.id;

    const listeSvg = await appel('GET', '/sauvegardes', jetonMere);
    verifier('liste des sauvegardes', listeSvg.statut === 200 && listeSvg.json?.total === 1, listeSvg.texte);
    const telechargement = await appel('GET', `/sauvegardes/${sauvegardeId}/telecharger`, jetonMere);
    verifier(
      'téléchargement sauvegarde = blob chiffré',
      telechargement.statut === 200 &&
        typeof telechargement.json?.contenu_chiffre === 'string' &&
        telechargement.json.contenu_chiffre.length > 0,
      telechargement.texte.slice(0, 120),
    );
    const sauvegardeFidele = await appel('POST', '/sauvegardes', jetonFidele, {});
    verifier('sauvegarde refusée au fidèle', sauvegardeFidele.statut === 403, sauvegardeFidele.texte);

    // Suppression du membre, puis restauration : le membre revient.
    const suppression = await appel('DELETE', `/membres/${membreId}`, jetonMere);
    verifier('suppression membre avant restauration', suppression.statut === 200, suppression.texte);
    const absent = await appel('GET', `/membres/${membreId}`, jetonMere);
    verifier('membre absent après suppression', absent.statut === 404, absent.texte);
    const restauration = await appel('POST', '/sauvegardes/restaurer', jetonMere, { sauvegarde_id: sauvegardeId });
    verifier(
      'restauration réussie',
      restauration.statut === 200 && restauration.json?.ok === true && (restauration.json?.lignes ?? 0) > 0,
      restauration.texte.slice(0, 200),
    );
    const revenu = await appel('GET', `/membres/${membreId}`, jetonMere);
    verifier('membre restauré', revenu.statut === 200 && revenu.json?.id === membreId, revenu.texte);
    const contributionsApres = await appel('GET', '/contributions', jetonMere);
    verifier(
      'contributions restaurées',
      contributionsApres.statut === 200 && (contributionsApres.json?.contributions?.length ?? 0) >= 1,
      contributionsApres.texte.slice(0, 120),
    );
    const restaurationInconnue = await appel('POST', '/sauvegardes/restaurer', jetonMere, { sauvegarde_id: '00000000-0000-0000-0000-000000000000' });
    verifier('restauration inconnue = 404', restaurationInconnue.statut === 404, restaurationInconnue.texte);

    // Paramètres de confiance.
    const params = await appel('GET', '/confiance/parametres', jetonMere);
    verifier(
      'paramètres de confiance par défaut',
      params.statut === 200 &&
        params.json?.sauvegarde_frequence === 'jamais' &&
        params.json?.notifications_configurees === false,
      params.texte,
    );
    const paramsModifies = await appel('PATCH', '/confiance/parametres', jetonMere, {
      sauvegarde_frequence: 'quotidienne',
      sauvegarde_heure: '03:00',
      notification_cle: 'cle-test-fournisseur-12345678',
      notification_plafond_mensuel: 1000,
    });
    verifier(
      'paramètres modifiés, clé jamais renvoyée',
      paramsModifies.statut === 200 &&
        paramsModifies.json?.sauvegarde_frequence === 'quotidienne' &&
        paramsModifies.json?.notification_cle === undefined &&
        paramsModifies.json?.notification_cle_chiffree === undefined,
      paramsModifies.texte,
    );

    // --- Notifications (aucun fournisseur branché) ------------------------------
    const notification = await appel('POST', '/notifications', jetonMere, {
      canal: 'push',
      titre: 'Rappel EXEMPLE',
      message: 'Culte dimanche à 10 h.',
    });
    verifier('notification créée en file', notification.statut === 201 && notification.json?.statut === 'en_attente', notification.texte);
    const notificationId = notification.json?.id;
    const envoi = await appel('POST', `/notifications/${notificationId}/envoyer`, jetonMere, {});
    verifier(
      'envoi sans fournisseur = 409, rien ne part',
      envoi.statut === 409 && envoi.json?.error === 'fournisseur_non_configure',
      envoi.texte,
    );
    const listeNotif = await appel('GET', '/notifications', jetonMere);
    verifier(
      'notification marquée non configurée',
      listeNotif.statut === 200 &&
        listeNotif.json?.items?.some((n) => n.id === notificationId && n.statut === 'non_configurée'),
      listeNotif.texte.slice(0, 200),
    );
    const notificationFidele = await appel('POST', '/notifications', jetonFidele, {
      titre: 'X',
      message: 'Y',
    });
    verifier('notification refusée au fidèle', notificationFidele.statut === 403, notificationFidele.texte);

    // --- File hors ligne ----------------------------------------------------------
    const action = await appel('POST', '/actions-hors-ligne', jetonMere, {
      type_action: 'presence.pointer',
      charge: { member_id: membreId, culte_id: culteId, mode: 'scan_qr' },
      cle_client: 'test-t11-pointage-1',
    });
    verifier('action hors ligne mise en file', action.statut === 201 && action.json?.statut === 'en_attente', action.texte);
    const doublon = await appel('POST', '/actions-hors-ligne', jetonMere, {
      type_action: 'presence.pointer',
      charge: { member_id: membreId, culte_id: culteId, mode: 'scan_qr' },
      cle_client: 'test-t11-pointage-1',
    });
    verifier('même cle_client = déjà enregistrée, pas de doublon', doublon.statut === 200 && doublon.json?.deja_enregistree === true, doublon.texte);
    const file = await appel('GET', '/actions-hors-ligne', jetonMere);
    verifier('file hors ligne : 1 action en attente', file.statut === 200 && file.json?.total === 1, file.texte);

    const rejeu = await appel('POST', '/actions-hors-ligne/rejouer-tout', jetonMere, {});
    verifier(
      'rejeu de la file : 1 pointage appliqué',
      rejeu.statut === 200 && rejeu.json?.rejouees === 1 && rejeu.json?.echouees === 0,
      rejeu.texte,
    );
    const presences = await appel('GET', `/presences?member_id=${membreId}`, jetonMere);
    verifier(
      'pointage rejoué visible',
      presences.statut === 200 && (presences.json?.total ?? 0) >= 1,
      presences.texte.slice(0, 200),
    );
    const fileApres = await appel('GET', '/actions-hors-ligne', jetonMere);
    verifier(
      'action marquée rejouée',
      fileApres.statut === 200 &&
        fileApres.json?.items?.some((a) => a.cle_client === 'test-t11-pointage-1' && a.statut === 'rejouee'),
      fileApres.texte.slice(0, 200),
    );

    // Une charge invalide échoue proprement au rejeu, sans bloquer la file.
    const mauvaise = await appel('POST', '/actions-hors-ligne', jetonMere, {
      type_action: 'contribution.creer',
      charge: { type: 'offrande', amount_fcfa: -5, payment_method: 'especes' },
      cle_client: 'test-t11-mauvaise-1',
    });
    verifier('mauvaise contribution mise en file', mauvaise.statut === 201, mauvaise.texte);
    const rejeu2 = await appel('POST', '/actions-hors-ligne/rejouer-tout', jetonMere, {});
    verifier(
      'rejeu : 0 appliquée, 1 en échec',
      rejeu2.statut === 200 && rejeu2.json?.rejouees === 0 && rejeu2.json?.echouees === 1,
      rejeu2.texte,
    );
    const fileFidele = await appel('GET', '/actions-hors-ligne', jetonFidele);
    verifier('file hors ligne refusée au fidèle', fileFidele.statut === 403, fileFidele.texte);

    // --- Isolation entre églises -----------------------------------------------------
    const autre = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Autre église EXEMPLE', city: 'Abidjan', phone: '+2250102030406' },
      admin: {
        full_name: 'Autre Admin EXEMPLE',
        email: 'admin-exemple-t11-autre@example.com',
        phone: '+2250102030406',
        password: 'MotDePasse123!',
      },
      channel: 'web',
    });
    const jetonAutre = autre.json?.token;
    const auditAutre = await appel('GET', '/audit', jetonAutre);
    const egliseMereId = mere.json?.church?.id;
    verifier(
      'autre église ne voit pas le journal de la première',
      auditAutre.statut === 200 &&
        (auditAutre.json?.items ?? []).every((l) => l.church_id !== egliseMereId),
      auditAutre.texte,
    );
    const restaurationAutre = await appel('POST', '/sauvegardes/restaurer', jetonAutre, { sauvegarde_id: sauvegardeId });
    verifier('restauration de la sauvegarde d’une autre église = 404', restaurationAutre.statut === 404, restaurationAutre.texte);
    const fileAutre = await appel('GET', '/actions-hors-ligne', jetonAutre);
    verifier('autre église ne voit pas la file', fileAutre.statut === 200 && fileAutre.json?.total === 0, fileAutre.texte);
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
