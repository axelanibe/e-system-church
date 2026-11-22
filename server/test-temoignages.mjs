// Test d'intégration du lot 3c (Témoignages) : migration 041,
// validation pure (types réels, tailles, texte), publication texte et
// photo, modération par l'admin (approuver / rejeter), isolation entre
// églises, accès contrôlé au média (Bearer ou ?token=), suppression
// (auteur ou admin) et limite de débit. Même forme que
// server/test-messagerie-t0.mjs : base fraîche créée puis vidée par le
// test lui-même, application du schéma puis des migrations avec le vrai
// moteur de migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-temoignages.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4113).
// Si DATABASE_URL est manquant, la boucle de .github/workflows/server.yml
// crée la base d'après le nom du script avant de le lancer ; le script
// recrée sinon sa propre base e_system_church_test_temoignages.
// Base locale : PostgreSQL est nécessaire.

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import {
  LONGUEUR_MAX_TEXTE_TEMOIGNAGE,
  detecterMimeReel,
  formaterTemoignagePublic,
  validerTemoignage,
} from './dist/temoignages.js';

const exec = promisify(execFile);

const PORT = Number(process.env.PORT ?? 4113);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_temoignages';
// Nom de la base visée par DATABASE_URL: <redacted>
const DB_NAME = new URL(DATABASE_URL).pathname.replace(/^\//, '');
// Secrets de test seulement, jamais utilisés en production (mêmes valeurs
// factices que test-messagerie-t0.mjs).
const JWT_SECRET = 'secret-test-temoignages-ne-pas-utiliser-en-production';
const PAYMENT_SECRETS_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

// PNG 1×1 transparent, octets réels : la détection du type réel et le
// téléchargement sont vérifiés sur ces octets exacts.
const PNG_1X1_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const PNG_1X1_OCTETS = Buffer.from(PNG_1X1_BASE64, 'base64');
// JPEG minimal : seuls les 3 premiers octets comptent pour la détection.
const JPEG_OCTETS = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00]);

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

async function appelOctets(chemin, jeton) {
  const url = jeton ? `${BASE}${chemin}?token=${jeton}` : `${BASE}${chemin}`;
  const reponse = await fetch(url);
  const tampon = Buffer.from(await reponse.arrayBuffer());
  return {
    statut: reponse.status,
    typeContenu: reponse.headers.get('content-type'),
    octets: tampon,
  };
}

async function appelOctetsBearer(chemin, jeton) {
  const reponse = await fetch(`${BASE}${chemin}`, {
    headers: { authorization: `Bearer ${jeton}` },
  });
  const tampon = Buffer.from(await reponse.arrayBuffer());
  return {
    statut: reponse.status,
    typeContenu: reponse.headers.get('content-type'),
    octets: tampon,
  };
}

