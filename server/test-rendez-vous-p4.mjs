// Test d'intégration du rendez-vous membre (tranche P4) : demande de
// rendez-vous auprès du pasteur, avec la migration 022.
// Même forme que server/test-espace-fidele-p1.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP, droits 401/403 et
// isolation entre églises.
//
// Usage : `node server/test-rendez-vous-p4.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4102),
// JWT_SECRET (défaut : valeur de test locale, 64 caractères hex,
// sans valeur de production ; l'API l'exige, 32 caractères minimum).
// Base locale : PostgreSQL est nécessaire. Sans base locale, ce test
// ne peut pas tourner (constaté le 12 novembre 2026 : aucun PostgreSQL
// dans cette machine). La migration 022 sera appliquée sur Render
// après la fusion, comme les migrations 015, 016, 018, 019 et 020.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';

// Secret de test seulement : l'API refuse de démarrer sans
// JWT_SECRET (32 caractères minimum) ; sans variable d'environnement,
// on utilise cette valeur locale, jamais en production.
process.env.JWT_SECRET ??=
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const PORT = Number(process.env.PORT ?? 4102);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_p4';

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
  // Base fraîche.
  const admin = new Client({
    connectionString: 'postgres://postgres:postgres@127.0.0.1:5432/postgres',
  });
  await admin.connect();
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_p4');
  await admin.query('CREATE DATABASE e_system_church_test_p4');
  await admin.end();

  // Schéma + migrations avec le vrai moteur.
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const exec = promisify(execFile);
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL },
  });

  // Démarrage de l'API.
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, PORT: String(PORT) },
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

    // --- Préparation : église mère, compte, membre ---
    // Amorçage aligné sur le format d'inscription actuel (base
    // 029b5968) : /auth/register attend { eglise, admin } et
    // /auth/inscription-par-code { nom_prenom, code_eglise, ... } ;
    // l'ancien format plat du test ne passait plus la validation.
    const mere = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-p4@example.com',
        password: 'MotDePasse123!',
        phone: '+2250102030405',
      },
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);

    const fidele = await appel('POST', '/auth/inscription-par-code', null, {
      code_eglise: mere.json?.church?.code_fidele ?? mere.json?.church?.code,
      nom_prenom: 'Fidèle EXEMPLE',
      email: 'fidele-exemple-p4@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle par code', fidele.statut === 201, fidele.texte);
    const jetonFidele = fidele.json?.token;

    // --- Demandes de rendez-vous ---
    const sansJeton = await appel('GET', '/moi/rendez-vous', null);
    verifier('GET /moi/rendez-vous sans jeton = 401', sansJeton.statut === 401);

    const listeVide = await appel('GET', '/moi/rendez-vous', jetonFidele);
    verifier(
      'liste vide au départ',
      listeVide.statut === 200 &&
        Array.isArray(listeVide.json?.rendez_vous) &&
        listeVide.json.rendez_vous.length === 0,
      listeVide.texte,
    );

    const demain = new Date(Date.now() + 86400000)
      .toISOString()
      .substring(0, 10);
    const demande = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: demain,
      motif: 'Motif EXEMPLE de rendez-vous.',
    });
    verifier(
      'POST /moi/rendez-vous = 201, statut en_attente',
      demande.statut === 201 &&
        demande.json?.rendez_vous?.statut === 'en_attente' &&
        demande.json?.rendez_vous?.date_souhaitee?.substring(0, 10) === demain,
      demande.texte,
    );

    const listeApres = await appel('GET', '/moi/rendez-vous', jetonFidele);
    verifier(
      'liste après demande : 1 rendez-vous',
      listeApres.statut === 200 &&
        listeApres.json?.rendez_vous?.length === 1,
      listeApres.texte,
    );

    const sansMotif = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: demain,
      motif: '   ',
    });
    verifier('motif vide rejeté (400)', sansMotif.statut === 400, sansMotif.texte);

    const sansDate = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      motif: 'Motif EXEMPLE.',
    });
    verifier('date manquante rejetée (400)', sansDate.statut === 400, sansDate.texte);

    const hier = new Date(Date.now() - 86400000)
      .toISOString()
      .substring(0, 10);
    const datePassee = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: hier,
      motif: 'Motif EXEMPLE.',
    });
    verifier('date passée rejetée (400)', datePassee.statut === 400, datePassee.texte);

    // --- Créneaux du pasteur (migration 033, E-RV1) ---
    const jetonAdmin = mere.json?.token;
    const sansJetonCreneaux = await appel(
      'GET',
      '/rendez-vous/creneaux',
      null,
    );
    verifier(
      'GET /rendez-vous/creneaux sans jeton = 401',
      sansJetonCreneaux.statut === 401,
    );

    const listeCreneauxVide = await appel(
      'GET',
      '/rendez-vous/creneaux',
      jetonAdmin,
    );
    verifier(
      'aucun créneau au départ (admin)',
      listeCreneauxVide.statut === 200 &&
        Array.isArray(listeCreneauxVide.json?.creneaux) &&
        listeCreneauxVide.json.creneaux.length === 0,
      listeCreneauxVide.texte,
    );

    const listeCreneauxFideleVide = await appel(
      'GET',
      '/moi/rendez-vous/creneaux',
      jetonFidele,
    );
    verifier(
      'aucun créneau au départ (fidèle)',
      listeCreneauxFideleVide.statut === 200 &&
        listeCreneauxFideleVide.json?.creneaux?.length === 0,
      listeCreneauxFideleVide.texte,
    );

    const creationParFidele = await appel(
      'POST',
      '/rendez-vous/creneaux',
      jetonFidele,
      { periode: 'matin', libelle: 'Créneau EXEMPLE' },
    );
    verifier(
      'création par un fidèle refusée (403)',
      creationParFidele.statut === 403,
      creationParFidele.texte,
    );

    const creneauMatin = await appel('POST', '/rendez-vous/creneaux', jetonAdmin, {
      periode: 'matin',
      libelle: '8 h 00 - 10 h 00',
    });
    verifier(
      'POST créneau matin = 201',
      creneauMatin.statut === 201 &&
        creneauMatin.json?.creneau?.periode === 'matin' &&
        creneauMatin.json?.creneau?.libelle === '8 h 00 - 10 h 00' &&
        creneauMatin.json?.creneau?.actif === true,
      creneauMatin.texte,
    );
    const idMatin = creneauMatin.json?.creneau?.id;

    const periodeInvalide = await appel(
      'POST',
      '/rendez-vous/creneaux',
      jetonAdmin,
      { periode: 'nuit', libelle: 'Créneau EXEMPLE' },
    );
    verifier(
      'période invalide rejetée (400)',
      periodeInvalide.statut === 400,
      periodeInvalide.texte,
    );

    const libelleVide = await appel('POST', '/rendez-vous/creneaux', jetonAdmin, {
      periode: 'matin',
      libelle: '   ',
    });
    verifier(
      'libellé vide rejeté (400)',
      libelleVide.statut === 400,
      libelleVide.texte,
    );

    const creneauSoir = await appel('POST', '/rendez-vous/creneaux', jetonAdmin, {
      periode: 'soir',
      libelle: '18 h 00 - 20 h 00',
    });
    verifier('POST créneau soir = 201', creneauSoir.statut === 201, creneauSoir.texte);
    const idSoir = creneauSoir.json?.creneau?.id;

    const listeCreneaux = await appel(
      'GET',
      '/rendez-vous/creneaux',
      jetonAdmin,
    );
    verifier(
      'liste admin : 2 créneaux, matin avant soir',
      listeCreneaux.statut === 200 &&
        listeCreneaux.json?.creneaux?.length === 2 &&
        listeCreneaux.json.creneaux[0]?.periode === 'matin' &&
        listeCreneaux.json.creneaux[1]?.periode === 'soir',
      listeCreneaux.texte,
    );

    const listeCreneauxFidele = await appel(
      'GET',
      '/moi/rendez-vous/creneaux',
      jetonFidele,
    );
    verifier(
      'liste fidèle : 2 créneaux actifs',
      listeCreneauxFidele.statut === 200 &&
        listeCreneauxFidele.json?.creneaux?.length === 2,
      listeCreneauxFidele.texte,
    );

    const desactive = await appel(
      'PATCH',
      `/rendez-vous/creneaux/${idSoir}`,
      jetonAdmin,
      { actif: false },
    );
    verifier(
      'PATCH désactivation du créneau soir',
      desactive.statut === 200 && desactive.json?.creneau?.actif === false,
      desactive.texte,
    );

    const listeFideleApres = await appel(
      'GET',
      '/moi/rendez-vous/creneaux',
      jetonFidele,
    );
    verifier(
      'fidèle : 1 seul créneau actif après désactivation',
      listeFideleApres.statut === 200 &&
        listeFideleApres.json?.creneaux?.length === 1 &&
        listeFideleApres.json.creneaux[0]?.periode === 'matin',
      listeFideleApres.texte,
    );

    const modifie = await appel(
      'PATCH',
      `/rendez-vous/creneaux/${idMatin}`,
      jetonAdmin,
      { libelle: '8 h 30 - 10 h 30' },
    );
    verifier(
      'PATCH libellé du créneau matin',
      modifie.statut === 200 &&
        modifie.json?.creneau?.libelle === '8 h 30 - 10 h 30',
      modifie.texte,
    );

    const sansChamp = await appel(
      'PATCH',
      `/rendez-vous/creneaux/${idMatin}`,
      jetonAdmin,
      {},
    );
    verifier('PATCH sans champ rejeté (400)', sansChamp.statut === 400, sansChamp.texte);

    const inexistant = await appel(
      'PATCH',
      '/rendez-vous/creneaux/00000000-0000-0000-0000-000000000000',
      jetonAdmin,
      { libelle: 'Créneau EXEMPLE' },
    );
    verifier(
      'PATCH créneau inexistant = 404',
      inexistant.statut === 404,
      inexistant.texte,
    );

    // Le fidèle demande avec le libellé choisi.
    const demandeAvecCreneau = await appel(
      'POST',
      '/moi/rendez-vous',
      jetonFidele,
      {
        date_souhaitee: demain,
        creneau: '8 h 30 - 10 h 30',
        motif: 'Motif EXEMPLE avec créneau.',
      },
    );
    verifier(
      'demande avec créneau = 201, créneau repris',
      demandeAvecCreneau.statut === 201 &&
        demandeAvecCreneau.json?.rendez_vous?.creneau === '8 h 30 - 10 h 30',
      demandeAvecCreneau.texte,
    );

    const supprime = await appel(
      'DELETE',
      `/rendez-vous/creneaux/${idSoir}`,
      jetonAdmin,
    );
    verifier(
      'DELETE créneau soir = 200',
      supprime.statut === 200 && supprime.json?.ok === true,
      supprime.texte,
    );

    const listeApresSuppression = await appel(
      'GET',
      '/rendez-vous/creneaux',
      jetonAdmin,
    );
    verifier(
      'liste admin : 1 créneau après suppression',
      listeApresSuppression.statut === 200 &&
        listeApresSuppression.json?.creneaux?.length === 1,
      listeApresSuppression.texte,
    );

    const supprimeInexistant = await appel(
      'DELETE',
      '/rendez-vous/creneaux/00000000-0000-0000-0000-000000000000',
      jetonAdmin,
    );
    verifier(
      'DELETE créneau inexistant = 404',
      supprimeInexistant.statut === 404,
      supprimeInexistant.texte,
    );

    // Isolation : une autre église ne voit pas les créneaux.
    const autreEglise = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Autre église EXEMPLE', city: 'Abidjan' },
      admin: {
        full_name: 'Autre admin EXEMPLE',
        email: 'autre-admin-exemple-p4@example.com',
        password: 'MotDePasse123!',
        phone: '+2250102030406',
      },
    });
    const jetonAutreAdmin = autreEglise.json?.token;
    const listeAutreEglise = await appel(
      'GET',
      '/rendez-vous/creneaux',
      jetonAutreAdmin,
    );
    verifier(
      'liste vide pour une autre église (isolation)',
      listeAutreEglise.statut === 200 &&
        listeAutreEglise.json?.creneaux?.length === 0,
      listeAutreEglise.texte,
    );
    const modifieAutreEglise = await appel(
      'PATCH',
      `/rendez-vous/creneaux/${idMatin}`,
      jetonAutreAdmin,
      { libelle: 'Créneau EXEMPLE' },
    );
    verifier(
      'PATCH du créneau d’une autre église = 404',
      modifieAutreEglise.statut === 404,
      modifieAutreEglise.texte,
    );

    // Isolation : un fidèle d'une autre église ne voit pas la demande.
    const autre = await appel('POST', '/auth/inscription-par-code', null, {
      code_eglise: mere.json?.church?.code_fidele ?? mere.json?.church?.code,
      nom_prenom: 'Autre fidèle EXEMPLE',
      email: 'autre-fidele-exemple-p4@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250909090909',
    });
    const jetonAutre = autre.json?.token;
    const listeAutre = await appel('GET', '/moi/rendez-vous', jetonAutre);
    verifier(
      'liste vide pour un autre fidèle (isolation)',
      listeAutre.statut === 200 &&
        listeAutre.json?.rendez_vous?.length === 0,
      listeAutre.texte,
    );
  } finally {
    api.kill();
    await once(api, 'exit').catch(() => undefined);
  }

  console.log(echecs === 0 ? 'TOUS LES TESTS PASSENT' : `${echecs} ECHEC(S)`);
  process.exit(echecs === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
