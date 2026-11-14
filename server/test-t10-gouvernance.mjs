// Test d'intégration de la gouvernance (tranche T10) : mandats et
// nominations, réunions du conseil, décisions, procès-verbaux,
// documents (modèles et courriers, recherche), bénéficiaires et aides,
// patrimoine (biens et maintenance reliée aux dépenses), signataires
// configurables, certificat de membre en PDF, droits 401/403 et
// isolation entre églises.
// Même forme que server/test-plan-comptable.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-t10-gouvernance.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4107).
// Base locale : PostgreSQL est nécessaire.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';

const PORT = Number(process.env.PORT ?? 4107);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_t10';
// Secret de test seulement, jamais utilisé en production.
const JWT_SECRET = 'test-secret-t10-gouvernance-32-caracteres';

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

async function main() {
  // Base fraîche.
  const admin = new Client({
    connectionString: 'postgres://postgres:postgres@127.0.0.1:5432/postgres',
  });
  await admin.connect();
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_t10');
  await admin.query('CREATE DATABASE e_system_church_test_t10');
  await admin.end();

  // Schéma + migrations avec le vrai moteur.
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const exec = promisify(execFile);
  await exec('node', ['dist/migrate.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, JWT_SECRET },
  });

  // Démarrage de l'API.
  const api = spawn('node', ['dist/index.js'], {
    cwd: 'server',
    env: { ...process.env, DATABASE_URL, PORT: String(PORT), JWT_SECRET },
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

    // --- Préparation : église mère + membre ---
    const mere = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère EXEMPLE', city: 'Abidjan', phone: '+2250102030405' },
      admin: {
        full_name: 'Admin EXEMPLE',
        email: 'admin-exemple-t10@example.com',
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
      email: 'fidele-exemple-t10@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle par code', fidele.statut === 201, fidele.texte);
    const jetonFidele = fidele.json?.token;

    const membre = await appel('POST', '/membres', jetonMere, {
      full_name: 'Jean T10',
      phone: '+22507000010',
    });
    verifier('membre créé', membre.statut === 201, membre.texte);
    const membreId = membre.json?.id;

    // --- Droits : sans jeton 401, fidèle 403 en écriture ---
    const sansJeton = await appel('GET', '/mandats', null);
    verifier('GET /mandats sans jeton = 401', sansJeton.statut === 401);
    const refuseFidele = await appel('POST', '/mandats', jetonFidele, {
      member_id: membreId,
      fonction: 'Diacre',
      date_debut: '2026-01-01',
    });
    verifier('POST /mandats par fidèle = 403', refuseFidele.statut === 403, refuseFidele.texte);

    // --- Réunions du conseil ---
    const reunion = await appel('POST', '/reunions-conseil', jetonMere, {
      titre: 'Conseil de janvier',
      date_reunion: '2026-01-15T18:00:00Z',
      lieu: 'Salle principale',
      ordre_du_jour: 'Budget, nominations.',
    });
    verifier(
      'réunion créée',
      reunion.statut === 201 && reunion.json?.statut === 'prevue',
      reunion.texte,
    );
    const reunionId = reunion.json?.id;
    const reunions = await appel('GET', '/reunions-conseil', jetonMere);
    verifier(
      'liste des réunions',
      reunions.statut === 200 && reunions.json?.total === 1,
      reunions.texte,
    );

    // --- Décisions ---
    const decision = await appel('POST', '/decisions', jetonMere, {
      reunion_id: reunionId,
      titre: 'Nomination du trésorier',
      description: 'Le conseil nomme un trésorier.',
      date_decision: '2026-01-15',
    });
    verifier(
      'décision liée à la réunion',
      decision.statut === 201 && decision.json?.statut === 'adoptee',
      decision.texte,
    );
    const decisionId = decision.json?.id;
    const mauvaiseReunion = await appel('POST', '/decisions', jetonMere, {
      reunion_id: '00000000-0000-0000-0000-000000000000',
      titre: 'Décision orpheline',
    });
    verifier('décision sans réunion = 400', mauvaiseReunion.statut === 400, mauvaiseReunion.texte);

    // --- Mandats et nominations ---
    const mandat = await appel('POST', '/mandats', jetonMere, {
      member_id: membreId,
      fonction: 'Trésorier',
      date_debut: '2026-01-15',
      date_fin: '2027-01-14',
      decision_id: decisionId,
    });
    verifier(
      'mandat créé, lié à la décision',
      mandat.statut === 201 && mandat.json?.decision_id === decisionId,
      mandat.texte,
    );
    const mandatId = mandat.json?.id;
    const mauvaisMembre = await appel('POST', '/mandats', jetonMere, {
      member_id: '00000000-0000-0000-0000-000000000000',
      fonction: 'Diacre',
      date_debut: '2026-01-01',
    });
    verifier('mandat sans membre = 400', mauvaisMembre.statut === 400, mauvaisMembre.texte);
    const datesInversees = await appel('POST', '/mandats', jetonMere, {
      member_id: membreId,
      fonction: 'Diacre',
      date_debut: '2026-06-01',
      date_fin: '2026-01-01',
    });
    verifier('mandat fin avant début = 400', datesInversees.statut === 400, datesInversees.texte);
    const mandatsEnCours = await appel('GET', '/mandats?statut=en_cours', jetonMere);
    verifier(
      'mandats en cours filtrés',
      mandatsEnCours.statut === 200 && mandatsEnCours.json?.total === 1,
      mandatsEnCours.texte,
    );
    const mandatTermine = await appel('PATCH', `/mandats/${mandatId}`, jetonMere, {
      statut: 'termine',
    });
    verifier(
      'mandat terminé',
      mandatTermine.statut === 200 && mandatTermine.json?.statut === 'termine',
      mandatTermine.texte,
    );

    // --- Procès-verbaux ---
    const pv = await appel('POST', '/proces-verbaux', jetonMere, {
      reunion_id: reunionId,
      numero: 'PV-2026-001',
      contenu: 'Le conseil a adopté la nomination.',
      date_pv: '2026-01-15',
    });
    verifier(
      'procès-verbal créé, brouillon',
      pv.statut === 201 && pv.json?.statut === 'brouillon',
      pv.texte,
    );
    const pvSigne = await appel('PATCH', `/proces-verbaux/${pv.json?.id}`, jetonMere, {
      statut: 'signe',
      signataire: 'Président du conseil',
    });
    verifier(
      'procès-verbal signé',
      pvSigne.statut === 200 && pvSigne.json?.signataire === 'Président du conseil',
      pvSigne.texte,
    );

    // --- Documents : modèles, courriers, recherche ---
    const modele = await appel('POST', '/documents', jetonMere, {
      titre: 'Modèle de lettre officielle',
      categorie: 'modele',
      description: 'En-tête et formule de politesse.',
    });
    verifier('modèle de document créé', modele.statut === 201, modele.texte);
    const courrier = await appel('POST', '/documents', jetonMere, {
      titre: 'Courrier de la mairie',
      categorie: 'courrier',
      sens: 'entrant',
      reference: 'M-2026-014',
      date_document: '2026-01-10',
    });
    verifier('courrier entrant créé', courrier.statut === 201, courrier.texte);
    const recherche = await appel('GET', '/documents?q=mairie', jetonMere);
    verifier(
      'recherche de document',
      recherche.statut === 200 &&
        recherche.json?.total === 1 &&
        recherche.json?.items?.[0]?.titre === 'Courrier de la mairie',
      recherche.texte,
    );
    const modeles = await appel('GET', '/documents?categorie=modele', jetonMere);
    verifier(
      'filtre modèles',
      modeles.statut === 200 && modeles.json?.total === 1,
      modeles.texte,
    );

    // --- Bénéficiaires et aides ---
    const beneficiaire = await appel('POST', '/beneficiaires', jetonMere, {
      nom: 'Famille EXEMPLE',
      telephone: '+22507000011',
      besoin: 'Vivres pour le mois.',
    });
    verifier('bénéficiaire créé', beneficiaire.statut === 201, beneficiaire.texte);
    const beneficiaireId = beneficiaire.json?.id;
    const aide = await appel('POST', '/aides', jetonMere, {
      beneficiaire_id: beneficiaireId,
      type_aide: 'vivres',
      montant_fcfa: 25000,
      description: 'Sac de riz et huile.',
    });
    verifier(
      'aide créée, prévue',
      aide.statut === 201 && aide.json?.statut === 'prevue',
      aide.texte,
    );
    const aideVersee = await appel('PATCH', `/aides/${aide.json?.id}`, jetonMere, {
      statut: 'versee',
    });
    verifier(
      'aide versée',
      aideVersee.statut === 200 && aideVersee.json?.statut === 'versee',
      aideVersee.texte,
    );
    const mauvaiseAide = await appel('POST', '/aides', jetonMere, {
      beneficiaire_id: '00000000-0000-0000-0000-000000000000',
      type_aide: 'vivres',
    });
    verifier('aide sans bénéficiaire = 400', mauvaiseAide.statut === 400, mauvaiseAide.texte);

    // --- Patrimoine ---
    const bien = await appel('POST', '/biens-patrimoine', jetonMere, {
      nom: 'Temple principal',
      categorie: 'batiment',
      valeur_fcfa: 25000000,
      assurance: 'Assureur EXEMPLE, contrat 2026-001.',
      code_inventaire: 'INV-001',
    });
    verifier('bien du patrimoine créé', bien.statut === 201, bien.texte);
    const bienId = bien.json?.id;
    const doublonInventaire = await appel('POST', '/biens-patrimoine', jetonMere, {
      nom: 'Annexe',
      categorie: 'batiment',
      code_inventaire: 'INV-001',
    });
    verifier('code inventaire en double = 409', doublonInventaire.statut === 409, doublonInventaire.texte);
    const depense = await appel('POST', '/depenses', jetonMere, {
      montant_fcfa: 150000,
      motif: 'Réparation de la toiture',
    });
    verifier('dépense créée', depense.statut === 201, depense.texte);
    const maintenance = await appel('POST', '/maintenance-patrimoine', jetonMere, {
      bien_id: bienId,
      description: 'Réparation de la toiture.',
      cout_fcfa: 150000,
      realise_par: 'Artisan EXEMPLE',
      depense_id: depense.json?.id,
    });
    verifier(
      'maintenance reliée à la dépense',
      maintenance.statut === 201 && maintenance.json?.depense_id === depense.json?.id,
      maintenance.texte,
    );
    const mauvaiseMaintenance = await appel('POST', '/maintenance-patrimoine', jetonMere, {
      bien_id: bienId,
      description: 'Travaux sans dépense.',
      depense_id: '00000000-0000-0000-0000-000000000000',
    });
    verifier('maintenance sans dépense = 400', mauvaiseMaintenance.statut === 400, mauvaiseMaintenance.texte);

    // --- Signataires configurables ---
    const parametres = await appel('PATCH', '/parametres', jetonMere, {
      signataire_nominations: 'Président du conseil',
      signataire_proces_verbaux: 'Secrétaire du conseil',
    });
    verifier(
      'signataires enregistrés',
      parametres.statut === 200 &&
        parametres.json?.signataire_nominations === 'Président du conseil' &&
        parametres.json?.signataire_proces_verbaux === 'Secrétaire du conseil',
      parametres.texte,
    );
    const parametresLus = await appel('GET', '/parametres', jetonMere);
    verifier(
      'signataires relus',
      parametresLus.statut === 200 &&
        parametresLus.json?.signataire_nominations === 'Président du conseil',
      parametresLus.texte,
    );

    // --- Certificat de membre en PDF ---
    const certificat = await appel('POST', '/attestations/emette', jetonMere, {
      type: 'membre',
      member_id: membreId,
      date_evenement: '2024-03-02',
      lieu: 'Abidjan',
    });
    verifier(
      'certificat de membre émis, numéro MEM',
      certificat.statut === 201 &&
        typeof certificat.json?.numero === 'string' &&
        certificat.json.numero.startsWith('MEM-'),
      certificat.texte,
    );
    const certificatPdf = await appel(
      'GET',
      `/attestations/${certificat.json?.id}/pdf`,
      jetonMere,
    );
    verifier(
      'certificat de membre PDF = 200',
      certificatPdf.statut === 200 &&
        (certificatPdf.entetes.get('content-type') ?? '').includes('application/pdf'),
      certificatPdf.texte.slice(0, 120),
    );
    const certificatDoublon = await appel('POST', '/attestations/emette', jetonMere, {
      type: 'membre',
      member_id: membreId,
      date_evenement: '2024-03-02',
    });
    verifier('certificat de membre en double = 409', certificatDoublon.statut === 409, certificatDoublon.texte);

    // --- Isolation entre églises ---
    const autre = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Autre église EXEMPLE', city: 'Abidjan', phone: '+2250102030406' },
      admin: {
        full_name: 'Autre Admin EXEMPLE',
        email: 'admin-exemple-t10-autre@example.com',
        phone: '+2250102030406',
        password: 'MotDePasse123!',
      },
      channel: 'web',
    });
    const jetonAutre = autre.json?.token;
    const mandatsAutre = await appel('GET', '/mandats', jetonAutre);
    verifier(
      'autre église ne voit pas les mandats',
      mandatsAutre.statut === 200 && mandatsAutre.json?.total === 0,
      mandatsAutre.texte,
    );
    const mandatAutre = await appel('GET', `/mandats/${mandatId}`, jetonAutre);
    verifier('mandat d’une autre église = 404', mandatAutre.statut === 404, mandatAutre.texte);
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
