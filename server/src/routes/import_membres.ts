import type { FastifyInstance } from "fastify";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";
import { auditLog, generateMatricule, normalizeSexe } from "../auth.js";
import { dbError, requireAuth, requireRole } from "../middleware.js";

/**
 * Tranche A — Import des listes de fidèles (11 nov. 2026).
 *
 * GET  /import/modele      — modèle CSV téléchargeable (en-têtes + une
 *                             ligne d'exemple clairement fausse).
 * POST /import/apercu      — valide sans rien écrire : colonnes détectées,
 *                             aperçu, erreurs et doublons.
 * POST /import/confirmer   — crée les membres en transaction, renvoie le
 *                             rapport, journalise dans audit_logs et garde
 *                             l'historique dans imports_membres.
 * GET  /import/historique  — derniers rapports d'import de l'église.
 *
 * Entrée : le contenu CSV en JSON (`contenu_csv`) ou des lignes déjà lues
 * côté client (`lignes`, par ex. un XLSX lu par l'application Flutter
 * avec le paquet Dart `excel`, puis envoyé en JSON). Pas de multipart :
 * le serveur n'en a pas le support. Aucun compte utilisateur n'est créé :
 * l'import ne crée que des fiches `members` (user_id NULL), comme la
 * création d'un membre ne crée pas de compte.
 * Rôle : admin_eglise seulement.
 *
 * Modèle CSV (séparateur `;`, comme l'export de /stats/export) :
 *   nom;prenom;telephone;email;naissance;sexe;departement;fonction;poste;cellule
 * Doublon = e-mail déjà présent dans l'église, ou même nom complet +
 * même date de naissance déjà présents, ou même cas dans le fichier.
 * Les doublons sont ignorés (comptés dans `ignores`), jamais créés.
 */

const ADMIN = ["admin_eglise"] as const;

/** Champs du modèle, avec les en-têtes reconnus (sans accent, en minuscules). */
const CHAMPS = [
  { champ: "nom", obligatoire: true, entetes: ["nom", "nom_de_famille", "family_name", "lastname", "last_name"] },
  { champ: "prenom", obligatoire: true, entetes: ["prenom", "first_name", "firstname"] },
  { champ: "nom_complet", obligatoire: false, entetes: ["nom_complet", "full_name", "fullname", "nom_prenom"] },
  { champ: "telephone", obligatoire: false, entetes: ["telephone", "tel", "phone"] },
  { champ: "email", obligatoire: false, entetes: ["email", "e_mail", "courriel"] },
  { champ: "naissance", obligatoire: false, entetes: ["naissance", "date_naissance", "date_de_naissance", "birth_date"] },
  { champ: "sexe", obligatoire: false, entetes: ["sexe", "sex", "genre"] },
  { champ: "departement", obligatoire: false, entetes: ["departement", "department"] },
  { champ: "fonction", obligatoire: false, entetes: ["fonction", "function"] },
  { champ: "poste", obligatoire: false, entetes: ["poste", "position"] },
  { champ: "cellule", obligatoire: false, entetes: ["cellule", "cell_group", "groupe", "groupe_cellule"] },
] as const;

type Champ = (typeof CHAMPS)[number]["champ"];

const ENTETES_MODELE = ["nom", "prenom", "telephone", "email", "naissance", "sexe", "departement", "fonction", "poste", "cellule"];

/** Ligne d'exemple du modèle : des valeurs clairement fausses. */
const LIGNE_EXEMPLE = ["EXEMPLE", "Jean", "0700000000", "jean.exemple@exemple.ci", "1990-01-01", "M", "Louange", "Chantre", "Collaborateur", "Exemple"];

const MAX_LIGNES = 2000;
const MAX_APERCU = 100;

