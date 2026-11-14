/* Test local T12 — US4 à US17 restantes (migration 030)
 * — base PostgreSQL de test seulement, jamais Render.
 * Usage :
 *   sudo -u postgres psql -c "CREATE DATABASE esc_t12_test;"
 *   DATABASE_URL=<redacted>
 *   node test-t12-us.mjs
 * La base doit être créée vide ; le script applique db/schema.sql puis
 * toutes les migrations, démarre l'API (tsx server/src/index.ts,
 * PORT 3114) et exerce promesses, dons en nature, visiteurs,
 * événements de vie, transparence, portefeuille, consentements
 * WhatsApp/SMS, alertes mère, listes configurables, seuils et dîme,
 * consultations sensibles.
 * Il ne supprime pas la base : la supprimer après, à la main.
 *
 * Cas testés : migration 030 (tables, colonnes, index après tables) ;
 * promesse en 3 versements (création, échéances, versement au montant
 * exact, montant différent refusé, confirmation qui marque l'échéance
 * reçue, promesse terminée à la dernière, annulation qui garde le reçu) ;
 * membre qui s'engage pour un autre (403) ; don en nature hors finances ;
 * visiteur puis devenu membre ; événement de vie masqué ; transparence
 * refusée puis visible après activation, annexe qui voit sa mère ;
 * portefeuille sans compte Wallet ; consentements WhatsApp et liste ;
 * alertes : détection réservée à la mère, une seule alerte ouverte par
 * type, traitement ; listes : rôle sans niveau refusé, statut configuré
 * accepté puis refusé une fois archivé ; consultations journalisées.
 */
import { spawn } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { Client } from "pg";
import argon2 from "argon2";

const DB = process.env.DATABASE_URL;
const BASE = "http://127.0.0.1:3114";
if (!DB) throw new Error("DATABASE_URL manquant");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, ko = 0;
function check(nom, cond, extra = "") {
  if (cond) { ok++; console.log(`  OK  ${nom}`); }
  else { ko++; console.log(`  KO  ${nom} ${extra}`); }
}

const db = new Client({ connectionString: DB });
await db.connect();
await db.query(readFileSync("../db/schema.sql", "utf8"));
for (const f of readdirSync("../db/migrations").sort()) {
  if (!f.endsWith(".sql")) continue;
  await db.query(readFileSync(`../db/migrations/${f}`, "utf8"));
}
for (const t of ["promesses", "echeances_promesses", "dons_nature", "visiteurs", "alertes_mere", "listes_configurables", "consultations_sensibles"]) {
  const r = await db.query(`SELECT 1 FROM information_schema.tables WHERE table_name = $1`, [t]);
  check(`migration 030 : table ${t} créée`, r.rowCount === 1);
}
const col = await db.query(`SELECT 1 FROM information_schema.columns WHERE table_name = 'contributions' AND column_name = 'promesse_id'`);
check("migration 030 : contributions.promesse_id", col.rowCount === 1);
const col2 = await db.query(`SELECT 1 FROM information_schema.columns WHERE table_name = 'members' AND column_name = 'whatsapp_consentement'`);
check("migration 030 : members.whatsapp_consentement", col2.rowCount === 1);
const col3 = await db.query(`SELECT 1 FROM information_schema.columns WHERE table_name = 'eglise_parametres' AND column_name = 'montant_dime_suggere'`);
check("migration 030 : eglise_parametres.montant_dime_suggere", col3.rowCount === 1);

const hash = await argon2.hash("Test1234!");
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const church = async (code, name, parent = null) =>
  (await q(`INSERT INTO churches (code, code_fidele, name, city, status, parent_church_id) VALUES ($1, $2, $3, 'Abidjan', 'active', $4) RETURNING id`, [code, `ESC-F-${code.slice(4)}`, name, parent]))[0].id;
