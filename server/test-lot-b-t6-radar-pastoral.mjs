// Test d'intégration de la tranche T6 (Lot B) — Radar pastoral et
// rendez-vous, partie serveur (migration 024).
//
// Périmètre : vue calculée v_radar_absences (GET /radar-absences),
// gestion des rendez-vous côté admin (GET /rendez-vous,
// PATCH /rendez-vous/:id/statut), visites typées (domicile / hôpital,
// avec lieu), rencontres d'accompagnement datées, suivi des personnes
// en difficulté (priorité + tableau des cas ouverts).
//
// Base fraîche, application du schéma puis des migrations avec le vrai
// moteur (dist/migrate.js), démarrage de l'API, appels HTTP, droits
// 401/403 et isolation entre églises. Aucun vrai envoi (ni SMS ni push).
//
// Usage (depuis la racine du dépôt, après `npm run build` dans server/) :
//   `node server/test-lot-b-t6-radar-pastoral.mjs`
// Variables : PORT (défaut 4108). PostgreSQL local requis
// (utilisateur postgres / postgres).

import { spawn, execFile } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { promisify } from 'node:util';
import { Client } from 'pg';
import argon2 from 'argon2';

const exec = promisify(execFile);
const JWT_SECRET = 'test-secret-t6-radar-32-caracteres';
const ADMIN = 'postgres://postgres:postgres@127.0.0.1:5432/postgres';
const NOM_DB = 'e_system_church_test_t6';

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
  const port = Number(process.env.PORT ?? 4108);
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

    const pool = new Client({ connectionString: databaseUrl });
    await pool.connect();

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

    // --- Préparation : église, admin, rôles, membres ----------------------
    const mere = await appel('POST', '/auth/register', null, {
      eglise: { name: 'Église mère T6', city: 'Abidjan' },
      admin: {
        full_name: 'Admin mère T6',
        email: 'admin-mere-t6@example.com',
        password: 'MotDePasse123!',
      },
    });
    verifier('inscription église mère', mere.statut === 201, mere.texte);
    const jetonAdmin = mere.json?.token;
    const egliseId = mere.json?.church?.id;

    // Rôles supplémentaires + fidèle lié à une fiche membre (SQL direct,
    // comme le test de la tranche 1).
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
    await creerCompte('culte-t6@example.com', 'responsable_culte');
    await creerCompte('tresorier-t6@example.com', 'tresorier');
    const jetonCulte = await login('culte-t6@example.com');
    const jetonTresorier = await login('tresorier-t6@example.com');

    // Membres : A (absent, 5 cultes), B (présent partout),
    // D (absent 3 cultes consécutifs), E (absent 1 culte), C (inactif).
    async function creerMembre(nom, statut = 'actif') {
      const r = await appel('POST', '/membres', jetonAdmin, { full_name: nom, status: statut });
      if (r.statut !== 201) throw new Error(`création membre ${nom}: ${r.texte}`);
      return r.json.id;
    }
    const idA = await creerMembre('Absent T6');
    const idB = await creerMembre('Présent T6');
    const idD = await creerMembre('Trois Absences T6');
    const idE = await creerMembre('Une Absence T6');
    const idC = await creerMembre('Inactif T6', 'inactif');
    // Les cultes de test sont dans le passé : on recule l'arrivée des
    // membres pour que le radar ne les ignore pas (borne = created_at).
    await pool.query(
      `UPDATE members SET created_at = '2026-10-01T00:00:00Z' WHERE id = ANY($1::uuid[])`,
      [[idA, idB, idD, idE, idC]],
    );

    // Fidèle lié à une fiche membre (pour les demandes de rendez-vous).
    const idFideleMembre = await creerMembre('Fidèle Demandeur T6');
    await creerCompte('fidele-t6@example.com', 'membre', idFideleMembre);
    const jetonFidele = await login('fidele-t6@example.com');

    // 5 cultes passés (8 au 12 novembre 2026, 10 h UTC).
    const datesCultes = ['2026-11-08', '2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12'];
    const culteIds = [];
    for (const d of datesCultes) {
      const { rows } = await pool.query(
        `INSERT INTO cultes (church_id, titre, date_heure) VALUES ($1, $2, $3) RETURNING id`,
        [egliseId, `Culte ${d}`, `${d}T10:00:00Z`],
      );
      culteIds.push(rows[0].id);
    }
    async function pointer(memberId, culteId) {
      await pool.query(
        `INSERT INTO presences (church_id, culte_id, member_id, statut, mode) VALUES ($1, $2, $3, 'present', 'manuel')`,
        [egliseId, culteId, memberId],
      );
    }
    // B présent aux 5 cultes ; D présent aux 2 premiers seulement ;
    // E présent aux 4 premiers ; A et C jamais pointés.
    for (const c of culteIds) await pointer(idB, c);
    await pointer(idD, culteIds[0]);
    await pointer(idD, culteIds[1]);
    for (let i = 0; i < 4; i += 1) await pointer(idE, culteIds[i]);

    // --- A. Radar des absences --------------------------------------------
    console.log('A. Radar des absences (vue calculée) :');
    const radar = await appel('GET', '/radar-absences', jetonAdmin);
    verifier(
      'GET /radar-absences admin : 200, 2 membres (A=5, D=3)',
      radar.statut === 200 &&
        radar.json?.total === 2 &&
        radar.json?.items?.[0]?.membre_nom === 'Absent T6' &&
        radar.json?.items?.[0]?.absences_consecutives === 5 &&
        radar.json?.items?.[1]?.membre_nom === 'Trois Absences T6' &&
        radar.json?.items?.[1]?.absences_consecutives === 3,
      radar.texte,
    );
    verifier(
      'radar : B (0), E (1) et C (inactif) absents du radar',
      radar.statut === 200 &&
        Array.isArray(radar.json?.items) &&
        !radar.json.items.some((x) => ['Présent T6', 'Une Absence T6', 'Inactif T6'].includes(x.membre_nom)),
      radar.texte,
    );
    verifier(
      'radar : alerte bienveillante + visite suggérée (domicile)',
      radar.statut === 200 &&
        typeof radar.json?.items?.[0]?.alerte === 'string' &&
        radar.json.items[0].alerte.includes('Absent T6') &&
        radar.json.items[0].visite_suggeree?.type === 'domicile',
      radar.texte,
    );
    verifier(
      'radar : dernière présence de D = 2026-11-09',
      radar.statut === 200 &&
        String(radar.json?.items?.[1]?.derniere_presence ?? '').startsWith('2026-11-09'),
      radar.texte,
    );
    const radarSeuil5 = await appel('GET', '/radar-absences?seuil=5', jetonAdmin);
    verifier(
      'radar ?seuil=5 : seul A',
      radarSeuil5.statut === 200 &&
        radarSeuil5.json?.total === 1 &&
        radarSeuil5.json?.items?.[0]?.membre_nom === 'Absent T6',
      radarSeuil5.texte,
    );
    const radarSeuil1 = await appel('GET', '/radar-absences?seuil=1', jetonAdmin);
    verifier(
      'radar ?seuil=1 : A, D et E',
      radarSeuil1.statut === 200 && radarSeuil1.json?.total === 3,
      radarSeuil1.texte,
    );
    const radarTresorier = await appel('GET', '/radar-absences', jetonTresorier);
    verifier('radar trésorier : 403', radarTresorier.statut === 403, radarTresorier.texte);
    const radarFidele = await appel('GET', '/radar-absences', jetonFidele);
    verifier('radar membre : 403', radarFidele.statut === 403, radarFidele.texte);
    const radarCulte = await appel('GET', '/radar-absences', jetonCulte);
    verifier('radar responsable de culte : 200', radarCulte.statut === 200, radarCulte.texte);
    const auditsRadar = await pool.query(
      `SELECT action FROM audit_logs WHERE action = 'radar_absences.lu'`,
    );
    verifier(
      'lecture du radar journalisée (audit_logs radar_absences.lu)',
      auditsRadar.rowCount >= 1,
      `lignes=${auditsRadar.rowCount}`,
    );

    // --- B. Rendez-vous côté admin -----------------------------------------
    console.log('B. Rendez-vous côté admin :');
    const demain = new Date(Date.now() + 86400000).toISOString().substring(0, 10);
    const demande = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: demain,
      motif: 'Entretien pastoral T6.',
    });
    verifier(
      'demande fidèle : 201, en_attente',
      demande.statut === 201 && demande.json?.rendez_vous?.statut === 'en_attente',
      demande.texte,
    );
    const rdvId = demande.json?.rendez_vous?.id;

    const listeRdv = await appel('GET', '/rendez-vous', jetonAdmin);
    verifier(
      'GET /rendez-vous admin : 200, 1 demande, nom du membre joint',
      listeRdv.statut === 200 &&
        listeRdv.json?.total === 1 &&
        listeRdv.json?.items?.[0]?.membre_nom === 'Fidèle Demandeur T6',
      listeRdv.texte,
    );
    const listeFiltre = await appel('GET', '/rendez-vous?statut=confirme', jetonAdmin);
    verifier(
      'GET /rendez-vous?statut=confirme : 0 (filtre)',
      listeFiltre.statut === 200 && listeFiltre.json?.total === 0,
      listeFiltre.texte,
    );
    const unRdv = await appel('GET', `/rendez-vous/${rdvId}`, jetonCulte);
    verifier(
      'GET /rendez-vous/:id responsable de culte : 200',
      unRdv.statut === 200 && unRdv.json?.id === rdvId,
      unRdv.texte,
    );
    const listeTresorier = await appel('GET', '/rendez-vous', jetonTresorier);
    verifier('GET /rendez-vous trésorier : 403', listeTresorier.statut === 403, listeTresorier.texte);
    const listeFidele = await appel('GET', '/rendez-vous', jetonFidele);
    verifier('GET /rendez-vous membre : 403', listeFidele.statut === 403, listeFidele.texte);

    const sansCreneau = await appel('PATCH', `/rendez-vous/${rdvId}/statut`, jetonAdmin, {
      statut: 'confirme',
    });
    verifier(
      'confirmer sans créneau : 400',
      sansCreneau.statut === 400,
      sansCreneau.texte,
    );
    const confirme = await appel('PATCH', `/rendez-vous/${rdvId}/statut`, jetonAdmin, {
      statut: 'confirme',
      creneau: '10h00',
    });
    verifier(
      'confirmer avec créneau : 200, statut confirme, créneau 10h00',
      confirme.statut === 200 &&
        confirme.json?.statut === 'confirme' &&
        confirme.json?.creneau === '10h00',
      confirme.texte,
    );
    const refuseApres = await appel('PATCH', `/rendez-vous/${rdvId}/statut`, jetonAdmin, {
      statut: 'refuse',
    });
    verifier(
      'refuser un rendez-vous confirmé : 409',
      refuseApres.statut === 409,
      refuseApres.texte,
    );
    const annule = await appel('PATCH', `/rendez-vous/${rdvId}/statut`, jetonCulte, {
      statut: 'annule',
    });
    verifier(
      'annuler un rendez-vous confirmé (responsable) : 200',
      annule.statut === 200 && annule.json?.statut === 'annule',
      annule.texte,
    );
    const reconfirme = await appel('PATCH', `/rendez-vous/${rdvId}/statut`, jetonAdmin, {
      statut: 'confirme',
      creneau: '11h00',
    });
    verifier(
      'confirmer un rendez-vous annulé : 409 (terminal)',
      reconfirme.statut === 409,
      reconfirme.texte,
    );

    const demande2 = await appel('POST', '/moi/rendez-vous', jetonFidele, {
      date_souhaitee: demain,
      motif: 'Deuxième demande T6.',
    });
    const rdvId2 = demande2.json?.rendez_vous?.id;
    const refuse = await appel('PATCH', `/rendez-vous/${rdvId2}/statut`, jetonAdmin, {
      statut: 'refuse',
    });
    verifier(
      'refuser une demande en attente : 200',
      refuse.statut === 200 && refuse.json?.statut === 'refuse',
      refuse.texte,
    );
    const statutInvalide = await appel('PATCH', `/rendez-vous/${rdvId2}/statut`, jetonAdmin, {
      statut: 'en_attente',
    });
    verifier(
      'statut invalide (en_attente) : 400',
      statutInvalide.statut === 400,
      statutInvalide.texte,
    );
    const inconnu = await appel('PATCH', '/rendez-vous/00000000-0000-0000-0000-000000000000/statut', jetonAdmin, {
      statut: 'confirme',
      creneau: '10h00',
    });
    verifier('rendez-vous inconnu : 409', inconnu.statut === 409, inconnu.texte);
    const auditsRdv = await pool.query(
      `SELECT action FROM audit_logs WHERE action LIKE 'rendez_vous.%' ORDER BY created_at`,
    );
    verifier(
      'transitions journalisées (rendez_vous.confirme/refuse/annule)',
      ['rendez_vous.confirme', 'rendez_vous.refuse', 'rendez_vous.annule'].every((a) =>
        auditsRdv.rows.some((x) => x.action === a),
      ),
      JSON.stringify(auditsRdv.rows.map((x) => x.action)),
    );

    // --- C. Visites typées, accompagnements, rencontres, cas ouverts ------
    console.log('C. Visites typées, accompagnements, rencontres, cas ouverts :');
    const visiteDom = await appel('POST', '/visites-pastorales', jetonAdmin, {
      member_id: idA,
      date_visite: '2026-11-13T10:00:00Z',
      type: 'domicile',
      lieu: '12 rue des Palmiers, Abidjan',
      motif: 'Visite après absences.',
    });
    verifier(
      'visite à domicile avec lieu : 201',
      visiteDom.statut === 201 &&
        visiteDom.json?.type === 'domicile' &&
        visiteDom.json?.lieu === '12 rue des Palmiers, Abidjan',
      visiteDom.texte,
    );
    const visiteHop = await appel('POST', '/visites-pastorales', jetonCulte, {
      member_id: idB,
      date_visite: '2026-11-13T11:00:00Z',
      type: 'hopital',
      lieu: 'CHU de Treichville',
    });
    verifier(
      'visite à l’hôpital : 201',
      visiteHop.statut === 201 && visiteHop.json?.type === 'hopital',
      visiteHop.texte,
    );
    const visiteMauvaisType = await appel('POST', '/visites-pastorales', jetonAdmin, {
      member_id: idA,
      date_visite: '2026-11-13T10:00:00Z',
      type: 'bureau',
    });
    verifier('type de visite invalide : 400', visiteMauvaisType.statut === 400, visiteMauvaisType.texte);
    const visitesDom = await appel('GET', '/visites-pastorales?type=domicile', jetonAdmin);
    verifier(
      'GET /visites-pastorales?type=domicile : 1 seule',
      visitesDom.statut === 200 && visitesDom.json?.total === 1,
      visitesDom.texte,
    );

    const accHaute = await appel('POST', '/accompagnements', jetonAdmin, {
      member_id: idA,
      type: 'difficulte',
      priorite: 'haute',
      description: 'Cas difficile T6.',
    });
    verifier(
      'accompagnement difficulté, priorité haute : 201',
      accHaute.statut === 201 && accHaute.json?.priorite === 'haute',
      accHaute.texte,
    );
    const accDefaut = await appel('POST', '/accompagnements', jetonAdmin, {
      member_id: idD,
      type: 'difficulte',
      description: 'Cas sans priorité précisée.',
    });
    verifier(
      'accompagnement sans priorité : défaut normale',
      accDefaut.statut === 201 && accDefaut.json?.priorite === 'normale',
      accDefaut.texte,
    );
    const accUrgente = await appel('POST', '/accompagnements', jetonAdmin, {
      member_id: idB,
      type: 'difficulte',
      priorite: 'urgente',
      description: 'Cas urgent T6.',
    });
    verifier('accompagnement priorité urgente : 201', accUrgente.statut === 201, accUrgente.texte);
    const accCouple = await appel('POST', '/accompagnements', jetonAdmin, {
      member_id: idE,
      type: 'couple',
      priorite: 'basse',
      description: 'Couple en cours.',
    });
    verifier('accompagnement couple en cours : 201', accCouple.statut === 201, accCouple.texte);
    const accTermine = await appel('POST', '/accompagnements', jetonAdmin, {
      member_id: idB,
      type: 'difficulte',
      priorite: 'haute',
      description: 'Cas déjà terminé.',
    });
    const ferme = await appel('PATCH', `/accompagnements/${accTermine.json?.id}`, jetonAdmin, {
      statut: 'termine',
    });
    verifier('accompagnement terminé (PATCH statut) : 200', ferme.statut === 200, ferme.texte);
    const accMauvaisePriorite = await appel('POST', '/accompagnements', jetonAdmin, {
      member_id: idA,
      type: 'difficulte',
      priorite: 'critique',
    });
    verifier('priorité invalide : 400', accMauvaisePriorite.statut === 400, accMauvaisePriorite.texte);

    const rencontre = await appel('POST', '/rencontres-accompagnement', jetonAdmin, {
      accompagnement_id: accHaute.json?.id,
      date_rencontre: '2026-11-10',
      note: 'Première rencontre.',
    });
    verifier(
      'rencontre datée : 201',
      rencontre.statut === 201 && rencontre.json?.date_rencontre?.startsWith('2026-11-10'),
      rencontre.texte,
    );
    const rencontre2 = await appel('POST', '/rencontres-accompagnement', jetonCulte, {
      accompagnement_id: accHaute.json?.id,
      date_rencontre: '2026-11-12',
      note: 'Deuxième rencontre.',
    });
    verifier('deuxième rencontre : 201', rencontre2.statut === 201, rencontre2.texte);
    const rencontresListe = await appel(
      'GET',
      `/rencontres-accompagnement?accompagnement_id=${accHaute.json?.id}`,
      jetonAdmin,
    );
    verifier(
      'liste des rencontres : 2, plus récente d’abord',
      rencontresListe.statut === 200 &&
        rencontresListe.json?.total === 2 &&
        String(rencontresListe.json?.items?.[0]?.date_rencontre ?? '').startsWith('2026-11-12'),
      rencontresListe.texte,
    );
    const rencontreInconnue = await appel('POST', '/rencontres-accompagnement', jetonAdmin, {
      accompagnement_id: '00000000-0000-0000-0000-000000000000',
      date_rencontre: '2026-11-10',
    });
    verifier(
      'rencontre sur accompagnement inconnu : 400',
      rencontreInconnue.statut === 400,
      rencontreInconnue.texte,
    );

    const cas = await appel('GET', '/accompagnements/cas-ouverts', jetonAdmin);
    verifier(
      'cas ouverts : 3 difficultés en cours, ordre urgente > haute > normale',
      cas.statut === 200 &&
        cas.json?.total === 3 &&
        cas.json?.items?.[0]?.priorite === 'urgente' &&
        cas.json?.items?.[1]?.priorite === 'haute' &&
        cas.json?.items?.[2]?.priorite === 'normale' &&
        cas.json?.items?.[0]?.membre_nom === 'Présent T6',
      cas.texte,
    );
    const casHaute = await appel('GET', '/accompagnements/cas-ouverts?priorite=haute', jetonAdmin);
    verifier(
      'cas ouverts ?priorite=haute : 1 seul',
      casHaute.statut === 200 && casHaute.json?.total === 1,
      casHaute.texte,
    );
    const casTous = await appel('GET', '/accompagnements/cas-ouverts?type=tous', jetonAdmin);
    verifier(
      'cas ouverts ?type=tous : 4 (dont le couple)',
      casTous.statut === 200 && casTous.json?.total === 4,
      casTous.texte,
    );
    const casTresorier = await appel('GET', '/accompagnements/cas-ouverts', jetonTresorier);
    verifier('cas ouverts trésorier : 403', casTresorier.statut === 403, casTresorier.texte);
    const auditsCas = await pool.query(
      `SELECT action FROM audit_logs WHERE action = 'accompagnement.cas_ouverts_lu'`,
    );
    verifier(
      'lecture des cas ouverts journalisée',
      auditsCas.rowCount >= 1,
      `lignes=${auditsCas.rowCount}`,
    );

    await pool.end();
  } finally {
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