function normaliserEntete(h: string): string {
  return h
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function normaliserNom(nom: string): string {
  return nom.normalize("NFD").replace(/[̀-ͯ]/g, "").trim().replace(/\s+/g, " ").toLowerCase();
}

function dateValide(v: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return false;
  const d = new Date(`${v}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
}

/** Parseur CSV minimal : guillemets, `""` échappé, séparateur `;` ou `,`. */
function parseCsv(texte: string): { colonnes: string[]; lignes: Record<string, string>[] } {
  const sansBom = texte.replace(/^\uFEFF/, "");
  const lignesBrutes = sansBom.split(/\r\n|\n|\r/).filter((l) => l.trim() !== "");
  if (lignesBrutes.length === 0) return { colonnes: [], lignes: [] };
  const separateur = lignesBrutes[0].includes(";") ? ";" : ",";
  const decouper = (ligne: string): string[] => {
    const cellules: string[] = [];
    let courant = "";
    let entreGuillemets = false;
    for (let i = 0; i < ligne.length; i++) {
      const c = ligne[i];
      if (entreGuillemets) {
        if (c === '"') {
          if (ligne[i + 1] === '"') { courant += '"'; i++; } else { entreGuillemets = false; }
        } else { courant += c; }
      } else if (c === '"') {
        entreGuillemets = true;
      } else if (c === separateur) {
        cellules.push(courant); courant = "";
      } else { courant += c; }
    }
    cellules.push(courant);
    return cellules.map((c) => c.trim());
  };
  const colonnes = decouper(lignesBrutes[0]);
  const lignes = lignesBrutes.slice(1).map((l) => {
    const cellules = decouper(l);
    const row: Record<string, string> = {};
    colonnes.forEach((col, i) => { row[col] = cellules[i] ?? ""; });
    return row;
  });
  return { colonnes, lignes };
}

/** Correspondance automatique en-tête → champ, par alias. */
function mappingAuto(colonnes: string[]): Record<string, Champ> {
  const mapping: Record<string, Champ> = {};
  for (const col of colonnes) {
    const n = normaliserEntete(col);
    const trouve = CHAMPS.find((c) => c.entetes.includes(n as never));
    if (trouve) mapping[col] = trouve.champ;
  }
  return mapping;
}

function appliquerMapping(
  lignes: Record<string, string>[],
  mapping: Record<string, Champ>,
): Record<string, string>[] {
  return lignes.map((row) => {
    const out: Record<string, string> = {};
    for (const [colonne, champ] of Object.entries(mapping)) {
      out[champ] = (row[colonne] ?? "").trim();
    }
    return out;
  });
}

interface LigneValidee {
  numero: number;
  nom: string;
  prenom: string;
  fullName: string;
  telephone: string | null;
  email: string | null;
  birthDate: string | null;
  sexe: "F" | "M" | null;
  department: string | null;
  fonction: string | null;
  poste: string | null;
  cellGroup: string | null;
  erreurs: string[];
  doublon: boolean;
}

function validerLigne(
  row: Record<string, string>,
  numero: number,
  vus: { emails: Set<string>; nomsNaissances: Set<string> },
): LigneValidee {
  const erreurs: string[] = [];
  // Ligne d'exemple du modèle : jamais importée, l'utilisateur doit la supprimer.
  if (normaliserNom(row.nom ?? "") === "exemple" && normaliserNom(row.prenom ?? "") === "jean") {
    return {
      numero, nom: "", prenom: "", fullName: "", telephone: null, email: null,
      birthDate: null, sexe: null, department: null, fonction: null, poste: null,
      cellGroup: null, erreurs: ["Ligne d'exemple du modèle : supprimez-la avant l'import."], doublon: false,
    };
  }
  let nom = (row.nom ?? "").trim();
  let prenom = (row.prenom ?? "").trim();
  // `nom_complet` seul : dernier mot = nom de famille, le reste = prénom.
  if ((!nom || !prenom) && row.nom_complet) {
    const mots = row.nom_complet.trim().split(/\s+/);
    if (mots.length >= 2) {
      if (!prenom) prenom = mots.slice(0, -1).join(" ");
      if (!nom) nom = mots[mots.length - 1];
    }
  }
  if (nom.length < 1 || nom.length > 100) erreurs.push("Nom obligatoire (1 à 100 caractères).");
  if (prenom.length < 1 || prenom.length > 100) erreurs.push("Prénom obligatoire (1 à 100 caractères).");
  const fullName = `${prenom} ${nom}`.trim();
  if (fullName.length > 200) erreurs.push("Nom complet trop long (200 caractères maximum).");
  const email = (row.email ?? "").trim().toLowerCase() || null;
  if (email && (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254)) {
    erreurs.push("E-mail invalide.");
  }
  const telephone = (row.telephone ?? "").trim() || null;
  if (telephone && (telephone.length < 8 || telephone.length > 30)) {
    erreurs.push("Téléphone invalide (8 à 30 caractères).");
  }
  const birthDate = (row.naissance ?? "").trim() || null;
  if (birthDate && !dateValide(birthDate)) {
    erreurs.push("Date de naissance invalide (AAAA-MM-JJ).");
  }
  const sexeBrut = (row.sexe ?? "").trim();
  let sexe: "F" | "M" | null = null;
  if (sexeBrut !== "") {
    sexe = normalizeSexe(sexeBrut);
    if (sexe === null) erreurs.push("Sexe invalide (M ou F).");
  }
  const champ = (v: string | undefined): string | null => {
    const t = (v ?? "").trim();
    if (t === "") return null;
    if (t.length > 120) erreurs.push(`« ${t.slice(0, 20)}… » trop long (120 caractères maximum).`);
    return t;
  };
  const department = champ(row.departement);
  const fonction = champ(row.fonction);
  const poste = champ(row.poste);
  const cellGroup = champ(row.cellule);
  // Doublon dans le fichier : e-mail, ou nom complet + date de naissance.
  let doublon = false;
  if (email && vus.emails.has(email)) doublon = true;
  const cleNomNaissance = birthDate ? `${normaliserNom(fullName)}|${birthDate}` : "";
  if (cleNomNaissance !== "" && vus.nomsNaissances.has(cleNomNaissance)) doublon = true;
  if (email) vus.emails.add(email);
  if (cleNomNaissance !== "") vus.nomsNaissances.add(cleNomNaissance);
  return {
    numero, nom, prenom, fullName, telephone, email, birthDate, sexe,
    department, fonction, poste, cellGroup, erreurs, doublon,
  };
}

interface Existant {
  full_name: string;
  birth_date: string | Date | null;
  email: string | null;
}

function marquerDoublonsBase(validees: LigneValidee[], existants: Existant[]): void {
  const emailsBase = new Set(
    existants.map((e) => (e.email ?? "").toLowerCase()).filter((e) => e !== ""),
  );
  const nomsNaissancesBase = new Set(
    existants
      .filter((e) => e.birth_date)
      .map((e) => {
        const d = e.birth_date instanceof Date ? e.birth_date.toISOString().slice(0, 10) : String(e.birth_date).slice(0, 10);
        return `${normaliserNom(e.full_name)}|${d}`;
      }),
  );
  for (const l of validees) {
    if (l.erreurs.length > 0) continue;
    if (l.email && emailsBase.has(l.email)) l.doublon = true;
    if (l.birthDate && nomsNaissancesBase.has(`${normaliserNom(l.fullName)}|${l.birthDate}`)) {
      l.doublon = true;
    }
  }
}

const importBodySchema = z.object({
  nom_fichier: z.string().min(1).max(200).optional(),
  contenu_csv: z.string().min(1).max(5_000_000).optional(),
  lignes: z.array(z.record(z.string(), z.string())).max(MAX_LIGNES).optional(),
  mapping: z.record(z.string(), z.string().max(40)).optional(),
});

async function lireEntrees(
  body: z.infer<typeof importBodySchema>,
): Promise<{ colonnes: string[]; lignes: Record<string, string>[]; mapping: Record<string, Champ> } | { erreur: string }> {
  let colonnes: string[];
  let lignes: Record<string, string>[];
  if (body.lignes) {
    lignes = body.lignes;
    colonnes = [...new Set(lignes.flatMap((l) => Object.keys(l)))];
  } else if (body.contenu_csv) {
    const parsed = parseCsv(body.contenu_csv);
    colonnes = parsed.colonnes;
    lignes = parsed.lignes;
  } else {
    return { erreur: "Fournissez `contenu_csv` ou `lignes`." };
  }
  if (lignes.length === 0) return { erreur: "Aucune ligne à importer." };
  if (lignes.length > MAX_LIGNES) return { erreur: `Trop de lignes (maximum ${MAX_LIGNES}).` };
  let mapping: Record<string, Champ>;
  if (body.mapping) {
    mapping = {};
    for (const [colonne, champ] of Object.entries(body.mapping)) {
      const connu = CHAMPS.find((c) => c.champ === champ);
      if (!connu) return { erreur: `Champ inconnu dans la correspondance : « ${champ} ».` };
      mapping[colonne] = connu.champ;
    }
  } else {
    mapping = mappingAuto(colonnes);
  }
  const champsPresents = new Set(Object.values(mapping));
  if (!champsPresents.has("nom") && !champsPresents.has("nom_complet")) {
    return { erreur: "Colonne « nom » introuvable : vérifiez la correspondance des colonnes." };
  }
  if (!champsPresents.has("prenom") && !champsPresents.has("nom_complet")) {
    return { erreur: "Colonne « prénom » introuvable : vérifiez la correspondance des colonnes." };
  }
  return { colonnes, lignes, mapping };
}

async function preparer(
  db: Pool,
  churchId: string,
  body: z.infer<typeof importBodySchema>,
): Promise<
  | { erreur: string }
  | { colonnes: string[]; mapping: Record<string, Champ>; validees: LigneValidee[] }
> {
  const entrees = await lireEntrees(body);
  if ("erreur" in entrees) return entrees;
  const lignesMappees = appliquerMapping(entrees.lignes, entrees.mapping);
  const vus = { emails: new Set<string>(), nomsNaissances: new Set<string>() };
  const validees = lignesMappees.map((row, i) => validerLigne(row, i + 2, vus));
  const { rows: existants } = await db.query<Existant>(
    `SELECT full_name, birth_date, email FROM members WHERE church_id = $1`,
    [churchId],
  );
  marquerDoublonsBase(validees, existants);
  return { colonnes: entrees.colonnes, mapping: entrees.mapping, validees };
}

function resume(validees: LigneValidee[]): { valides: number; invalides: number; doublons: number } {
  return {
    valides: validees.filter((l) => l.erreurs.length === 0 && !l.doublon).length,
    invalides: validees.filter((l) => l.erreurs.length > 0).length,
    doublons: validees.filter((l) => l.erreurs.length === 0 && l.doublon).length,
  };
}

export function registerImportMembresRoutes(app: FastifyInstance, db: Pool) {
  // -- Modèle CSV téléchargeable. -------------------------------------------
  app.get(
    "/import/modele",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (_req, reply) => {
      const lignes = [
        ENTETES_MODELE.join(";"),
        LIGNE_EXEMPLE.map((v) => `"${v}"`).join(";"),
      ];
      return reply
        .header("Content-Disposition", 'attachment; filename="modele-import-fideles.csv"')
        .type("text/csv; charset=utf-8")
        .send(`\uFEFF${lignes.join("\n")}`);
    },
  );

  // -- Aperçu : valide sans rien écrire. -------------------------------------
  app.post(
    "/import/apercu",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)], bodyLimit: 5_242_880 },
    async (req, reply) => {
      const parsed = importBodySchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données d'import invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      try {
        const prep = await preparer(db, req.session.churchId, parsed.data);
        if ("erreur" in prep) {
          return reply.code(400).send({ error: "invalid_input", message: prep.erreur });
        }
        const { valides, invalides, doublons } = resume(prep.validees);
        return reply.send({
          colonnes: prep.colonnes,
          mapping: prep.mapping,
          total_lignes: prep.validees.length,
          valides,
          invalides,
          doublons,
          lignes: prep.validees.slice(0, MAX_APERCU).map((l) => ({
            ligne: l.numero,
            nom_complet: l.fullName,
            email: l.email,
            erreurs: l.erreurs,
            doublon: l.doublon,
            valide: l.erreurs.length === 0 && !l.doublon,
          })),
        });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );

  // -- Confirmation : crée les membres en transaction. -----------------------
  app.post(
    "/import/confirmer",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)], bodyLimit: 5_242_880 },
    async (req, reply) => {
      const parsed = importBodySchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          error: "invalid_input",
          message: "Données d'import invalides.",
          details: parsed.error.issues.map((i) => i.message),
        });
      }
      const client: PoolClient = await db.connect();
      try {
        const prep = await preparer(db, req.session.churchId, parsed.data);
        if ("erreur" in prep) {
          return reply.code(400).send({ error: "invalid_input", message: prep.erreur });
        }
        const { valides, invalides, doublons } = resume(prep.validees);
        const aCreer = prep.validees.filter((l) => l.erreurs.length === 0 && !l.doublon);
        const erreurs = prep.validees
          .filter((l) => l.erreurs.length > 0)
          .map((l) => ({ ligne: l.numero, nom_complet: l.fullName, erreurs: l.erreurs }));
        const crees: { id: string; matricule: string; full_name: string }[] = [];
        await client.query("BEGIN");
        try {
          for (const l of aCreer) {
            // Matricule généré (logique existante, système du permis du
            // Québec) ; on réessaie en cas de collision, comme POST /membres.
            let insere: { id: string; matricule: string } | null = null;
            let lastError: unknown = null;
            for (let attempt = 0; attempt < 3; attempt++) {
              const matricule = await generateMatricule(client, l.fullName, l.birthDate, l.sexe);
              try {
                const { rows } = await client.query<{ id: string; matricule: string }>(
                  `INSERT INTO members
                     (church_id, matricule, full_name, phone, email, birth_date, sexe,
                      department, fonction, poste, cell_group, status)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'actif')
                   RETURNING id, matricule`,
                  [
                    req.session.churchId, matricule, l.fullName, l.telephone, l.email,
                    l.birthDate, l.sexe, l.department, l.fonction, l.poste, l.cellGroup,
                  ],
                );
                insere = rows[0];
                break;
              } catch (e) {
                if ((e as { code?: string }).code === "23505") { lastError = e; continue; }
                throw e;
              }
            }
            if (!insere) throw lastError ?? new Error("Création du membre impossible.");
            crees.push({ id: insere.id, matricule: insere.matricule, full_name: l.fullName });
          }
          const statut = crees.length === 0 ? "echoue" : invalides > 0 || doublons > 0 ? "partiel" : "termine";
          const { rows: importRows } = await client.query<{ id: string }>(
            `INSERT INTO imports_membres
               (church_id, user_id, nom_fichier, total_lignes, crees, ignores, erreurs, statut)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
             RETURNING id`,
            [
              req.session.churchId,
              req.session.userId,
              parsed.data.nom_fichier ?? "import.csv",
              prep.validees.length,
              crees.length,
              doublons,
              JSON.stringify(erreurs),
              statut,
            ],
          );
          await auditLog(client, {
            churchId: req.session.churchId,
            userId: req.session.userId,
            action: "import_membres.confirme",
            details: {
              import_id: importRows[0].id,
              nom_fichier: parsed.data.nom_fichier ?? "import.csv",
              total_lignes: prep.validees.length,
              crees: crees.length,
              ignores: doublons,
              invalides,
            },
          });
          await client.query("COMMIT");
          return reply.code(201).send({
            import_id: importRows[0].id,
            statut,
            total_lignes: prep.validees.length,
            crees: crees.length,
            ignores: doublons,
            invalides,
            erreurs,
            membres: crees,
          });
        } catch (e) {
          await client.query("ROLLBACK");
          throw e;
        }
      } catch (e) {
        return dbError(reply, e);
      } finally {
        client.release();
      }
    },
  );

  // -- Historique des imports de l'église. ------------------------------------
  app.get(
    "/import/historique",
    { preHandler: [requireAuth(db), requireRole(...ADMIN)] },
    async (req, reply) => {
      try {
        const { rows } = await db.query(
          `SELECT id, nom_fichier, total_lignes, crees, ignores, erreurs, statut, created_at
             FROM imports_membres WHERE church_id = $1 ORDER BY created_at DESC LIMIT 20`,
          [req.session.churchId],
        );
        return reply.send({ imports: rows });
      } catch (e) {
        return dbError(reply, e);
      }
    },
  );
}