async function main() {
  // --- 0. Validation pure, sans base ---------------------------------------
  verifier(
    'valider : texte seul accepté',
    validerTemoignage({ mime: null, tailleOctets: null, texte: 'Merci Seigneur.' }) === null,
  );
  verifier(
    'valider : vide refusé (400)',
    validerTemoignage({ mime: null, tailleOctets: null, texte: '   ' })?.statut === 400,
  );
  verifier(
    'valider : texte trop long refusé (400)',
    validerTemoignage({ mime: null, tailleOctets: null, texte: 'x'.repeat(LONGUEUR_MAX_TEXTE_TEMOIGNAGE + 1) })?.statut === 400,
  );
  verifier(
    'valider : type non autorisé refusé (415)',
    validerTemoignage({ mime: 'application/pdf', tailleOctets: 100, texte: '' })?.statut === 415,
  );
  verifier(
    'valider : vidéo trop volumineuse refusée (413)',
    validerTemoignage({ mime: 'video/mp4', tailleOctets: 26 * 1024 * 1024, texte: '' })?.statut === 413,
  );
  verifier(
    'détecter : PNG reconnu',
    detecterMimeReel(PNG_1X1_OCTETS) === 'image/png',
  );
  verifier(
    'détecter : JPEG reconnu',
    detecterMimeReel(JPEG_OCTETS) === 'image/jpeg',
  );
  verifier(
    'détecter : WAV reconnu',
    detecterMimeReel(Buffer.concat([Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WAVE')])) === 'audio/wav',
  );
  verifier(
    'détecter : OGG reconnu',
    detecterMimeReel(Buffer.from('OggSxxxx')) === 'audio/ogg',
  );
  verifier(
    'détecter : MP3 (ID3) reconnu',
    detecterMimeReel(Buffer.from('ID3xxxx')) === 'audio/mpeg',
  );
  verifier(
    'détecter : WebM reconnu',
    detecterMimeReel(Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 0, 0])) === 'video/webm',
  );
  verifier(
    'détecter : MP4 (isom) reconnu',
    detecterMimeReel(Buffer.concat([Buffer.from([0, 0, 0, 0]), Buffer.from('ftypisom'), Buffer.from([0, 0, 0, 0])])) === 'video/mp4',
  );
  verifier(
    'détecter : M4A reconnu',
    detecterMimeReel(Buffer.concat([Buffer.from([0, 0, 0, 0]), Buffer.from('ftypM4A '), Buffer.from([0, 0, 0, 0])])) === 'audio/mp4',
  );
  verifier(
    'détecter : contenu inconnu refusé',
    detecterMimeReel(Buffer.from('%PDF-1.7....')) === null,
  );
  verifier(
    'formater : texte seul sans url_media, statut par défaut',
    (() => {
      const f = formaterTemoignagePublic({ id: 'x', auteur_nom: 'A EXEMPLE', texte: 't', type_media: 'texte' });
      return f.url_media === null && f.statut === 'en_attente' && f.type_media === 'texte';
    })(),
  );

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

    // --- 1. Migration 041 : table, index, enregistrement --------------------
    const direct = new Client({ connectionString: DATABASE_URL });
    await direct.connect();
    const table = await direct.query(
      `SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'temoignages'`,
    );
    verifier('migration 041 : table temoignages créée', table.rowCount === 1);
    const index = await direct.query(
      `SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND indexname IN ('idx_temoignages_church_statut', 'idx_temoignages_auteur')`,
    );
    verifier('migration 041 : 2 index présents', index.rowCount === 2, `reçu ${index.rowCount}`);
    const migration = await direct.query(
      `SELECT 1 FROM schema_migrations WHERE name = '041_temoignages'`,
    );
    verifier('migration 041 enregistrée dans schema_migrations', migration.rowCount === 1);
    await direct.end();

    // --- 2. Préparation par API : deux églises, quatre comptes --------------
    const mereA = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan', phone: '+2250102030405' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-temoignage@example.com',
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
      email: 'fidele-exemple-temoignage@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle A par code', fideleA.statut === 201, fideleA.texte);
    const jetonFideleA = fideleA.json?.token;
    const fideleAUserId = fideleA.json?.user?.id;

    const fideleA2 = await appel('POST', '/auth/inscription-par-code', null, {
      code_eglise: mereA.json?.church?.code_fidele ?? mereA.json?.church?.code,
      nom_prenom: 'Autre Fidèle EXEMPLE',
      email: 'fidele2-exemple-temoignage@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080910',
    });
    verifier('inscription fidèle A2 par code', fideleA2.statut === 201, fideleA2.texte);
    const jetonFideleA2 = fideleA2.json?.token;

    const mereB = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Autre église EXEMPLE', city: 'Abidjan', phone: '+2250102030406' },
      admin: {
        full_name: 'Autre Admin EXEMPLE',
        email: 'admin-exemple-temoignage-autre@example.com',
        phone: '+2250102030406',
        password: 'MotDePasse123!',
      },
      channel: 'web',
    });
    verifier('inscription église B', mereB.statut === 201, mereB.texte);
    const jetonAdminB = mereB.json?.token;

    const fideleB = await appel('POST', '/auth/inscription-par-code', null, {
      code_eglise: mereB.json?.church?.code_fidele ?? mereB.json?.church?.code,
      nom_prenom: 'Fidèle B EXEMPLE',
      email: 'fidele-exemple-temoignage-b@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080919',
    });
    verifier('inscription fidèle B par code', fideleB.statut === 201, fideleB.texte);
    const jetonFideleB = fideleB.json?.token;

    // Fiche membre pour le fidèle A seulement (nom d'auteur résolu
    // depuis la fiche), puis liaison users.member_id en base.
    const fiche = await appel('POST', '/membres', jetonAdminA, {
      full_name: 'Fidèle EXEMPLE',
      phone: '+2250708080911',
      email: 'fidele-exemple-temoignage@example.com',
    });
    verifier('fiche membre fidèle A', fiche.statut === 201, fiche.texte);
    const liaison = new Client({ connectionString: DATABASE_URL });
    await liaison.connect();
    await liaison.query(`UPDATE users SET member_id = $1 WHERE id = $2`, [
      fiche.json?.id,
      fideleAUserId,
    ]);
    await liaison.end();

    // --- 3. Refus de publication --------------------------------------------
    const vide = await appel('POST', '/temoignages', jetonFideleA, {});
    verifier('publication vide = 400', vide.statut === 400, vide.texte);
    const tropLong = await appel('POST', '/temoignages', jetonFideleA, {
      texte: 'x'.repeat(LONGUEUR_MAX_TEXTE_TEMOIGNAGE + 1),
    });
    verifier('texte trop long = 400', tropLong.statut === 400, tropLong.texte);
    const mauvaisType = await appel('POST', '/temoignages', jetonFideleA, {
      texte: 'Témoignage EXEMPLE',
      media_base64: Buffer.from('%PDF-1.7....').toString('base64'),
      media_mime: 'application/pdf',
      media_nom: 'faux.pdf',
    });
    verifier('type non autorisé = 415', mauvaisType.statut === 415, mauvaisType.texte);
    const incoherent = await appel('POST', '/temoignages', jetonFideleA, {
      texte: 'Témoignage EXEMPLE',
      media_base64: JPEG_OCTETS.toString('base64'),
      media_mime: 'image/png',
      media_nom: 'photo.png',
    });
    verifier('type déclaré ≠ contenu réel = 415', incoherent.statut === 415, incoherent.texte);
    const sansJeton = await appel('POST', '/temoignages', null, { texte: 'Témoignage EXEMPLE' });
    verifier('publication sans jeton = 401', sansJeton.statut === 401, sansJeton.texte);

    // --- 4. Publications : texte seul + photo, en attente --------------------
    const texteSeul = await appel('POST', '/temoignages', jetonFideleA, {
      texte: 'Le Seigneur m’a relevé, je témoigne EXEMPLE.',
    });
    verifier(
      'publication texte seul = 201, en_attente, nom de la fiche membre',
      texteSeul.statut === 201 &&
        texteSeul.json?.statut === 'en_attente' &&
        texteSeul.json?.type_media === 'texte' &&
        texteSeul.json?.url_media === null &&
        texteSeul.json?.auteur_nom === 'Fidèle EXEMPLE',
      texteSeul.texte,
    );
    const idTexte = texteSeul.json?.id;
    const photo = await appel('POST', '/temoignages', jetonFideleA, {
      texte: 'Photo du baptême EXEMPLE.',
      media_base64: PNG_1X1_BASE64,
      media_mime: 'image/png',
      media_nom: 'bapteme.png',
    });
    verifier(
      'publication photo = 201, en_attente, url_media présente',
      photo.statut === 201 &&
        photo.json?.statut === 'en_attente' &&
        photo.json?.type_media === 'photo' &&
        typeof photo.json?.url_media === 'string',
      photo.texte,
    );
    const idPhoto = photo.json?.id;

    const lectureFidele = await appel('GET', '/temoignages', jetonFideleA);
    verifier(
      'fidèle A : fil vide, 2 miens, modération vide',
      lectureFidele.statut === 200 &&
        lectureFidele.json?.temoignages?.length === 0 &&
        lectureFidele.json?.mes_temoignages?.length === 2 &&
        lectureFidele.json?.moderation?.length === 0,
      lectureFidele.texte.slice(0, 200),
    );
    const lectureAdmin = await appel('GET', '/temoignages', jetonAdminA);
    verifier(
      'admin A : 2 en modération, fil vide',
      lectureAdmin.statut === 200 &&
        lectureAdmin.json?.moderation?.length === 2 &&
        lectureAdmin.json?.temoignages?.length === 0,
      lectureAdmin.texte.slice(0, 200),
    );

    // --- 5. Média : accès contrôlé -------------------------------------------
    const mediaAuteur = await appelOctetsBearer(`/temoignages/${idPhoto}/media`, jetonFideleA);
    verifier(
      'auteur télécharge sa photo en attente (200, image/png, octets exacts)',
      mediaAuteur.statut === 200 &&
        mediaAuteur.typeContenu === 'image/png' &&
        mediaAuteur.octets.equals(PNG_1X1_OCTETS),
      `statut ${mediaAuteur.statut}, type ${mediaAuteur.typeContenu}`,
    );
    const mediaJetonRequete = await appelOctets(`/temoignages/${idPhoto}/media`, jetonFideleA);
    verifier(
      'média par ?token= (200)',
      mediaJetonRequete.statut === 200 && mediaJetonRequete.octets.equals(PNG_1X1_OCTETS),
      `statut ${mediaJetonRequete.statut}`,
    );
    const mediaAdmin = await appelOctetsBearer(`/temoignages/${idPhoto}/media`, jetonAdminA);
    verifier('admin télécharge la photo en attente (200)', mediaAdmin.statut === 200, `statut ${mediaAdmin.statut}`);
    const mediaAutreMembre = await appelOctetsBearer(`/temoignages/${idPhoto}/media`, jetonFideleA2);
    verifier(
      'autre membre : photo en attente = 404',
      mediaAutreMembre.statut === 404,
      `statut ${mediaAutreMembre.statut}`,
    );
    const mediaAutreEglise = await appelOctetsBearer(`/temoignages/${idPhoto}/media`, jetonFideleB);
    verifier(
      'fidèle B (autre église) : photo = 404',
      mediaAutreEglise.statut === 404,
      `statut ${mediaAutreEglise.statut}`,
    );
    const mediaSansJeton = await appelOctets(`/temoignages/${idPhoto}/media`, null);
    verifier('média sans jeton = 401', mediaSansJeton.statut === 401, `statut ${mediaSansJeton.statut}`);

    // --- 6. Modération --------------------------------------------------------
    const modererFidele = await appel('POST', `/temoignages/${idTexte}/moderer`, jetonFideleA, {
      statut: 'approuve',
    });
    verifier('fidèle ne peut pas modérer = 403', modererFidele.statut === 403, modererFidele.texte);
    const modererInvalide = await appel('POST', `/temoignages/${idTexte}/moderer`, jetonAdminA, {
      statut: 'publie',
    });
    verifier('statut de modération invalide = 400', modererInvalide.statut === 400, modererInvalide.texte);
    const approuver = await appel('POST', `/temoignages/${idTexte}/moderer`, jetonAdminA, {
      statut: 'approuve',
    });
    verifier(
      'admin approuve le texte = 200, approuve',
      approuver.statut === 200 && approuver.json?.statut === 'approuve',
      approuver.texte,
    );
    const reapprouver = await appel('POST', `/temoignages/${idTexte}/moderer`, jetonAdminA, {
      statut: 'approuve',
    });
    verifier('modérer deux fois = 409', reapprouver.statut === 409, reapprouver.texte);
    const rejeter = await appel('POST', `/temoignages/${idPhoto}/moderer`, jetonAdminA, {
      statut: 'rejete',
      motif_rejet: 'Photo floue EXEMPLE.',
    });
    verifier(
      'admin rejette la photo = 200, rejete',
      rejeter.statut === 200 && rejeter.json?.statut === 'rejete',
      rejeter.texte,
    );

    const filApres = await appel('GET', '/temoignages', jetonFideleA2);
    verifier(
      'fil de l’église A : 1 approuvé seulement, sans statut exposé au-delà du texte',
      filApres.statut === 200 &&
        filApres.json?.temoignages?.length === 1 &&
        filApres.json?.temoignages?.[0]?.id === idTexte,
      filApres.texte.slice(0, 200),
    );
    const miensApres = await appel('GET', '/temoignages', jetonFideleA);
    verifier(
      'mes témoignages : approuvé + rejeté avec leurs statuts',
      miensApres.statut === 200 &&
        miensApres.json?.mes_temoignages?.length === 2 &&
        miensApres.json?.mes_temoignages?.some((t) => t.statut === 'approuve') &&
        miensApres.json?.mes_temoignages?.some((t) => t.statut === 'rejete'),
      miensApres.texte.slice(0, 200),
    );
    const moderationVide = await appel('GET', '/temoignages', jetonAdminA);
    verifier(
      'file de modération vide après décisions',
      moderationVide.statut === 200 && moderationVide.json?.moderation?.length === 0,
      moderationVide.texte.slice(0, 200),
    );
    const mediaRejeteeAutre = await appelOctetsBearer(`/temoignages/${idPhoto}/media`, jetonFideleA2);
    verifier(
      'photo rejetée : autre membre = 404',
      mediaRejeteeAutre.statut === 404,
      `statut ${mediaRejeteeAutre.statut}`,
    );

    // --- 7. Isolation entre églises ------------------------------------------
    // Un quatrième témoignage, encore en attente, pour tester la
    // modération inter-églises sur une ligne modérable.
    const quatrieme = await appel('POST', '/temoignages', jetonFideleA, {
      texte: 'Témoignage de contrôle EXEMPLE.',
    });
    verifier('quatrième témoignage publié', quatrieme.statut === 201, quatrieme.texte);
    const idQuatrieme = quatrieme.json?.id;
    const listeB = await appel('GET', '/temoignages', jetonFideleB);
    verifier(
      'fidèle B : fil vide, miens vides, modération vide',
      listeB.statut === 200 &&
        listeB.json?.temoignages?.length === 0 &&
        listeB.json?.mes_temoignages?.length === 0 &&
        listeB.json?.moderation?.length === 0,
      listeB.texte.slice(0, 200),
    );
    const modererB = await appel('POST', `/temoignages/${idQuatrieme}/moderer`, jetonAdminB, {
      statut: 'rejete',
    });
    verifier(
      'admin B modère un témoignage en attente de A = 409 (introuvable dans son église)',
      modererB.statut === 409,
      modererB.texte,
    );
    // Nettoyage : l'auteur supprime ce témoignage de contrôle, pour ne
    // pas fausser les comptes de la section 8.
    const nettoyerQuatrieme = await appel('DELETE', `/temoignages/${idQuatrieme}`, jetonFideleA);
    verifier('nettoyage du témoignage de contrôle', nettoyerQuatrieme.statut === 200, nettoyerQuatrieme.texte);

    // --- 8. Suppression -------------------------------------------------------
    const supprimerAutre = await appel('DELETE', `/temoignages/${idTexte}`, jetonFideleA2);
    verifier(
      'autre membre ne peut pas supprimer = 403',
      supprimerAutre.statut === 403,
      supprimerAutre.texte,
    );
    const troisieme = await appel('POST', '/temoignages', jetonFideleA, {
      texte: 'Témoignage à supprimer EXEMPLE.',
    });
    const idTroisieme = troisieme.json?.id;
    await appel('POST', `/temoignages/${idTroisieme}/moderer`, jetonAdminA, { statut: 'approuve' });
    const supprimerAuteur = await appel('DELETE', `/temoignages/${idTroisieme}`, jetonFideleA);
    verifier('auteur supprime son témoignage approuvé = 200', supprimerAuteur.statut === 200, supprimerAuteur.texte);
    const filApresSuppression = await appel('GET', '/temoignages', jetonFideleA2);
    verifier(
      'fil après suppression : 1 témoignage restant',
      filApresSuppression.json?.temoignages?.length === 1,
      filApresSuppression.texte.slice(0, 200),
    );
    const supprimerAdmin = await appel('DELETE', `/temoignages/${idPhoto}`, jetonAdminA);
    verifier('admin supprime la photo rejetée = 200', supprimerAdmin.statut === 200, supprimerAdmin.texte);
    const miensFin = await appel('GET', '/temoignages', jetonFideleA);
    verifier(
      'mes témoignages : 1 restant après suppressions',
      miensFin.json?.mes_temoignages?.length === 1,
      miensFin.texte.slice(0, 200),
    );
    const supprimerIntrouvable = await appel('DELETE', `/temoignages/${idPhoto}`, jetonAdminA);
    verifier('supprimer deux fois = 404', supprimerIntrouvable.statut === 404, supprimerIntrouvable.texte);

    // --- 9. Limite de débit : 10 publications / heure / auteur ---------------
    // Admin B n'a rien publié : ses 10 premières passent, la 11e est refusée.
    let dixOk = true;
    for (let i = 0; i < 10; i += 1) {
      const p = await appel('POST', '/temoignages', jetonAdminB, {
        texte: `Témoignage débit EXEMPLE ${i}.`,
      });
      if (p.statut !== 201) dixOk = false;
    }
    verifier('10 publications par heure acceptées', dixOk);
    const onzieme = await appel('POST', '/temoignages', jetonAdminB, {
      texte: 'Témoignage débit EXEMPLE 10.',
    });
    verifier('11e publication dans l’heure = 429', onzieme.statut === 429, onzieme.texte);

    // --- 10. Sans jeton --------------------------------------------------------
    const listeSansJeton = await appel('GET', '/temoignages', null);
    verifier('liste sans jeton = 401', listeSansJeton.statut === 401, listeSansJeton.texte);
    verifier('église A toujours isolée (sanity)', typeof egliseAId === 'string' && typeof adminAUserId === 'string');
  } catch (e) {
    echecs += 1;
    console.log('  ECHEC exception', e);
  } finally {
    api.kill();
    try {
      await once(api, 'exit');
    } catch {
      // Déjà terminé.
    }
  }
  console.log(`\nTémoignages : ${echecs === 0 ? 'OK' : `${echecs} échec(s)`}.`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