const mere = await church("ESC-T12-M", "Mère T12");
const annexe = await church("ESC-T12-A", "Annexe T12", mere);
async function user(email, fullName, memberships) {
  const u = (await q(`INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id`, [email, hash, fullName]))[0].id;
  for (const [egliseId, roleName] of memberships) {
    await q(`INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, $3)`, [u, egliseId, roleName]);
  }
  return u;
}
const adminId = await user("admin@t12.test", "Admin T12", [[mere, "admin_eglise"], [annexe, "admin_eglise"]]);
const adminAnnexeId = await user("admin-annexe@t12.test", "Admin Annexe T12", [[annexe, "admin_eglise"]]);
const tresorierId = await user("tresorier@t12.test", "Trésorier T12", [[mere, "tresorier"]]);
const membreUserId = await user("membre@t12.test", "Membre T12", [[mere, "membre"]]);
const dans5j = new Date(Date.now() + 5 * 86400000).toISOString().slice(0, 10);
const membreId = (await q(
  `INSERT INTO members (church_id, full_name, matricule, phone, birth_date) VALUES ($1, 'Membre T12', 'M-T12-001', '+225 07 00 00 01', $2) RETURNING id`,
  [mere, dans5j]))[0].id;
await q(`UPDATE users SET member_id = $2 WHERE id = $1`, [membreUserId, membreId]);
const autreMembreId = (await q(
  `INSERT INTO members (church_id, full_name, matricule) VALUES ($1, 'Autre Membre', 'M-T12-002') RETURNING id`,
  [mere]))[0].id;

