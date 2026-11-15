// Test d'intégration de la tranche T9 (Lot B) — Bible (Louis Segond 1910
// et King James Version, domaine public, sources eBible.org), concordance
// Strong (Open Scriptures, CC-BY-SA) et dictionnaire biblique (Aquifer
// Open Bible Dictionary, CC BY-SA 4.0), et école biblique (cours, leçons,
// inscriptions, progression), partie serveur (migration 027).
//
// Périmètre : GET /bible/versions, GET /bible/livres, GET
// /bible/livres/:code/chapitres/:n, GET /bible/recherche (paramètre
// ?version=lsg1910|kjv, défaut lsg1910) ; GET /bible/strong/:numero et
// GET /bible/strong/recherche ; GET /bible/dictionnaire/:titre et
// GET /bible/dictionnaire/recherche (?langue=fra|eng, défaut fra) ;
// CRUD /cours-ecole et /lecons-ecole (WRITE_STD) ; inscriptions
// (auto-inscription du membre, propriétaire ou gestionnaire pour la
// suite) ; POST /inscriptions-ecole/:id/terminer (idempotent, statut
// 'termine' posé par le serveur) ; GET .../progression.
// Rôles : un membre ne peut pas créer/modifier un cours ou une leçon,
// un admin oui ; un membre ne voit que ses propres inscriptions.
//
// Base fraîche, application du schéma puis des migrations avec le vrai
// moteur (dist/migrate.js), démarrage de l'API, appels HTTP, droits
// 401/403/404 et isolation entre églises. Aucun vrai envoi.
//
// Usage (depuis la racine du dépôt, après `npm run build` dans server/) :
//   `node server/test-lot-b-t9-ecole-biblique.mjs`
// Variables : PORT (défaut 4109). PostgreSQL local requis
// (utilisateur postgres / postgres).

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);
const JWT_SECRET = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const ADMIN = 'postgres://postgres:postgres@127.0.0.1:5432/postgres';
const NOM_DB = 'e_system_church_test_t9';

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
  const port = Number(process.env.PORT ?? 4109);
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
        // Une route qui ne répond pas doit échouer vite, pas attendre
        // le délai d'en-tête par défaut (300 s).
        signal: AbortSignal.timeout(15000),
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

    // --- Préparation : église, admin, rôles, membres ----------------------
    const mere = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère T9', city: 'Abidjan' },
      admin: {
        full_name: 'Admin mère T9',
        email: 'admin-mere-t9@example.com',
        password: 'Test1234!',
      },
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonAdmin = mere.json?.token;
    const egliseId = mere.json?.church?.id;

    const hash = await argon2.hash('Test1234!');
    async function creerCompte(email, role, memberId = null) {
      const { rows } = await pool.query(
        `INSERT INTO users (email, password_hash, full_name, member_id) VALUES ($1, $2, $3, $4) RETURNING id`,
        [email, hash, email, memberId],
      );
      const userId = rows[0].id;
      await pool.query(
        `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`,
        [userId, egliseId, role],
      );
      return userId;
    }
    await creerCompte('culte-t9@example.com', 'responsable_culte');
    await creerCompte('tresorier-t9@example.com', 'tresorier');
    const jetonCulte = await login('culte-t9@example.com');
    const jetonTresorier = await login('tresorier-t9@example.com');

    async function creerMembre(nom) {
      const r = await appel('POST', '/membres', jetonAdmin, { full_name: nom, status: 'actif' });
      if (r.statut !== 201) throw new Error(`création membre ${nom}: ${r.texte}`);
      return r.json.id;
    }
    const idFidele = await creerMembre('Fidèle Élève T9');
    const idAutre = await creerMembre('Autre Membre T9');
    await creerCompte('fidele-t9@example.com', 'membre', idFidele);
    await creerCompte('autre-t9@example.com', 'membre', idAutre);
    const jetonFidele = await login('fidele-t9@example.com');
    const jetonAutre = await login('autre-t9@example.com');

    // --- A. Bible (Louis Segond 1910, domaine public) ----------------------
    console.log('A. Bible :');
    const sansJeton = await appel('GET', '/bible/livres', null);
    verifier('GET /bible/livres sans jeton : 401', sansJeton.statut === 401, sansJeton.texte);
    const livres = await appel('GET', '/bible/livres', jetonAdmin);
    const canon = livres.json?.livres ?? [];
    verifier(
      'GET /bible/livres admin : 200, 66 livres',
      livres.statut === 200 && canon.length === 66,
      livres.texte.slice(0, 200),
    );
    verifier(
      'canon : GEN 50 chapitres, PSA 150, JHN 21, REV 22',
      canon.find((l) => l.code === 'GEN')?.chapitres === 50 &&
        canon.find((l) => l.code === 'PSA')?.chapitres === 150 &&
        canon.find((l) => l.code === 'JHN')?.chapitres === 21 &&
        canon.find((l) => l.code === 'REV')?.chapitres === 22,
      livres.texte.slice(0, 200),
    );
    const livresMembre = await appel('GET', '/bible/livres', jetonFidele);
    verifier(
      'GET /bible/livres membre : 200 (lecture ouverte à tous)',
      livresMembre.statut === 200 && (livresMembre.json?.livres ?? []).length === 66,
      livresMembre.texte.slice(0, 200),
    );
    const gen1 = await appel('GET', '/bible/livres/GEN/chapitres/1', jetonAdmin);
    verifier(
      'GEN 1 : 31 versets, verset 1 exact',
      gen1.statut === 200 &&
        gen1.json?.versets?.length === 31 &&
        gen1.json.versets[0]?.texte === 'Au commencement, Dieu créa les cieux et la terre.',
      gen1.texte.slice(0, 300),
    );
    const jhn3 = await appel('GET', '/bible/livres/JHN/chapitres/3', jetonFidele);
    verifier(
      'JHN 3:16 : « Dieu a tant aimé le monde »',
      jhn3.statut === 200 &&
        jhn3.json?.versets?.[15]?.numero === 16 &&
        (jhn3.json.versets[15]?.texte ?? '').includes('Dieu a tant aimé le monde'),
      jhn3.texte.slice(0, 300),
    );
    const psa119 = await appel('GET', '/bible/livres/PSA/chapitres/119', jetonAdmin);
    verifier(
      'PSA 119 : 176 versets',
      psa119.statut === 200 && psa119.json?.versets?.length === 176,
      psa119.texte.slice(0, 200),
    );
    const livreInconnu = await appel('GET', '/bible/livres/XXX/chapitres/1', jetonAdmin);
    verifier('livre inconnu : 404', livreInconnu.statut === 404, livreInconnu.texte);
    const chapitreHors = await appel('GET', '/bible/livres/GEN/chapitres/99', jetonAdmin);
    verifier('chapitre hors limites : 404', chapitreHors.statut === 404, chapitreHors.texte);
    const recherche = await appel('GET', '/bible/recherche?q=berger', jetonFidele);
    verifier(
      'recherche « berger » : PSA 23:1 dans les résultats',
      recherche.statut === 200 &&
        (recherche.json?.resultats ?? []).some(
          (r) => r.code === 'PSA' && r.chapitre === 23 && r.verset === 1,
        ),
      recherche.texte.slice(0, 300),
    );
    const rechercheCourte = await appel('GET', '/bible/recherche?q=a', jetonAdmin);
    verifier('recherche 1 caractère : 400', rechercheCourte.statut === 400, rechercheCourte.texte);
    const rechercheVide = await appel('GET', '/bible/recherche', jetonAdmin);
    verifier('recherche sans q : 400', rechercheVide.statut === 400, rechercheVide.texte);

    // --- A2. Versions : LS1910 (défaut) + KJV ------------------------------
    console.log('A2. Versions (LS1910 + KJV) :');
    const versions = await appel('GET', '/bible/versions', jetonAdmin);
    const vLsg = (versions.json?.versions ?? []).find((v) => v.id === 'lsg1910');
    const vKjv = (versions.json?.versions ?? []).find((v) => v.id === 'kjv');
    verifier(
      'GET /bible/versions : 2 versions, lsg1910 66 livres / 31 170 versets, kjv 66 / 31 102',
      versions.statut === 200 &&
        vLsg?.livres === 66 && vLsg?.versets === 31170 &&
        vKjv?.livres === 66 && vKjv?.versets === 31102,
      versions.texte.slice(0, 300),
    );
    const livresKjv = await appel('GET', '/bible/livres?version=kjv', jetonAdmin);
    verifier(
      'GET /bible/livres?version=kjv : 66 livres, GEN = Genesis',
      livresKjv.statut === 200 &&
        (livresKjv.json?.livres ?? []).length === 66 &&
        livresKjv.json.livres.find((l) => l.code === 'GEN')?.nom === 'Genesis',
      livresKjv.texte.slice(0, 200),
    );
    const gen1Kjv = await appel('GET', '/bible/livres/GEN/chapitres/1?version=kjv', jetonAdmin);
    verifier(
      'KJV GEN 1 : 31 versets, verset 1 exact',
      gen1Kjv.statut === 200 &&
        gen1Kjv.json?.versets?.length === 31 &&
        gen1Kjv.json.versets[0]?.texte === 'In the beginning God created the heaven and the earth.',
      gen1Kjv.texte.slice(0, 300),
    );
    const jhn3Kjv = await appel('GET', '/bible/livres/JHN/chapitres/3?version=kjv', jetonFidele);
    verifier(
      'KJV JHN 3:16 : « For God so loved the world »',
      jhn3Kjv.statut === 200 &&
        (jhn3Kjv.json?.versets?.[15]?.texte ?? '').includes('For God so loved the world'),
      jhn3Kjv.texte.slice(0, 300),
    );
    const psa23Kjv = await appel('GET', '/bible/livres/PSA/chapitres/23?version=kjv', jetonAdmin);
    verifier(
      'KJV PSA 23:1 : « The LORD is my shepherd » (sans suscription)',
      psa23Kjv.statut === 200 &&
        psa23Kjv.json?.versets?.[0]?.texte === 'The LORD is my shepherd; I shall not want.',
      psa23Kjv.texte.slice(0, 300),
    );
    const rechercheKjv = await appel('GET', '/bible/recherche?q=shepherd&version=kjv', jetonFidele);
    verifier(
      'recherche KJV « shepherd » : PSA 23:1 dans les résultats',
      rechercheKjv.statut === 200 &&
        (rechercheKjv.json?.resultats ?? []).some(
          (r) => r.code === 'PSA' && r.chapitre === 23 && r.verset === 1,
        ),
      rechercheKjv.texte.slice(0, 300),
    );
    const versionInconnue = await appel('GET', '/bible/livres?version=xyz', jetonAdmin);
    verifier('version inconnue : 400', versionInconnue.statut === 400, versionInconnue.texte);
    const versionInconnueChapitre = await appel(
      'GET', '/bible/livres/GEN/chapitres/1?version=xyz', jetonAdmin);
    verifier(
      'version inconnue (chapitre) : 400',
      versionInconnueChapitre.statut === 400,
      versionInconnueChapitre.texte,
    );

    // --- A3. Concordance Strong --------------------------------------------
    console.log('A3. Concordance Strong :');
    const sansJetonStrong = await appel('GET', '/bible/strong/H1', null);
    verifier('GET /bible/strong/H1 sans jeton : 401', sansJetonStrong.statut === 401, sansJetonStrong.texte);
    const h1 = await appel('GET', '/bible/strong/H1', jetonAdmin);
    verifier(
      'H1 : lemme אָב, définition « father »',
      h1.statut === 200 &&
        h1.json?.entree?.lemma === 'אָב' &&
        (h1.json.entree.strongs_def ?? '').includes('father'),
      h1.texte.slice(0, 300),
    );
    const g1minuscule = await appel('GET', '/bible/strong/g1', jetonFidele);
    verifier(
      'g1 (minuscule) : normalisé en G1, lemme Α',
      g1minuscule.statut === 200 && g1minuscule.json?.entree?.numero === 'G1' &&
        g1minuscule.json?.entree?.lemma === 'Α',
      g1minuscule.texte.slice(0, 200),
    );
    const h8674 = await appel('GET', '/bible/strong/H8674', jetonAdmin);
    verifier(
      'H8674 (dernier numéro hébreu) : Tattenai',
      h8674.statut === 200 &&
        (h8674.json?.entree?.strongs_def ?? '').includes('Tattenai'),
      h8674.texte.slice(0, 200),
    );
    const g5624 = await appel('GET', '/bible/strong/G5624', jetonAdmin);
    verifier('G5624 (dernier numéro grec) : 200', g5624.statut === 200, g5624.texte.slice(0, 200));
    const strongAbsent = await appel('GET', '/bible/strong/G9999', jetonAdmin);
    verifier('G9999 (numéro absent) : 404', strongAbsent.statut === 404, strongAbsent.texte);
    const strongInvalide = await appel('GET', '/bible/strong/XYZ', jetonAdmin);
    verifier('XYZ (format invalide) : 400', strongInvalide.statut === 400, strongInvalide.texte);
    const rechercheStrong = await appel('GET', '/bible/strong/recherche?q=father', jetonFidele);
    verifier(
      'recherche Strong « father » : H1 dans les résultats',
      rechercheStrong.statut === 200 &&
        (rechercheStrong.json?.resultats ?? []).some((e) => e.numero === 'H1'),
      rechercheStrong.texte.slice(0, 300),
    );
    const rechercheStrongNumero = await appel('GET', '/bible/strong/recherche?q=G1', jetonAdmin);
    verifier(
      'recherche Strong « G1 » : l’entrée G1 en premier',
      rechercheStrongNumero.statut === 200 &&
        rechercheStrongNumero.json?.resultats?.[0]?.numero === 'G1',
      rechercheStrongNumero.texte.slice(0, 200),
    );
    const rechercheStrongCourte = await appel('GET', '/bible/strong/recherche?q=a', jetonAdmin);
    verifier('recherche Strong 1 caractère : 400', rechercheStrongCourte.statut === 400, rechercheStrongCourte.texte);

    // --- A4. Dictionnaire biblique -----------------------------------------
    console.log('A4. Dictionnaire :');
    const sansJetonDict = await appel('GET', '/bible/dictionnaire/recherche?q=Mo%C3%AFse', null);
    verifier('recherche dictionnaire sans jeton : 401', sansJetonDict.statut === 401, sansJetonDict.texte);
    const dictMoise = await appel('GET', '/bible/dictionnaire/recherche?q=Mo%C3%AFse', jetonFidele);
    verifier(
      'recherche dictionnaire « Moïse » (fra) : 4 475 articles, « Moïse » dans les résultats',
      dictMoise.statut === 200 &&
        dictMoise.json?.articles === 4475 &&
        (dictMoise.json?.resultats ?? []).some((r) => r.titre === 'Moïse'),
      dictMoise.texte.slice(0, 300),
    );
    const articleMoise = await appel('GET', '/bible/dictionnaire/Mo%C3%AFse', jetonAdmin);
    verifier(
      'article « Moïse » : texte non vide, parle de l’Égypte',
      articleMoise.statut === 200 &&
        (articleMoise.json?.article?.texte ?? '').length > 1000 &&
        (articleMoise.json.article.texte ?? '').includes('Égypte'),
      articleMoise.texte.slice(0, 300),
    );
    const dictMoses = await appel('GET', '/bible/dictionnaire/recherche?q=Moses&langue=eng', jetonFidele);
    verifier(
      'recherche dictionnaire « Moses » (eng) : 6 074 articles, « Moses » dans les résultats',
      dictMoses.statut === 200 &&
        dictMoses.json?.articles === 6074 &&
        (dictMoses.json?.resultats ?? []).some((r) => r.titre === 'Moses'),
      dictMoses.texte.slice(0, 300),
    );
    const articleJesus = await appel('GET', '/bible/dictionnaire/Jesus?langue=eng', jetonAdmin);
    verifier(
      'article « Jesus » (eng) : texte non vide',
      articleJesus.statut === 200 &&
        (articleJesus.json?.article?.texte ?? '').length > 100,
      articleJesus.texte.slice(0, 200),
    );
    const articleAbsent = await appel('GET', '/bible/dictionnaire/ZzzzzIntrouvable', jetonAdmin);
    verifier('article introuvable : 404', articleAbsent.statut === 404, articleAbsent.texte);
    const langueInconnue = await appel('GET', '/bible/dictionnaire/recherche?q=Moise&langue=xyz', jetonAdmin);
    verifier('langue inconnue : 400', langueInconnue.statut === 400, langueInconnue.texte);
    const rechercheDictCourte = await appel('GET', '/bible/dictionnaire/recherche?q=a', jetonAdmin);
    verifier('recherche dictionnaire 1 caractère : 400', rechercheDictCourte.statut === 400, rechercheDictCourte.texte);

    // --- B. Cours ------------------------------------------------------------
    console.log('B. Cours :');
    const coursMembre = await appel('POST', '/cours-ecole', jetonFidele, {
      titre: 'Cours interdit',
    });
    verifier('POST /cours-ecole membre : 403', coursMembre.statut === 403, coursMembre.texte);
    const coursTresorier = await appel('POST', '/cours-ecole', jetonTresorier, {
      titre: 'Cours interdit',
    });
    verifier('POST /cours-ecole trésorier : 403', coursTresorier.statut === 403, coursTresorier.texte);
    const cours1 = await appel('POST', '/cours-ecole', jetonAdmin, {
      titre: 'Fondements de la foi',
      description: 'Les bases de la foi chrétienne.',
      niveau: 'debutant',
    });
    verifier('POST /cours-ecole admin : 201', cours1.statut === 201, cours1.texte);
    const cours2 = await appel('POST', '/cours-ecole', jetonCulte, {
      titre: 'Étude des Psaumes',
      niveau: 'intermediaire',
    });
    verifier('POST /cours-ecole responsable : 201', cours2.statut === 201, cours2.texte);
    const coursSansTitre = await appel('POST', '/cours-ecole', jetonAdmin, { description: 'x' });
    verifier('POST /cours-ecole sans titre : 400', coursSansTitre.statut === 400, coursSansTitre.texte);
    const listeCours = await appel('GET', '/cours-ecole', jetonFidele);
    verifier(
      'GET /cours-ecole membre : 200, 2 cours',
      listeCours.statut === 200 && listeCours.json?.total === 2,
      listeCours.texte,
    );
    const patchMembre = await appel('PATCH', `/cours-ecole/${cours1.json?.id}`, jetonFidele, {
      actif: false,
    });
    verifier('PATCH /cours-ecole membre : 403', patchMembre.statut === 403, patchMembre.texte);
    const patchAdmin = await appel('PATCH', `/cours-ecole/${cours2.json?.id}`, jetonAdmin, {
      actif: false,
    });
    verifier(
      'PATCH /cours-ecole admin : 200, cours désactivé',
      patchAdmin.statut === 200 && patchAdmin.json?.actif === false,
      patchAdmin.texte,
    );
    const auditsCours = await pool.query(
      `SELECT action FROM audit_logs WHERE action = 'cours_ecole.cree'`,
    );
    verifier('création de cours journalisée', auditsCours.rowCount >= 1, `lignes=${auditsCours.rowCount}`);

    // --- C. Leçons -----------------------------------------------------------
    console.log('C. Leçons :');
    const leconMembre = await appel('POST', '/lecons-ecole', jetonFidele, {
      cours_id: cours1.json?.id,
      ordre: 1,
      titre: 'Leçon interdite',
    });
    verifier('POST /lecons-ecole membre : 403', leconMembre.statut === 403, leconMembre.texte);
    const leconCoursInconnu = await appel('POST', '/lecons-ecole', jetonAdmin, {
      cours_id: '00000000-0000-0000-0000-000000000000',
      ordre: 1,
      titre: 'Leçon orpheline',
    });
    verifier('POST /lecons-ecole cours inconnu : 400', leconCoursInconnu.statut === 400, leconCoursInconnu.texte);
    const lecon1 = await appel('POST', '/lecons-ecole', jetonAdmin, {
      cours_id: cours1.json?.id,
      ordre: 1,
      titre: 'Dieu créateur',
      contenu: 'Au commencement, Dieu créa les cieux et la terre.',
      reference_biblique: 'Genèse 1:1',
    });
    verifier('POST /lecons-ecole admin ordre 1 : 201', lecon1.statut === 201, lecon1.texte);
    const lecon2 = await appel('POST', '/lecons-ecole', jetonCulte, {
      cours_id: cours1.json?.id,
      ordre: 2,
      titre: 'La foi qui sauve',
      reference_biblique: 'Jean 3:16',
    });
    verifier('POST /lecons-ecole responsable ordre 2 : 201', lecon2.statut === 201, lecon2.texte);
    const leconDoublon = await appel('POST', '/lecons-ecole', jetonAdmin, {
      cours_id: cours1.json?.id,
      ordre: 1,
      titre: 'Doublon',
    });
    verifier('POST /lecons-ecole ordre doublon : 400', leconDoublon.statut === 400, leconDoublon.texte);
    const listeLecons = await appel(
      'GET',
      `/lecons-ecole?cours_id=${cours1.json?.id}`,
      jetonFidele,
    );
    verifier(
      'GET /lecons-ecole?cours_id : 2 leçons, ordre croissant',
      listeLecons.statut === 200 &&
        listeLecons.json?.total === 2 &&
        listeLecons.json.items[0]?.ordre === 1 &&
        listeLecons.json.items[1]?.ordre === 2,
      listeLecons.texte,
    );
    const patchOrdre = await appel('PATCH', `/lecons-ecole/${lecon2.json?.id}`, jetonAdmin, {
      ordre: 1,
    });
    verifier('PATCH /lecons-ecole ordre en conflit : 400', patchOrdre.statut === 400, patchOrdre.texte);

    // --- D. Inscriptions ------------------------------------------------------
    console.log('D. Inscriptions :');
    const inscription = await appel('POST', '/inscriptions-ecole', jetonFidele, {
      cours_id: cours1.json?.id,
    });
    verifier(
      'POST /inscriptions-ecole membre (auto-inscription) : 201',
      inscription.statut === 201 && inscription.json?.member_id === idFidele,
      inscription.texte,
    );
    const inscriptionAutre = await appel('POST', '/inscriptions-ecole', jetonFidele, {
      cours_id: cours1.json?.id,
      member_id: idAutre,
    });
    verifier(
      "POST /inscriptions-ecole membre pour un autre : 403",
      inscriptionAutre.statut === 403,
      inscriptionAutre.texte,
    );
    const inscriptionDoublon = await appel('POST', '/inscriptions-ecole', jetonFidele, {
      cours_id: cours1.json?.id,
    });
    verifier(
      'POST /inscriptions-ecole doublon : 409',
      inscriptionDoublon.statut === 409,
      inscriptionDoublon.texte,
    );
    const inscriptionAdmin = await appel('POST', '/inscriptions-ecole', jetonAdmin, {
      cours_id: cours1.json?.id,
      member_id: idAutre,
    });
    verifier(
      'POST /inscriptions-ecole admin pour un membre : 201',
      inscriptionAdmin.statut === 201,
      inscriptionAdmin.texte,
    );
    const inscriptionAdminSansMembre = await appel('POST', '/inscriptions-ecole', jetonAdmin, {
      cours_id: cours1.json?.id,
    });
    verifier(
      'POST /inscriptions-ecole admin sans member_id : 400',
      inscriptionAdminSansMembre.statut === 400,
      inscriptionAdminSansMembre.texte,
    );
    const inscriptionCoursInactif = await appel('POST', '/inscriptions-ecole', jetonFidele, {
      cours_id: cours2.json?.id,
    });
    verifier(
      'POST /inscriptions-ecole cours inactif : 400',
      inscriptionCoursInactif.statut === 400,
      inscriptionCoursInactif.texte,
    );
    const listeInscrMembre = await appel('GET', '/inscriptions-ecole', jetonFidele);
    verifier(
      'GET /inscriptions-ecole membre : 1 seule (la sienne)',
      listeInscrMembre.statut === 200 &&
        listeInscrMembre.json?.total === 1 &&
        listeInscrMembre.json.items[0]?.member_id === idFidele,
      listeInscrMembre.texte,
    );
    const listeInscrAdmin = await appel('GET', '/inscriptions-ecole', jetonAdmin);
    verifier(
      'GET /inscriptions-ecole admin : 2 inscriptions',
      listeInscrAdmin.statut === 200 && listeInscrAdmin.json?.total === 2,
      listeInscrAdmin.texte,
    );
    const lectureAutre = await appel(
      'GET',
      `/inscriptions-ecole/${inscriptionAdmin.json?.id}`,
      jetonFidele,
    );
    verifier(
      "GET /inscriptions-ecole/:id d'un autre par le fidèle : 404",
      lectureAutre.statut === 404,
      lectureAutre.texte,
    );
    const patchTermine = await appel(
      'PATCH',
      `/inscriptions-ecole/${inscription.json?.id}`,
      jetonFidele,
      { statut: 'termine' },
    );
    verifier(
      "PATCH statut 'termine' par le fidèle : 400 (géré par le serveur)",
      patchTermine.statut === 400,
      patchTermine.texte,
    );
    const patchAbandon = await appel(
      'PATCH',
      `/inscriptions-ecole/${inscription.json?.id}`,
      jetonFidele,
      { statut: 'abandonne' },
    );
    verifier(
      "PATCH statut 'abandonne' par le fidèle : 200",
      patchAbandon.statut === 200 && patchAbandon.json?.statut === 'abandonne',
      patchAbandon.texte,
    );
    const patchReprise = await appel(
      'PATCH',
      `/inscriptions-ecole/${inscription.json?.id}`,
      jetonFidele,
      { statut: 'inscrit' },
    );
    verifier(
      "PATCH statut 'inscrit' (reprise) : 200",
      patchReprise.statut === 200 && patchReprise.json?.statut === 'inscrit',
      patchReprise.texte,
    );

    // --- E. Progression -------------------------------------------------------
    console.log('E. Progression :');
    const inscriptionId = inscription.json?.id;
    const terminerAutreMembre = await appel(
      'POST',
      `/inscriptions-ecole/${inscriptionId}/terminer`,
      jetonAutre,
      { lecon_id: lecon1.json?.id },
    );
    verifier(
      'POST /terminer par un autre membre : 403',
      terminerAutreMembre.statut === 403,
      terminerAutreMembre.texte,
    );
    const terminer1 = await appel(
      'POST',
      `/inscriptions-ecole/${inscriptionId}/terminer`,
      jetonFidele,
      { lecon_id: lecon1.json?.id },
    );
    verifier('POST /terminer leçon 1 : 200', terminer1.statut === 200, terminer1.texte);
    const terminer1Bis = await appel(
      'POST',
      `/inscriptions-ecole/${inscriptionId}/terminer`,
      jetonFidele,
      { lecon_id: lecon1.json?.id },
    );
    verifier(
      'POST /terminer même leçon : 200 idempotent (même ligne)',
      terminer1Bis.statut === 200 && terminer1Bis.json?.id === terminer1.json?.id,
      terminer1Bis.texte,
    );
    const progression1 = await appel(
      'GET',
      `/inscriptions-ecole/${inscriptionId}/progression`,
      jetonFidele,
    );
    verifier(
      'GET /progression : 1/2, 50 %',
      progression1.statut === 200 &&
        progression1.json?.terminees === 1 &&
        progression1.json?.total === 2 &&
        progression1.json?.pourcentage === 50,
      progression1.texte,
    );
    const terminer2 = await appel(
      'POST',
      `/inscriptions-ecole/${inscriptionId}/terminer`,
      jetonFidele,
      { lecon_id: lecon2.json?.id },
    );
    verifier('POST /terminer leçon 2 : 200', terminer2.statut === 200, terminer2.texte);
    const progression2 = await appel(
      'GET',
      `/inscriptions-ecole/${inscriptionId}/progression`,
      jetonAdmin,
    );
    verifier(
      'GET /progression admin : 2/2, 100 %',
      progression2.statut === 200 &&
        progression2.json?.terminees === 2 &&
        progression2.json?.pourcentage === 100,
      progression2.texte,
    );
    const inscriptionFinie = await appel(
      'GET',
      `/inscriptions-ecole/${inscriptionId}`,
      jetonAdmin,
    );
    verifier(
      "inscription passée à 'termine' par le serveur",
      inscriptionFinie.statut === 200 && inscriptionFinie.json?.statut === 'termine',
      inscriptionFinie.texte,
    );
    const leconAutreCours = await appel('POST', '/lecons-ecole', jetonAdmin, {
      cours_id: cours2.json?.id,
      ordre: 1,
      titre: 'Psaume 23',
    });
    const terminerHorsCours = await appel(
      'POST',
      `/inscriptions-ecole/${inscriptionId}/terminer`,
      jetonFidele,
      { lecon_id: leconAutreCours.json?.id },
    );
    verifier(
      "POST /terminer leçon d'un autre cours : 400",
      terminerHorsCours.statut === 400,
      terminerHorsCours.texte,
    );

    // --- F. Suppression -------------------------------------------------------
    console.log('F. Suppression :');
    const supprimerCoursBloque = await appel(
      'DELETE',
      `/cours-ecole/${cours1.json?.id}`,
      jetonAdmin,
    );
    verifier(
      'DELETE /cours-ecole avec leçons et inscriptions : 409',
      supprimerCoursBloque.statut === 409,
      supprimerCoursBloque.texte,
    );
    const supprimerInscription = await appel(
      'DELETE',
      `/inscriptions-ecole/${inscriptionAdmin.json?.id}`,
      jetonFidele,
    );
    verifier(
      "DELETE /inscriptions-ecole d'un autre par le fidèle : 403",
      supprimerInscription.statut === 403,
      supprimerInscription.texte,
    );
    const supprimerMienne = await appel(
      'DELETE',
      `/inscriptions-ecole/${inscriptionId}`,
      jetonFidele,
    );
    verifier(
      'DELETE /inscriptions-ecole la sienne : 204',
      supprimerMienne.statut === 204,
      supprimerMienne.texte,
    );
    const supprimerLecon1 = await appel('DELETE', `/lecons-ecole/${lecon1.json?.id}`, jetonAdmin);
    const supprimerLecon2 = await appel('DELETE', `/lecons-ecole/${lecon2.json?.id}`, jetonAdmin);
    verifier(
      'DELETE /lecons-ecole : 200',
      supprimerLecon1.statut === 200 && supprimerLecon2.statut === 200,
      `${supprimerLecon1.texte} ${supprimerLecon2.texte}`,
    );
    const supprimerInscriptionAutre = await appel(
      'DELETE',
      `/inscriptions-ecole/${inscriptionAdmin.json?.id}`,
      jetonAdmin,
    );
    verifier(
      'DELETE /inscriptions-ecole restante par admin : 204',
      supprimerInscriptionAutre.statut === 204,
      supprimerInscriptionAutre.texte,
    );
    const supprimerCours = await appel('DELETE', `/cours-ecole/${cours1.json?.id}`, jetonAdmin);
    verifier(
      'DELETE /cours-ecole sans leçons ni inscriptions : 200',
      supprimerCours.statut === 200,
      supprimerCours.texte,
    );

    // --- G. Isolation entre églises -------------------------------------------
    console.log('G. Isolation :');
    const autre = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église voisine T9', city: 'Yamoussoukro' },
      admin: {
        full_name: 'Admin voisine T9',
        email: 'admin-voisine-t9@example.com',
        password: 'Test1234!',
      },
    });
    verifier('inscription seconde église', autre.statut === 201, autre.texte);
    const jetonVoisin = autre.json?.token;
    const coursVoisin = await appel('GET', '/cours-ecole', jetonVoisin);
    verifier(
      'GET /cours-ecole autre église : 0 cours',
      coursVoisin.statut === 200 && coursVoisin.json?.total === 0,
      coursVoisin.texte,
    );
    const coursVoisinUn = await appel('GET', `/cours-ecole/${cours2.json?.id}`, jetonVoisin);
    verifier(
      'GET /cours-ecole/:id autre église : 404',
      coursVoisinUn.statut === 404,
      coursVoisinUn.texte,
    );

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
