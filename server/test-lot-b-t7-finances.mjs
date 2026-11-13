// Test d'intégration de la tranche T7 (Lot B) — Finances complètes,
// partie serveur (migration 025).
//
// Périmètre : double validation verrouillée des contributions (le
// trésorier saisit, seul le pasteur confirme ; reçu numéroté REC-AAAA-NNNN
// + caisse écrite automatiquement à la confirmation), caisse écrite
// automatiquement à chaque dépense payée, comptes bancaires, rapprochement
// bancaire par canal, clôture de caisse verrouillée, cotisations (montant
// fixé par l'église, suivi payé / reste par membre), budgets par
// département avec alerte de dépassement, justificatif par référence
// (déjà en place, vérifié ici : le champ est stocké et relu).
//
// Base fraîche, application du schéma puis des migrations avec le vrai
// moteur (dist/migrate.js), démarrage de l'API, appels HTTP, droits
// 401/403 et isolation entre églises. Aucun vrai envoi, aucun appel
// Wave / Orange / MTN.
//
// Usage (depuis la racine du dépôt, après `npm run build` dans server/) :
//   `node server/test-lot-b-t7-finances.mjs`
// Variables : PORT (défaut 4109). PostgreSQL local requis
// (utilisateur postgres / postgres).

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);
const JWT_SECRET = 'test-secret-t7-finances-32-caracteres';
const ADMIN = 'postgres://postgres:postgres@127.0.0.1:5432/postgres';
const NOM_DB = 'e_system_church_test_t7';

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

    const maintenant = new Date();
    const annee = maintenant.getFullYear();
    const mois = maintenant.getMonth() + 1;
    const periodeMois = `${annee}-${String(mois).padStart(2, '0')}`;
    const moisPrecedent = new Date(annee, mois - 2, 1);
    const periodePrecedente = `${moisPrecedent.getFullYear()}-${String(moisPrecedent.getMonth() + 1).padStart(2, '0')}`;
    const moisMoins2 = new Date(annee, mois - 3, 1);
    const periodeMoins2 = `${moisMoins2.getFullYear()}-${String(moisMoins2.getMonth() + 1).padStart(2, '0')}`;
    const moisMoins3 = new Date(annee, mois - 4, 1);
    const periodeMoins3 = `${moisMoins3.getFullYear()}-${String(moisMoins3.getMonth() + 1).padStart(2, '0')}`;

    // --- Préparation : église, admin, rôles, membres ----------------------
    const mere = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère T7', city: 'Abidjan' },
      admin: {
        full_name: 'Admin mère T7',
        email: 'admin-mere-t7@example.com',
        password: 'MotDePasse123!',
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
    await creerCompte('tresorier-t7@example.com', 'tresorier');
    await creerCompte('culte-t7@example.com', 'responsable_culte');
    const jetonTresorier = await login('tresorier-t7@example.com');
    const jetonCulte = await login('culte-t7@example.com');

    async function creerMembre(nom, statut = 'actif') {
      const r = await appel('POST', '/membres', jetonAdmin, { full_name: nom, status: statut });
      if (r.statut !== 201) throw new Error(`création membre ${nom}: ${r.texte}`);
      return r.json.id;
    }
    const idA = await creerMembre('Cotisant T7');
    const idB = await creerMembre('Partiel T7');
    const idC = await creerMembre('Inactif T7', 'inactif');
    await creerCompte('fidele-a-t7@example.com', 'membre', idA);
    const jetonFideleA = await login('fidele-a-t7@example.com');

    // --- A. Double validation verrouillée + reçu + caisse -------------------
    console.log('A. Double validation des contributions :');
    const dime = await appel('POST', '/contributions', jetonTresorier, {
      type: 'dime', amount_fcfa: 5000, payment_method: 'wave',
      payment_ref: 'WAVE-T7-1', member_id: idA,
    });
    verifier(
      'trésorier saisit une dîme : 201, en_attente, sans reçu',
      dime.statut === 201 && dime.json?.status === 'en_attente' && !dime.json?.recu_numero,
      dime.texte,
    );
    const idDime = dime.json?.id;
    const confirmeTresorier = await appel('PATCH', `/contributions/${idDime}/statut`, jetonTresorier, { status: 'confirme' });
    verifier(
      'trésorier qui confirme : 403 (seul le pasteur valide)',
      confirmeTresorier.statut === 403,
      confirmeTresorier.texte,
    );
    const confirmeAdmin = await appel('PATCH', `/contributions/${idDime}/statut`, jetonAdmin, { status: 'confirme' });
    verifier(
      'pasteur qui confirme : 200, reçu REC-AAAA-0001',
      confirmeAdmin.statut === 200 &&
        confirmeAdmin.json?.status === 'confirme' &&
        confirmeAdmin.json?.recu_numero === `REC-${annee}-0001`,
      confirmeAdmin.texte,
    );
    const reconfirme = await appel('PATCH', `/contributions/${idDime}/statut`, jetonAdmin, { status: 'confirme' });
    verifier('contribution confirmée : re-confirmation 409', reconfirme.statut === 409, reconfirme.texte);
    const annuleConfirmee = await appel('PATCH', `/contributions/${idDime}/statut`, jetonAdmin, { status: 'annule' });
    verifier('contribution confirmée : annulation 409 (verrouillée)', annuleConfirmee.statut === 409, annuleConfirmee.texte);
    const detailDime = await appel('GET', `/contributions/${idDime}`, jetonAdmin);
    verifier(
      'GET /contributions/:id porte le numéro de reçu',
      detailDime.statut === 200 && detailDime.json?.recu?.recu_numero === `REC-${annee}-0001`,
      detailDime.texte,
    );
    const offrande = await appel('POST', '/contributions', jetonTresorier, {
      type: 'offrande', amount_fcfa: 7000, payment_method: 'orange_money',
      payment_ref: 'OM-T7-1', member_id: idB,
    });
    const idOffrande = offrande.json?.id;
    const confirmeOffrande = await appel('PATCH', `/contributions/${idOffrande}/statut`, jetonAdmin, { status: 'confirme' });
    verifier(
      'deuxième reçu : REC-AAAA-0002 (séquence par église et par année)',
      confirmeOffrande.statut === 200 && confirmeOffrande.json?.recu_numero === `REC-${annee}-0002`,
      confirmeOffrande.texte,
    );
    const donAttente = await appel('POST', '/contributions', jetonTresorier, {
      type: 'don', amount_fcfa: 3000, payment_method: 'especes', member_id: idA,
    });
    const idDonAttente = donAttente.json?.id;
    const donAnnule = await appel('POST', '/contributions', jetonTresorier, {
      type: 'don', amount_fcfa: 4000, payment_method: 'virement', member_id: idB,
    });
    const idDonAnnule = donAnnule.json?.id;
    const annuleTresorier = await appel('PATCH', `/contributions/${idDonAnnule}/statut`, jetonTresorier, { status: 'annule' });
    verifier(
      'trésorier peut annuler une contribution en attente : 200',
      annuleTresorier.statut === 200 && annuleTresorier.json?.status === 'annule',
      annuleTresorier.texte,
    );
    const membrePost = await appel('POST', '/contributions', jetonFideleA, {
      type: 'don', amount_fcfa: 1000, payment_method: 'especes', member_id: idA,
    });
    verifier('membre simple : POST /contributions 403', membrePost.statut === 403, membrePost.texte);

    // Caisse écrite automatiquement à la confirmation (une seule source).
    const caisseAuto = await appel('GET', '/caisse-mouvements?source=contribution', jetonAdmin);
    verifier(
      'caisse : 2 écritures automatiques (dîme + offrande), canal porté',
      caisseAuto.statut === 200 && caisseAuto.json?.total === 2 &&
        caisseAuto.json.items.every((m) => m.source === 'contribution') &&
        caisseAuto.json.items.some((m) => m.canal === 'wave' && m.montant_fcfa === 5000 && m.reference === `REC-${annee}-0001`) &&
        caisseAuto.json.items.some((m) => m.canal === 'orange_money' && m.montant_fcfa === 7000),
      caisseAuto.texte,
    );
    const manuel1 = await appel('POST', '/caisse-mouvements', jetonTresorier, {
      type: 'entree', montant_fcfa: 2000, motif: 'Quête manuelle T7', canal: 'especes',
    });
    verifier(
      'saisie manuelle de caisse toujours possible : 201, source manuelle',
      manuel1.statut === 201 && manuel1.json?.source === 'manuelle' && manuel1.json?.canal === 'especes',
      manuel1.texte,
    );
    const idManuel1 = manuel1.json?.id;
    const manuel2 = await appel('POST', '/caisse-mouvements', jetonTresorier, {
      type: 'entree', montant_fcfa: 1000, motif: 'Sans canal T7',
    });
    verifier(
      'saisie manuelle sans canal : 201, canal null',
      manuel2.statut === 201 && manuel2.json?.canal === null,
      manuel2.texte,
    );

    // Reçu PDF.
    const recuAdmin = await appel('GET', `/contributions/${idDime}/recu.pdf`, jetonAdmin);
    verifier(
      'reçu PDF admin : 200, %PDF, numéro et montant dans le contenu',
      recuAdmin.statut === 200 &&
        recuAdmin.texte.startsWith('%PDF') &&
        recuAdmin.texte.includes(`REC-${annee}-0001`) &&
        recuAdmin.texte.includes('5 000 FCFA'),
      recuAdmin.texte.slice(0, 120),
    );
    const recuFideleA = await appel('GET', `/contributions/${idDime}/recu.pdf`, jetonFideleA);
    verifier('reçu PDF : le membre télécharge son propre reçu', recuFideleA.statut === 200, recuFideleA.texte.slice(0, 120));
    const recuFideleAutre = await appel('GET', `/contributions/${idOffrande}/recu.pdf`, jetonFideleA);
    verifier("reçu PDF : le reçu d'un autre membre 403", recuFideleAutre.statut === 403, recuFideleAutre.texte);
    const recuAttente = await appel('GET', `/contributions/${idDonAttente}/recu.pdf`, jetonAdmin);
    verifier('reçu PDF : contribution en attente 409', recuAttente.statut === 409, recuAttente.texte);
    const recuTresorier = await appel('GET', `/contributions/${idDime}/recu.pdf`, jetonTresorier);
    verifier('reçu PDF : trésorier 200', recuTresorier.statut === 200, recuTresorier.texte.slice(0, 80));

    // --- B. Dépense payée → caisse automatique ------------------------------
    console.log('B. Dépense payée et caisse :');
    const depense = await appel('POST', '/plan-comptable/depenses', jetonAdmin, {
      montant_fcfa: 3000, motif: 'Achat T7', mode_paiement: 'especes',
      justificatif_ref: 'PHOTO-T7-001',
    });
    verifier(
      'dépense créée (plan comptable) : 201, soumise, justificatif porté',
      depense.statut === 201 && depense.json?.statut === 'soumise' &&
        depense.json?.justificatif_ref === 'PHOTO-T7-001' &&
        typeof depense.json?.reference === 'string' && depense.json.reference.startsWith(`DEP-${annee}-`),
      depense.texte,
    );
    const idDepense = depense.json?.id;
    const caisseAvantPaiement = await appel('GET', '/caisse-mouvements?source=depense', jetonAdmin);
    verifier(
      'avant paiement : aucune écriture de caisse pour la dépense',
      caisseAvantPaiement.statut === 200 && caisseAvantPaiement.json?.total === 0,
      caisseAvantPaiement.texte,
    );
    await appel('PATCH', `/depenses/${idDepense}/statut`, jetonTresorier, { statut: 'validee_tresorier' });
    await appel('PATCH', `/depenses/${idDepense}/statut`, jetonAdmin, { statut: 'validee_pasteur' });
    const payee = await appel('PATCH', `/depenses/${idDepense}/statut`, jetonTresorier, { statut: 'payee' });
    verifier('dépense payée : 200', payee.statut === 200 && payee.json?.statut === 'payee', payee.texte);
    const caisseDepense = await appel('GET', '/caisse-mouvements?source=depense', jetonAdmin);
    verifier(
      'caisse : 1 sortie automatique (dépense payée), canal espèces',
      caisseDepense.statut === 200 && caisseDepense.json?.total === 1 &&
        caisseDepense.json.items[0].type === 'sortie' &&
        caisseDepense.json.items[0].montant_fcfa === 3000 &&
        caisseDepense.json.items[0].canal === 'especes' &&
        caisseDepense.json.items[0].source_id === idDepense,
      caisseDepense.texte,
    );
    const solde = await appel('GET', '/finances/caisse', jetonAdmin);
    verifier(
      'solde de caisse : 15 000 entrées − 3 000 sorties = 12 000 (5 mouvements)',
      solde.statut === 200 && solde.json?.entrees === 15000 &&
        solde.json?.sorties === 3000 && solde.json?.solde === 12000 &&
        solde.json?.mouvements === 5,
      solde.texte,
    );

    // --- C. Comptes bancaires -------------------------------------------------
    console.log('C. Comptes bancaires :');
    const compte = await appel('POST', '/comptes-bancaires', jetonTresorier, {
      banque: 'Banque Atlantique', titulaire: 'Église mère T7',
      numero_compte: 'CI123456789', type: 'banque', devise: 'FCFA',
    });
    verifier(
      'compte bancaire créé : 201',
      compte.statut === 201 && compte.json?.banque === 'Banque Atlantique',
      compte.texte,
    );
    const idCompte = compte.json?.id;
    const comptesListe = await appel('GET', '/comptes-bancaires', jetonAdmin);
    verifier(
      'liste des comptes : 1',
      comptesListe.statut === 200 && comptesListe.json?.total === 1,
      comptesListe.texte,
    );
    const compteMembre = await appel('GET', '/comptes-bancaires', jetonFideleA);
    verifier('comptes bancaires : membre 403', compteMembre.statut === 403, compteMembre.texte);
    const comptePatch = await appel('PATCH', `/comptes-bancaires/${idCompte}`, jetonAdmin, { titulaire: 'Église T7' });
    verifier('compte modifié : 200', comptePatch.statut === 200 && comptePatch.json?.titulaire === 'Église T7', comptePatch.texte);
    const compteSuppr = await appel('DELETE', `/comptes-bancaires/${idCompte}`, jetonAdmin);
    verifier('compte supprimé : 200', compteSuppr.statut === 200, compteSuppr.texte);
    const comptesApres = await appel('GET', '/comptes-bancaires', jetonAdmin);
    verifier('liste des comptes après suppression : 0', comptesApres.statut === 200 && comptesApres.json?.total === 0, comptesApres.texte);

    // --- D. Rapprochement par canal -------------------------------------------
    console.log('D. Rapprochement par canal :');
    const rapprochement = await appel('GET', `/finances/rapprochement?annee=${annee}&mois=${mois}`, jetonAdmin);
    const ligneCanal = (nom) => rapprochement.json?.canaux?.find((c) => c.canal === nom);
    verifier(
      'rapprochement : 200, période du mois en cours',
      rapprochement.statut === 200 && rapprochement.json?.periode === periodeMois,
      rapprochement.texte,
    );
    verifier(
      'Wave : attendu 5 000, caisse 5 000, écart 0, sans alerte',
      ligneCanal('wave')?.attendu_fcfa === 5000 &&
        ligneCanal('wave')?.caisse_net_fcfa === 5000 &&
        ligneCanal('wave')?.ecart_fcfa === 0 && ligneCanal('wave')?.alerte === false,
      rapprochement.texte,
    );
    verifier(
      'Orange Money : attendu 7 000, écart 0',
      ligneCanal('orange_money')?.attendu_fcfa === 7000 && ligneCanal('orange_money')?.ecart_fcfa === 0,
      rapprochement.texte,
    );
    verifier(
      'Espèces : attendu −3 000, caisse −1 000 (sortie auto + saisie manuelle), écart −2 000, alerte',
      ligneCanal('especes')?.attendu_fcfa === -3000 &&
        ligneCanal('especes')?.caisse_net_fcfa === -1000 &&
        ligneCanal('especes')?.ecart_fcfa === -2000 && ligneCanal('especes')?.alerte === true,
      rapprochement.texte,
    );
    verifier(
      'Non ventilé : caisse 1 000 (saisie sans canal), écart −1 000, alerte',
      rapprochement.json?.non_ventile?.caisse_net_fcfa === 1000 &&
        rapprochement.json?.non_ventile?.ecart_fcfa === -1000 &&
        rapprochement.json?.non_ventile?.alerte === true,
      rapprochement.texte,
    );
    verifier(
      'Totaux : entrées 12 000, sorties 3 000, attendu 9 000, caisse 12 000, écart −3 000',
      rapprochement.json?.totaux?.entrees_confirmees_fcfa === 12000 &&
        rapprochement.json?.totaux?.sorties_payees_fcfa === 3000 &&
        rapprochement.json?.totaux?.attendu_fcfa === 9000 &&
        rapprochement.json?.totaux?.caisse_net_fcfa === 12000 &&
        rapprochement.json?.totaux?.ecart_fcfa === -3000,
      rapprochement.texte,
    );
    const rapprochementMembre = await appel('GET', `/finances/rapprochement?annee=${annee}&mois=${mois}`, jetonFideleA);
    verifier('rapprochement : membre 403', rapprochementMembre.statut === 403, rapprochementMembre.texte);

    // --- E. Clôture de caisse verrouillée ------------------------------------
    console.log('E. Clôture de caisse :');
    const clotureCourant = await appel('POST', '/finances/caisse/cloturer', jetonTresorier, { periode: periodeMois });
    verifier('clôture du mois en cours : 400', clotureCourant.statut === 400, clotureCourant.texte);
    const clotureFutur = await appel('POST', '/finances/caisse/cloturer', jetonTresorier, { periode: `${annee + 1}-01` });
    verifier('clôture d’un mois futur : 400', clotureFutur.statut === 400, clotureFutur.texte);
    const cloturePrecedente = await appel('POST', '/finances/caisse/cloturer', jetonTresorier, { periode: periodePrecedente });
    verifier(
      'clôture du mois précédent (sans mouvement) : 201, solde 0, écart 0',
      cloturePrecedente.statut === 201 &&
        cloturePrecedente.json?.solde_calcule_fcfa === 0 &&
        cloturePrecedente.json?.solde_compte_fcfa === 0 &&
        cloturePrecedente.json?.ecart_fcfa === 0,
      cloturePrecedente.texte,
    );
    const clotureDouble = await appel('POST', '/finances/caisse/cloturer', jetonTresorier, { periode: periodePrecedente });
    verifier('deuxième clôture du même mois : 409', clotureDouble.statut === 409, clotureDouble.texte);
    // Mouvement antidaté dans le mois −2, puis clôture avec solde compté.
    const manuelCloture = await appel('POST', '/caisse-mouvements', jetonTresorier, {
      type: 'entree', montant_fcfa: 1500, motif: 'Clôture T7', canal: 'especes',
    });
    const idManuelCloture = manuelCloture.json?.id;
    await pool.query(
      `UPDATE caisse_mouvements SET created_at = $1 WHERE id = $2`,
      [`${periodeMoins2}-15T10:00:00Z`, idManuelCloture],
    );
    const clotureMoins2 = await appel('POST', '/finances/caisse/cloturer', jetonTresorier, {
      periode: periodeMoins2, solde_compte_fcfa: 1500, commentaire: 'Compté T7',
    });
    verifier(
      'clôture avec solde compté : 201, calculé 1 500, écart 0',
      clotureMoins2.statut === 201 &&
        clotureMoins2.json?.solde_calcule_fcfa === 1500 &&
        clotureMoins2.json?.ecart_fcfa === 0,
      clotureMoins2.texte,
    );
    const clotureEcart = await appel('POST', '/finances/caisse/cloturer', jetonTresorier, {
      periode: periodeMoins3, solde_compte_fcfa: 500,
    });
    verifier(
      'clôture sans mouvement, solde compté 500 : 201, écart 500',
      clotureEcart.statut === 201 &&
        clotureEcart.json?.solde_calcule_fcfa === 0 &&
        clotureEcart.json?.ecart_fcfa === 500,
      clotureEcart.texte,
    );
    const patchCloture = await appel('PATCH', `/caisse-mouvements/${idManuelCloture}`, jetonTresorier, { motif: 'Modifié T7' });
    verifier('mouvement d’un mois clôturé : PATCH 400', patchCloture.statut === 400, patchCloture.texte);
    const supprCloture = await appel('DELETE', `/caisse-mouvements/${idManuelCloture}`, jetonTresorier);
    verifier('mouvement d’un mois clôturé : DELETE 409', supprCloture.statut === 409, supprCloture.texte);
    const patchCourant = await appel('PATCH', `/caisse-mouvements/${idManuel1}`, jetonTresorier, { motif: 'Quête manuelle T7 modifiée' });
    verifier('mouvement du mois en cours : PATCH 200 (non verrouillé)', patchCourant.statut === 200, patchCourant.texte);
    const clotures = await appel('GET', '/finances/caisse/clotures', jetonAdmin);
    verifier(
      'liste des clôtures : 3 (mois −1, −2, −3)',
      clotures.statut === 200 && clotures.json?.length === 3,
      clotures.texte,
    );

    // --- F. Cotisations --------------------------------------------------------
    console.log('F. Cotisations :');
    const configAbsente = await appel('GET', '/cotisations/config', jetonAdmin);
    verifier('config cotisation absente : null', configAbsente.statut === 200 && configAbsente.json === null, configAbsente.texte);
    const suiviSansConfig = await appel('GET', `/cotisations/suivi?periode=${periodeMois}`, jetonAdmin);
    verifier(
      'suivi sans config : config_absente, aucun membre',
      suiviSansConfig.statut === 200 && suiviSansConfig.json?.config_absente === true &&
        suiviSansConfig.json?.membres?.length === 0,
      suiviSansConfig.texte,
    );
    const configPost = await appel('POST', '/cotisations/config', jetonTresorier, { montant_fcfa: 2000 });
    verifier(
      'config cotisation fixée : 201, 2 000 FCFA mensuels',
      configPost.statut === 201 && configPost.json?.montant_fcfa === 2000 &&
        configPost.json?.periodicite === 'mensuelle',
      configPost.texte,
    );
    const configMembre = await appel('POST', '/cotisations/config', jetonFideleA, { montant_fcfa: 3000 });
    verifier('config cotisation : membre 403', configMembre.statut === 403, configMembre.texte);
    const cotisationSansMembre = await appel('POST', '/contributions', jetonTresorier, {
      type: 'cotisation', amount_fcfa: 2000, payment_method: 'especes',
    });
    verifier('cotisation sans membre : 400', cotisationSansMembre.statut === 400, cotisationSansMembre.texte);
    // Campagne active (SQL direct, comme les cultes du test T6).
    const { rows: campagneRows } = await pool.query(
      `INSERT INTO campagnes (church_id, nom, objectif_fcfa, date_debut, date_fin, statut)
       VALUES ($1, 'Campagne T7', 100000, '2026-01-01', '2026-12-31', 'active') RETURNING id`,
      [egliseId],
    );
    const idCampagne = campagneRows[0].id;
    const cotisationCampagne = await appel('POST', '/contributions', jetonTresorier, {
      type: 'cotisation', amount_fcfa: 2000, payment_method: 'especes', member_id: idA, campagne_id: idCampagne,
    });
    verifier('cotisation affectée à une campagne : 400', cotisationCampagne.statut === 400, cotisationCampagne.texte);
    const dimeCampagne = await appel('POST', '/contributions', jetonTresorier, {
      type: 'dime', amount_fcfa: 1000, payment_method: 'especes', member_id: idA, campagne_id: idCampagne,
    });
    verifier('dîme affectée à une campagne : 201 (cas normal intact)', dimeCampagne.statut === 201, dimeCampagne.texte);
    const cotisationA = await appel('POST', '/contributions', jetonTresorier, {
      type: 'cotisation', amount_fcfa: 2000, payment_method: 'especes', member_id: idA,
    });
    const idCotisationA = cotisationA.json?.id;
    const cotisationA2 = await appel('POST', '/contributions', jetonTresorier, {
      type: 'cotisation', amount_fcfa: 1000, payment_method: 'wave', member_id: idA,
    });
    const cotisationB = await appel('POST', '/contributions', jetonTresorier, {
      type: 'cotisation', amount_fcfa: 500, payment_method: 'wave', member_id: idB,
    });
    const idCotisationB = cotisationB.json?.id;
    verifier(
      'cotisations saisies : 201, en_attente',
      cotisationA.statut === 201 && cotisationA2.statut === 201 && cotisationB.statut === 201,
      `${cotisationA.texte} ${cotisationA2.texte} ${cotisationB.texte}`,
    );
    const confirmeCotisationA = await appel('PATCH', `/contributions/${idCotisationA}/statut`, jetonAdmin, { status: 'confirme' });
    verifier(
      'cotisation A confirmée : reçu émis',
      confirmeCotisationA.statut === 200 && typeof confirmeCotisationA.json?.recu_numero === 'string',
      confirmeCotisationA.texte,
    );
    await appel('PATCH', `/contributions/${idCotisationB}/statut`, jetonAdmin, { status: 'confirme' });
    const suivi = await appel('GET', `/cotisations/suivi?periode=${periodeMois}`, jetonAdmin);
    const ligneSuivi = (nom) => suivi.json?.membres?.find((m) => m.membre_nom === nom);
    verifier(
      'suivi : A payé (2 000 / 2 000, reste 0), B partiel (500 / 2 000, reste 1 500)',
      suivi.statut === 200 &&
        ligneSuivi('Cotisant T7')?.montant_du_fcfa === 2000 &&
        ligneSuivi('Cotisant T7')?.montant_paye_fcfa === 2000 &&
        ligneSuivi('Cotisant T7')?.reste_fcfa === 0 &&
        ligneSuivi('Cotisant T7')?.statut === 'payee' &&
        ligneSuivi('Partiel T7')?.montant_paye_fcfa === 500 &&
        ligneSuivi('Partiel T7')?.reste_fcfa === 1500 &&
        ligneSuivi('Partiel T7')?.statut === 'partielle',
      suivi.texte,
    );
    verifier(
      'suivi : membre inactif exclu, totaux 4 000 dus / 2 500 payés / 1 500 restants',
      suivi.json?.membres?.length === 2 &&
        !suivi.json.membres.some((m) => m.membre_nom === 'Inactif T7') &&
        suivi.json?.totaux?.total_du_fcfa === 4000 &&
        suivi.json?.totaux?.total_paye_fcfa === 2500 &&
        suivi.json?.totaux?.total_reste_fcfa === 1500 &&
        suivi.json?.totaux?.membres_payes === 1 &&
        suivi.json?.totaux?.membres_total === 2,
      suivi.texte,
    );
    const suiviFidele = await appel('GET', `/cotisations/suivi?periode=${periodeMois}`, jetonFideleA);
    verifier(
      'suivi : le membre ne voit que sa propre ligne',
      suiviFidele.statut === 200 && suiviFidele.json?.membres?.length === 1 &&
        suiviFidele.json.membres[0].membre_nom === 'Cotisant T7',
      suiviFidele.texte,
    );
    const suiviMauvaisePeriode = await appel('GET', `/cotisations/suivi?periode=${annee}`, jetonAdmin);
    verifier('suivi mensuel avec une période annuelle : 400', suiviMauvaisePeriode.statut === 400, suiviMauvaisePeriode.texte);

    // --- G. Budgets par département -------------------------------------------
    console.log('G. Budgets par département :');
    const { rows: depRows } = await pool.query(
      `INSERT INTO departements (church_id, nom) VALUES ($1, 'Louange'), ($1, 'Jeunesse') RETURNING id, nom`,
      [egliseId],
    );
    const idLouange = depRows.find((d) => d.nom === 'Louange').id;
    const idJeunesse = depRows.find((d) => d.nom === 'Jeunesse').id;
    const budgetDep = await appel('POST', '/budgets-departements', jetonTresorier, {
      departement_id: idLouange, annee, mois, montant_prevu: 50000,
    });
    verifier(
      'budget département créé : 201',
      budgetDep.statut === 201 && budgetDep.json?.montant_prevu === 50000,
      budgetDep.texte,
    );
    const idBudgetDep = budgetDep.json?.id;
    const budgetDep2 = await appel('POST', '/budgets-departements', jetonTresorier, {
      departement_id: idLouange, annee, mois, montant_prevu: 60000,
    });
    verifier(
      'budget département remplacé (upsert) : 201, 60 000',
      budgetDep2.statut === 201 && budgetDep2.json?.montant_prevu === 60000,
      budgetDep2.texte,
    );
    const depenseLouange = await appel('POST', '/plan-comptable/depenses', jetonAdmin, {
      montant_fcfa: 65000, motif: 'Sono T7', departement_id: idLouange, mode_paiement: 'virement',
    });
    verifier('dépense Louange 65 000 : 201', depenseLouange.statut === 201, depenseLouange.texte);
    const depenseJeunesse = await appel('POST', '/plan-comptable/depenses', jetonAdmin, {
      montant_fcfa: 4000, motif: 'Goûter T7', departement_id: idJeunesse, mode_paiement: 'especes',
    });
    verifier('dépense Jeunesse 4 000 : 201', depenseJeunesse.statut === 201, depenseJeunesse.texte);
    const suiviDep = await appel('GET', `/plan-comptable/suivi-departements?annee=${annee}&mois=${mois}`, jetonAdmin);
    const ligneDep = (nom) => suiviDep.json?.par_departements?.find((d) => d.departement === nom);
    verifier(
      'suivi départements : Louange dépasse (60 000 prévus, 65 000 réels, écart 5 000)',
      suiviDep.statut === 200 &&
        ligneDep('Louange')?.prevu_fcfa === 60000 &&
        ligneDep('Louange')?.reel_fcfa === 65000 &&
        ligneDep('Louange')?.ecart_fcfa === 5000 &&
        ligneDep('Louange')?.depasse === true &&
        ligneDep('Louange')?.budget_defini === true,
      suiviDep.texte,
    );
    verifier(
      'suivi départements : Jeunesse sans budget (0 prévus, 4 000 réels, pas de dépassement)',
      ligneDep('Jeunesse')?.prevu_fcfa === 0 &&
        ligneDep('Jeunesse')?.reel_fcfa === 4000 &&
        ligneDep('Jeunesse')?.depasse === false &&
        ligneDep('Jeunesse')?.budget_defini === false,
      suiviDep.texte,
    );
    verifier(
      'suivi départements : sans département 3 000 (dépense payée sans département), totaux 60 000 / 72 000',
      suiviDep.json?.sans_departement?.reel_fcfa === 3000 &&
        suiviDep.json?.total_prevu_fcfa === 60000 &&
        suiviDep.json?.total_reel_fcfa === 72000,
      suiviDep.texte,
    );
    const supprBudgetDep = await appel('DELETE', `/budgets-departements/${idBudgetDep}`, jetonAdmin);
    verifier('budget département supprimé : 204', supprBudgetDep.statut === 204, supprBudgetDep.texte);
    const suiviDepApres = await appel('GET', `/plan-comptable/suivi-departements?annee=${annee}&mois=${mois}`, jetonAdmin);
    verifier(
      'suivi après suppression : Louange sans budget',
      ligneDep('Louange') === undefined ||
        suiviDepApres.json?.par_departements?.find((d) => d.departement === 'Louange')?.budget_defini === false,
      suiviDepApres.texte,
    );

    // --- H. Non-régression : les cotisations ne polluent pas les dons --------
    console.log('H. Attestations (dons seulement) :');
    const totaux = await appel('GET', '/contributions?status=confirme&limit=100', jetonAdmin);
    verifier(
      'totaux par type : cotisation 2 500 à part, dîme 5 000, offrande 7 000',
      totaux.statut === 200 &&
        totaux.json?.totaux?.cotisation?.total_fcfa === 2500 &&
        totaux.json?.totaux?.dime?.total_fcfa === 5000 &&
        totaux.json?.totaux?.offrande?.total_fcfa === 7000,
      totaux.texte,
    );
    const genererAtt = await appel('POST', '/attestations/generer', jetonAdmin, { annee });
    verifier('génération des attestations : 201, 2 créées', genererAtt.statut === 201 && genererAtt.json?.creees?.length === 2, genererAtt.texte);
    const attestations = await appel('GET', `/attestations?annee=${annee}`, jetonAdmin);
    const listeAtt = attestations.json?.attestations ?? [];
    const totalAtt = listeAtt.reduce((s, a) => s + Number(a.total_fcfa ?? 0), 0);
    verifier(
      'attestations : 2 donateurs, 12 000 au total (cotisations exclues)',
      attestations.statut === 200 && listeAtt.length === 2 && totalAtt === 12000,
      attestations.texte,
    );

    // --- I. Isolation entre églises --------------------------------------------
    console.log('I. Isolation :');
    const autre = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Autre église T7', city: 'Yamoussoukro' },
      admin: {
        full_name: 'Admin autre T7',
        email: 'admin-autre-t7@example.com',
        password: 'MotDePasse123!',
      },
    });
    const jetonAutre = autre.json?.token;
    const contributionAutre = await appel('GET', `/contributions/${idDime}`, jetonAutre);
    verifier('contribution d’une autre église : 404', contributionAutre.statut === 404, contributionAutre.texte);
    const caisseAutre = await appel('GET', '/finances/caisse', jetonAutre);
    verifier(
      'caisse d’une autre église : vide (solde 0)',
      caisseAutre.statut === 200 && caisseAutre.json?.solde === 0 && caisseAutre.json?.mouvements === 0,
      caisseAutre.texte,
    );
    const suiviAutre = await appel('GET', `/cotisations/suivi?periode=${periodeMois}`, jetonAutre);
    verifier(
      'suivi cotisations d’une autre église : config absente',
      suiviAutre.statut === 200 && suiviAutre.json?.config_absente === true,
      suiviAutre.texte,
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
