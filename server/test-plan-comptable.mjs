// Test d'intégration du plan comptable des dépenses (tranche dépenses
// prévisibles) : catégories, huit postes pré-créés à l'inscription,
// rattachement et marqueur récurrente, budgets mensuels, dépenses
// complètes avec référence auto DEP-AAAA-NNNN, suivi mensuel avec
// dépassement, rapport JSON et PDF, droits 401/403.
// Même forme que server/test-rapports-annexe-p5.mjs : base fraîche,
// application du schéma puis des migrations avec le vrai moteur de
// migration, démarrage de l'API, appels HTTP.
//
// Usage : `node server/test-plan-comptable.mjs`
// Variables : DATABASE_URL (ou PG*), PORT (défaut 4106).
// Base locale : PostgreSQL est nécessaire. Sans base locale, ce test
// ne peut pas tourner (constaté le 12 novembre 2026 : aucun PostgreSQL
// dans cette machine). La migration 031 sera appliquée sur Render
// après la fusion, comme les migrations 015, 016, 018, 019, 020 et 021.

import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';

const PORT = Number(process.env.PORT ?? 4106);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ??
  'postgres://postgres:postgres@127.0.0.1:5432/e_system_church_test_plan';

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
  await admin.query('DROP DATABASE IF EXISTS e_system_church_test_plan');
  await admin.query('CREATE DATABASE e_system_church_test_plan');
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

    // --- Préparation : église mère ---
    const mere = await appel('POST', '/auth/register', null, {
      nom_eglise: 'Église mère EXEMPLE',
      nom_complet: 'Admin EXEMPLE',
      email: 'admin-exemple-plan@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250102030405',
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonMere = mere.json?.token;

    const fidele = await appel('POST', '/auth/inscription-par-code', null, {
      code: mere.json?.church?.code_fidele ?? mere.json?.church?.code,
      nom_complet: 'Fidèle EXEMPLE',
      email: 'fidele-exemple-plan@example.com',
      mot_de_passe: 'MotDePasse123!',
      telephone: '+2250708080909',
    });
    verifier('inscription fidèle par code', fidele.statut === 201, fidele.texte);
    const jetonFidele = fidele.json?.token;

    // --- Catégories ---
    const sansJeton = await appel('GET', '/categories-depenses', null);
    verifier('GET /categories-depenses sans jeton = 401', sansJeton.statut === 401);

    const categories = await appel('GET', '/categories-depenses', jetonMere);
    verifier(
      'dix catégories, codes 01 à 10',
      categories.statut === 200 &&
        Array.isArray(categories.json) &&
        categories.json.length === 10 &&
        categories.json[0]?.code === '01' &&
        categories.json[9]?.code === '10',
      categories.texte,
    );
    const cat02 = categories.json?.find((c) => c.code === '02');
    const cat03 = categories.json?.find((c) => c.code === '03');
    const cat07 = categories.json?.find((c) => c.code === '07');
    const cat08 = categories.json?.find((c) => c.code === '08');

    // --- Huit postes pré-créés à l'inscription ---
    const postes = await appel(
      'GET',
      '/postes-budgetaires?categorie=depense',
      jetonMere,
    );
    const noms = (postes.json ?? []).map((p) => p.nom);
    verifier(
      'huit postes prévisibles créés à l’inscription',
      postes.statut === 200 &&
        ['Électricité', 'Eau', 'Transports', 'Cas sociaux', 'Location de sono',
          "Achat d'équipement", 'Maintenance', "Location d'équipement"]
          .every((n) => noms.includes(n)),
      postes.texte,
    );
    const electricite = (postes.json ?? []).find((p) => p.nom === 'Électricité');
    verifier(
      'Électricité en 02, récurrente',
      electricite?.categorie_id === cat02?.id && electricite?.est_recurrente === true,
      JSON.stringify(electricite),
    );
    const casSociaux = (postes.json ?? []).find((p) => p.nom === 'Cas sociaux');
    verifier(
      'Cas sociaux en 08, ponctuel',
      casSociaux?.categorie_id === cat08?.id && casSociaux?.est_recurrente === false,
      JSON.stringify(casSociaux),
    );
    const transports = (postes.json ?? []).find((p) => p.nom === 'Transports');
    verifier(
      'Transports en 07, récurrent',
      transports?.categorie_id === cat07?.id && transports?.est_recurrente === true,
      JSON.stringify(transports),
    );

    // --- Création et modification d'un poste ---
    const posteCree = await appel('POST', '/plan-comptable/postes', jetonMere, {
      nom: 'Papeterie EXEMPLE',
      categorie: 'depense',
      categorie_id: categories.json?.find((c) => c.code === '01')?.id,
      est_recurrente: true,
    });
    verifier(
      'poste créé avec catégorie 01 et récurrente',
      posteCree.statut === 201 &&
        posteCree.json?.categorie_id ===
          categories.json?.find((c) => c.code === '01')?.id &&
        posteCree.json?.est_recurrente === true,
      posteCree.texte,
    );

    const doublon = await appel('POST', '/plan-comptable/postes', jetonMere, {
      nom: 'Papeterie EXEMPLE',
      categorie: 'depense',
    });
    verifier('poste en double = 409', doublon.statut === 409, doublon.texte);

    const mauvaiseCategorie = await appel(
      'POST',
      '/plan-comptable/postes',
      jetonMere,
      { nom: 'Autre EXEMPLE', categorie: 'recette', categorie_id: cat02?.id },
    );
    verifier(
      'catégorie sur une recette = 400',
      mauvaiseCategorie.statut === 400,
      mauvaiseCategorie.texte,
    );

    const modifie = await appel(
      'PATCH',
      `/plan-comptable/postes/${posteCree.json?.id}`,
      jetonMere,
      { categorie_id: cat03?.id, est_recurrente: false },
    );
    verifier(
      'poste modifié : catégorie 03, ponctuel',
      modifie.statut === 200 &&
        modifie.json?.categorie_id === cat03?.id &&
        modifie.json?.est_recurrente === false,
      modifie.texte,
    );

    const refuseFidele = await appel(
      'POST',
      '/plan-comptable/postes',
      jetonFidele,
      { nom: 'Interdit EXEMPLE', categorie: 'depense' },
    );
    verifier(
      'un fidèle ne crée pas de poste = 403',
      refuseFidele.statut === 403,
      refuseFidele.texte,
    );

    // --- Budgets mensuels ---
    const budget = await appel('POST', '/budgets-mensuels', jetonMere, {
      poste_id: electricite?.id,
      annee: 2026,
      mois: 11,
      montant_prevu: 10000,
    });
    verifier(
      'budget mensuel créé',
      budget.statut === 201 && budget.json?.montant_prevu === 10000,
      budget.texte,
    );
    const budgetRemplace = await appel('POST', '/budgets-mensuels', jetonMere, {
      poste_id: electricite?.id,
      annee: 2026,
      mois: 11,
      montant_prevu: 12000,
    });
    verifier(
      'budget mensuel remplacé (même id, montant mis à jour)',
      budgetRemplace.statut === 201 &&
        budgetRemplace.json?.id === budget.json?.id &&
        budgetRemplace.json?.montant_prevu === 12000,
      budgetRemplace.texte,
    );

    // --- Dépenses complètes, référence auto ---
    const depense1 = await appel(
      'POST',
      '/plan-comptable/depenses',
      jetonMere,
      {
        poste_id: electricite?.id,
        montant_fcfa: 15000,
        motif: 'Facture électricité EXEMPLE',
        date_depense: '2026-11-12',
        mode_paiement: 'virement',
        fournisseur_beneficiaire: 'CIE EXEMPLE',
        responsable_depense: 'Trésorier EXEMPLE',
        responsable_autorisation: 'Pasteur EXEMPLE',
        devise: 'FCFA',
      },
    );
    verifier(
      'dépense créée, référence DEP-2026-0001',
      depense1.statut === 201 &&
        depense1.json?.reference === 'DEP-2026-0001' &&
        depense1.json?.statut === 'soumise' &&
        depense1.json?.mode_paiement === 'virement',
      depense1.texte,
    );
    const depense2 = await appel(
      'POST',
      '/plan-comptable/depenses',
      jetonMere,
      {
        poste_id: electricite?.id,
        montant_fcfa: 5000,
        motif: 'Seconde dépense EXEMPLE',
        date_depense: '2026-11-13',
      },
    );
    verifier(
      'deuxième dépense, référence DEP-2026-0002',
      depense2.statut === 201 && depense2.json?.reference === 'DEP-2026-0002',
      depense2.texte,
    );
    const mauvaisMode = await appel(
      'POST',
      '/plan-comptable/depenses',
      jetonMere,
      {
        poste_id: electricite?.id,
        montant_fcfa: 1000,
        motif: 'Mode invalide EXEMPLE',
        mode_paiement: 'bitcoin',
      },
    );
    verifier(
      'mode de paiement invalide = 400',
      mauvaisMode.statut === 400,
      mauvaisMode.texte,
    );

    // --- Suivi mensuel : dépassement ---
    const suivi = await appel(
      'GET',
      '/plan-comptable/suivi-mensuel?annee=2026&mois=11',
      jetonMere,
    );
    const ligneElec = (suivi.json?.par_postes ?? []).find(
      (l) => l.poste === 'Électricité',
    );
    verifier(
      'suivi Électricité : prévu 12000, réel 20000, dépassement',
      suivi.statut === 200 &&
        ligneElec?.prevu_fcfa === 12000 &&
        ligneElec?.reel_fcfa === 20000 &&
        ligneElec?.budget_defini === true,
      suivi.texte,
    );
    const catInfra = (suivi.json?.par_categories ?? []).find(
      (l) => l.categorie_code === '02',
    );
    verifier(
      'suivi catégorie 02 : réel 20000',
      catInfra?.reel_fcfa === 20000,
      suivi.texte,
    );

    // --- Rapport mensuel JSON et PDF ---
    const rapport = await appel(
      'GET',
      '/plan-comptable/rapport?annee=2026&mois=11',
      jetonMere,
    );
    verifier(
      'rapport mensuel : totaux cohérents, 2 dépenses listées',
      rapport.statut === 200 &&
        rapport.json?.total_prevu_fcfa === 12000 &&
        rapport.json?.total_reel_fcfa === 20000 &&
        rapport.json?.depenses?.length === 2,
      rapport.texte,
    );
    const rapportPdf = await appel(
      'GET',
      '/plan-comptable/rapport/pdf?annee=2026&mois=11',
      jetonMere,
    );
    verifier(
      'rapport mensuel PDF = 200, contenu PDF',
      rapportPdf.statut === 200 &&
        (rapportPdf.entetes.get('content-type') ?? '').includes('application/pdf'),
      rapportPdf.texte.slice(0, 120),
    );
    const rapportAnnuel = await appel(
      'GET',
      '/plan-comptable/rapport?annee=2026',
      jetonMere,
    );
    verifier(
      'rapport annuel : mêmes totaux',
      rapportAnnuel.statut === 200 &&
        rapportAnnuel.json?.total_reel_fcfa === 20000,
      rapportAnnuel.texte,
    );
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