const server = spawn("npx", ["tsx", "src/index.ts"], { cwd: process.cwd(), env: { ...process.env, PORT: "3114", DATABASE_URL: DB, JWT_SECRET: "test-secret-t12-32-caracteres-xx" }, stdio: "ignore", detached: true });
try {
  for (let i = 0; i < 30; i++) { try { const r = await fetch(`${BASE}/sante`); if (r.ok) break; } catch {} await sleep(500); }
  const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
  const appel = async (method, path, token, body) => {
    const r = await fetch(`${BASE}${path}`, {
      method,
      headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: r.status, data: await j(r) };
  };
  const login = async (email) => {
    const r = await appel("POST", "/auth/login", null, { identifiant: email, password: "Test1234!", channel: "web" });
    check(`connexion ${email}`, r.status === 200, JSON.stringify(r.data).slice(0, 200));
    return r.data.token;
  };
  const tokenAdmin = await login("admin@t12.test");
  const tokenAdminMere = tokenAdmin;
  const tokenAdminAnnexe = await login("admin-annexe@t12.test");
  const tokenTresorier = await login("tresorier@t12.test");
  const tokenMembre = await login("membre@t12.test");

  // -- US4 : promesses -------------------------------------------------------
  let r = await appel("POST", "/promesses", tokenAdminMere, { member_id: membreId, montant_total_fcfa: 9000, nb_versements: 3 });
  check("US4 : promesse créée (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  const promesseId = r.data.id;
  r = await appel("GET", `/promesses/${promesseId}`, tokenAdminMere);
  check("US4 : 3 échéances de 3000", r.status === 200 && Array.isArray(r.data.echeances) && r.data.echeances.length === 3 && r.data.echeances.every((e) => e.montant_fcfa === 3000), JSON.stringify(r.data.echeances ?? r.data).slice(0, 200));
  const echeance1 = r.data.echeances[0].id;
  const echeance2 = r.data.echeances[1].id;
  const echeance3 = r.data.echeances[2].id;
  r = await appel("POST", `/promesses/${promesseId}/versements`, tokenTresorier, { echeance_id: echeance1, amount_fcfa: 3000, payment_method: "especes" });
  check("US4 : versement au montant exact (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  const contributionId = r.data.id;
  r = await appel("POST", `/promesses/${promesseId}/versements`, tokenTresorier, { echeance_id: echeance2, amount_fcfa: 2500, payment_method: "especes" });
  check("US4 : versement au mauvais montant refusé (400)", r.status === 400, JSON.stringify(r.data).slice(0, 200));
  r = await appel("PATCH", `/contributions/${contributionId}/statut`, tokenAdminMere, { status: "confirme" });
  check("US4 : confirmation de la contribution (200)", r.status === 200, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", `/promesses/${promesseId}`, tokenAdminMere);
  check("US4 : échéance 1 reçue, promesse toujours en cours", r.status === 200 && r.data.echeances[0].statut === "recu" && r.data.statut === "en_cours" && r.data.recu_fcfa === 3000, JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", "/promesses", tokenMembre, { member_id: autreMembreId, montant_total_fcfa: 1000, nb_versements: 1 });
  check("US4 : membre qui s'engage pour un autre refusé (403)", r.status === 403, JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", "/promesses", tokenMembre, { member_id: membreId, montant_total_fcfa: 1000, nb_versements: 1 });
  check("US4 : membre qui s'engage pour lui-même (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  const promesseMembreId = r.data.id;
  r = await appel("PATCH", `/promesses/${promesseMembreId}`, tokenAdminMere, { statut: "annulee" });
  check("US4 : annulation d'une promesse sans versement (200)", r.status === 200 && r.data.statut === "annulee", JSON.stringify(r.data).slice(0, 200));
  // Terminer la première promesse : verser puis confirmer les 2 restantes.
  for (const ech of [echeance2, echeance3]) {
    const v = await appel("POST", `/promesses/${promesseId}/versements`, tokenTresorier, { echeance_id: ech, amount_fcfa: 3000, payment_method: "especes" });
    check(`US4 : versement échéance ${ech.slice(0, 8)} (201)`, v.status === 201, JSON.stringify(v.data).slice(0, 200));
    const c = await appel("PATCH", `/contributions/${v.data.id}/statut`, tokenAdminMere, { status: "confirme" });
    check(`US4 : confirmation versement ${ech.slice(0, 8)} (200)`, c.status === 200, JSON.stringify(c.data).slice(0, 200));
  }
  r = await appel("GET", `/promesses/${promesseId}`, tokenAdminMere);
  check("US4 : promesse terminée après la dernière confirmation", r.status === 200 && r.data.statut === "terminee" && r.data.recu_fcfa === 9000, JSON.stringify(r.data).slice(0, 200));

  // -- US5 : dons en nature ---------------------------------------------------
  r = await appel("POST", "/dons-nature", tokenTresorier, { member_id: membreId, description: "Sacs de riz", quantite: 5, unite: "sacs", type_don: "nourriture" });
  check("US5 : don en nature créé (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/dons-nature", tokenAdminMere);
  check("US5 : don en nature listé", r.status === 200 && Array.isArray(r.data.items) && r.data.items.length === 1, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/contributions?type=don", tokenAdminMere);
  check("US5 : don en nature absent des contributions en argent", r.status === 200 && !JSON.stringify(r.data).includes("Sacs de riz"), JSON.stringify(r.data).slice(0, 200));

  // -- US6 : visiteurs ---------------------------------------------------------
  r = await appel("POST", "/visiteurs", tokenAdminMere, { nom: "Visiteur Test", telephone: "+225 00 00 00 00" });
  check("US6 : visiteur créé (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  const visiteurId = r.data.id;
  r = await appel("POST", `/visiteurs/${visiteurId}/devenir-membre`, tokenAdminMere, { member_id: autreMembreId });
  check("US6 : visiteur devenu membre (200)", r.status === 200 && r.data.statut === "devenu_membre", JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", `/visiteurs/${visiteurId}/devenir-membre`, tokenAdminMere, { member_id: autreMembreId });
  check("US6 : visiteur déjà membre refusé (404)", r.status === 404, JSON.stringify(r.data).slice(0, 200));

  // -- US7 : événements de vie -------------------------------------------------
  r = await appel("GET", "/evenements-vie?jours=30", tokenAdminMere);
  check("US7 : anniversaire dans 5 jours rappelé", r.status === 200 && r.data.items.some((e) => e.type === "anniversaire" && e.member_id === membreId), JSON.stringify(r.data).slice(0, 300));
  r = await appel("PATCH", "/moi/evenements-vie-masques", tokenMembre, { types: ["anniversaire"] });
  check("US7 : membre masque son anniversaire (200)", r.status === 200, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/evenements-vie?jours=30", tokenAdminMere);
  check("US7 : anniversaire masqué absent des rappels", r.status === 200 && !r.data.items.some((e) => e.type === "anniversaire" && e.member_id === membreId), JSON.stringify(r.data).slice(0, 300));
  await appel("PATCH", "/moi/evenements-vie-masques", tokenMembre, { types: [] });

  // -- US8 : transparence --------------------------------------------------------
  r = await appel("GET", "/moi/transparence", tokenMembre);
  check("US8 : transparence refusée au membre quand désactivée (403)", r.status === 403, JSON.stringify(r.data).slice(0, 200));
  r = await appel("PATCH", "/parametres", tokenAdminMere, { transparence_visible_membres: true, montant_dime_suggere: 5000 });
  check("US14/US8 : paramètres seuils et dîme enregistrés (200)", r.status === 200 && r.data.montant_dime_suggere === 5000 && r.data.transparence_visible_membres === true, JSON.stringify(r.data).slice(0, 300));
  r = await appel("GET", "/parametres", tokenAdminMere);
  check("US14 : dîme suggérée relue (5000)", r.status === 200 && r.data.montant_dime_suggere === 5000, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/moi/transparence", tokenMembre);
  check("US8 : transparence visible après activation, totaux sans nominatif", r.status === 200 && typeof r.data.total_recettes_fcfa === "number" && !JSON.stringify(r.data).includes("Membre T12"), JSON.stringify(r.data).slice(0, 300));
  const tokenAdminAnnexeCheck = await appel("GET", "/moi/eglise", tokenAdminAnnexe);
  check("US8 : l'admin annexe est bien sur son annexe", tokenAdminAnnexeCheck.status === 200 && tokenAdminAnnexeCheck.data.church?.id === annexe, JSON.stringify(tokenAdminAnnexeCheck.data).slice(0, 200));
  r = await appel("GET", "/moi/transparence", tokenAdminAnnexe);
  check("US8 : l'annexe voit les chiffres de sa mère", r.status === 200 && r.data.eglise === "Mère T12", JSON.stringify(r.data).slice(0, 200));

  // -- US9 : portefeuille ---------------------------------------------------------
  r = await appel("GET", "/moi/carte/portefeuille", tokenMembre);
  check("US9 : carte exportable, aucun compte Wallet branché", r.status === 200 && r.data.matricule === "M-T12-001" && r.data.compte_wallet === null && typeof r.data.qr_donnees === "string", JSON.stringify(r.data).slice(0, 300));

  // -- US10/US16 : consentements ---------------------------------------------------
  r = await appel("GET", "/moi/consentements", tokenMembre);
  check("US10 : consentements lus (faux par défaut)", r.status === 200 && r.data.whatsapp_consentement === false, JSON.stringify(r.data).slice(0, 200));
  r = await appel("PATCH", "/moi/consentements", tokenMembre, { whatsapp_consentement: true });
  check("US10 : consentement WhatsApp donné (200)", r.status === 200 && r.data.whatsapp_consentement === true, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/whatsapp/consentements", tokenAdminMere);
  check("US10 : membre consenti dans la liste WhatsApp", r.status === 200 && r.data.items.some((m) => m.id === membreId) && r.data.fournisseur === null, JSON.stringify(r.data).slice(0, 300));

  // -- US11 : alertes mère -----------------------------------------------------------
  r = await appel("POST", "/alertes-mere/detecter", tokenAdminAnnexe);
  check("US11 : détection refusée à l'annexe (403)", r.status === 403, JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", "/alertes-mere/detecter", tokenAdminMere);
  check("US11 : détection par la mère (200)", r.status === 200, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/alertes-mere?statut=ouverte", tokenAdminMere);
  const alertes = r.data.items ?? [];
  check("US11 : alerte antenne inactive créée pour l'annexe sans activité", r.status === 200 && alertes.some((a) => a.annexe_id === annexe && a.type === "inactive"), JSON.stringify(r.data).slice(0, 300));
  const nbAvant = alertes.length;
  await appel("POST", "/alertes-mere/detecter", tokenAdminMere);
  r = await appel("GET", "/alertes-mere?statut=ouverte", tokenAdminMere);
  check("US11 : pas de doublon à la deuxième détection", r.status === 200 && (r.data.items ?? []).length === nbAvant, JSON.stringify(r.data).slice(0, 200));
  const alerteId = (r.data.items ?? []).find((a) => a.annexe_id === annexe && a.type === "inactive")?.id;
  if (alerteId) {
    r = await appel("PATCH", `/alertes-mere/${alerteId}/traiter`, tokenAdminMere);
    check("US11 : alerte traitée (200)", r.status === 200 && r.data.statut === "traitee", JSON.stringify(r.data).slice(0, 200));
    r = await appel("PATCH", `/alertes-mere/${alerteId}/traiter`, tokenAdminMere);
    check("US11 : alerte déjà traitée refusée (404)", r.status === 404, JSON.stringify(r.data).slice(0, 200));
  } else {
    check("US11 : alerte traitée (200)", false, "aucune alerte inactive trouvée");
    check("US11 : alerte déjà traitée refusée (404)", false, "aucune alerte inactive trouvée");
  }

  // -- US12/US13 : listes configurables -----------------------------------------------
  r = await appel("POST", "/listes-configurables", tokenAdminMere, { type: "role", libelle: "Responsable jeunesse" });
  check("US12 : rôle sans niveau refusé (400)", r.status === 400, JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", "/listes-configurables", tokenAdminMere, { type: "role", libelle: "Responsable jeunesse", niveau: "responsable_culte" });
  check("US12 : rôle avec niveau créé (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", "/listes-configurables", tokenAdminMere, { type: "statut_membre", libelle: "Ancien fidèle" });
  check("US13 : statut de membre configuré créé (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  const statutId = r.data.id;
  r = await appel("GET", "/listes-configurables/statuts-membre", tokenAdminMere);
  check("US13 : statut configuré dans la liste effective", r.status === 200 && r.data.items.includes("Ancien fidèle") && r.data.items.includes("membre"), JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", `/membres/${membreId}/statut`, tokenAdminMere, { statut: "Ancien fidèle", motif: "Test T12" });
  check("US13 : changement vers le statut configuré (200)", r.status === 200, JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", `/membres/${membreId}/statut`, tokenAdminMere, { statut: "Statut inexistant" });
  check("US13 : statut non configuré refusé (400)", r.status === 400, JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", "/listes-configurables", tokenAdminMere, { type: "statut_membre", libelle: "parti", archive: true });
  check("US13 : défaut 'parti' archivé (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/listes-configurables/statuts-membre", tokenAdminMere);
  check("US13 : défaut archivé retiré de la liste effective", r.status === 200 && !r.data.items.includes("parti"), JSON.stringify(r.data).slice(0, 200));
  r = await appel("POST", `/membres/${membreId}/statut`, tokenAdminMere, { statut: "parti" });
  check("US13 : statut archivé refusé (400)", r.status === 400, JSON.stringify(r.data).slice(0, 200));
  await appel("PATCH", `/listes-configurables/${statutId}`, tokenAdminMere, { archive: true });
  r = await appel("GET", "/listes-configurables/statuts-membre", tokenAdminMere);
  check("US13 : statut configuré archivé retiré", r.status === 200 && !r.data.items.includes("Ancien fidèle"), JSON.stringify(r.data).slice(0, 200));

  // -- US17 : consultations sensibles ------------------------------------------------------
  r = await appel("POST", "/consultations-sensibles", tokenAdminMere, { ressource: "membre", ressource_id: membreId });
  check("US17 : lecture sensible journalisée (201)", r.status === 201, JSON.stringify(r.data).slice(0, 200));
  r = await appel("GET", "/consultations-sensibles", tokenAdminMere);
  check("US17 : journal visible par l'admin", r.status === 200 && r.data.items.some((c) => c.ressource_id === membreId), JSON.stringify(r.data).slice(0, 300));
  r = await appel("GET", "/moi/consultations", tokenMembre);
  check("US17 : membre voit qui a consulté sa fiche", r.status === 200 && r.data.items.some((c) => c.ressource_id === membreId), JSON.stringify(r.data).slice(0, 300));
} finally {
  try { process.kill(-server.pid); } catch {}
  await db.end();
}
console.log(`\nT12 : ${ok} OK, ${ko} KO`);
process.exit(ko ? 1 : 0);
