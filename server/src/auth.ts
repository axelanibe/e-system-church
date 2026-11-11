import { createHash, randomBytes } from "node:crypto";
import argon2 from "argon2";
import jwt from "jsonwebtoken";
import type { Pool, PoolClient } from "pg";
import { z } from "zod";

// ---------------------------------------------------------------------------
// Constantes (mêmes règles que SanteCI Connect)
// ---------------------------------------------------------------------------
export const MAX_FAILED_LOGINS = 5;
export const LOCK_MINUTES = 15;
/** Durée de vie du JWT : 30 min sur le web, 2 h sur mobile. */
const SESSION_TTL = { web: "30m", mobile: "2h" } as const;

export type Channel = keyof typeof SESSION_TTL;

// ---------------------------------------------------------------------------
// Schémas zod
// ---------------------------------------------------------------------------
export const registerSchema = z.object({
  eglise: z.object({
    name: z.string().min(2).max(200),
    city: z.string().min(2).max(120),
    phone: z.string().min(8).max(30).optional(),
    email: z.string().email().max(254).optional(),
    /**
     * Code d'invitation d'une église mère à rejoindre. L'église est alors
     * créée avec un rattachement EN ATTENTE : elle ne devient sous-église
     * qu'une fois la demande acceptée par la mère (décision de Bouf :
     * inscription libre, rattachement validé par la mère).
     */
    parent_code: z.string().min(4).max(20).optional(),
  }),
  admin: z.object({
    full_name: z.string().min(2).max(200),
    email: z.string().email().max(254),
    phone: z.string().min(8).max(30).optional(),
    password: z.string().min(8).max(256),
  }),
  channel: z.enum(["web", "mobile"]).default("web"),
});

export const loginSchema = z.object({
  email: z.string().email().max(254),
  password: z.string().min(1).max(256),
  channel: z.enum(["web", "mobile"]).default("web"),
  /** Choisir parmi ses églises (un utilisateur peut appartenir à plusieurs). */
  church_id: z.string().uuid().optional(),
});

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
export interface ChurchSummary {
  id: string;
  code: string;
  /** Code fidèle (ESC-F-…) : les membres l'utilisent pour s'inscrire
   *  dans cette église. Absent des anciennes réponses (avant la 007). */
  code_fidele?: string | null;
  name: string;
  parent_church_id: string | null;
  status: string;
  /** Module 13 — identité visuelle et présentation. */
  logo_url?: string | null;
  couleur_principale?: string | null;
  devise?: string;
  fuseau_horaire?: string;
  description?: string | null;
  horaires_cultes?: unknown;
}

export interface Membership {
  church: ChurchSummary;
  role: string;
}

export type LoginResult =
  | {
      ok: true;
      token: string;
      user: { id: string; full_name: string; email: string };
      church: ChurchSummary & { role: string };
      eglises: Membership[];
    }
  | {
      ok: false;
      reason:
        | "invalid_input"
        | "invalid_credentials"
        | "locked"
        | "invalid_church"
        | "password_not_set"
        | "no_church";
    };

// ---------------------------------------------------------------------------
// Secrets et hachage
// ---------------------------------------------------------------------------
export function getJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error("JWT_SECRET manquant ou trop court (32 caractères minimum).");
  }
  return secret;
}

export const hashPassword = (password: string): Promise<string> =>
  argon2.hash(password, { type: argon2.argon2id });

export const verifyPassword = (hash: string, password: string): Promise<boolean> =>
  argon2.verify(hash, password).catch(() => false);

/** Hachage jetable pour égaliser le temps de réponse quand le compte n'existe pas. */
let dummyHash: Promise<string> | null = null;
const getDummyHash = () =>
  (dummyHash ??= argon2.hash(randomBytes(16).toString("hex"), { type: argon2.argon2id }));

function signToken(
  payload: { sub: string; churchId: string; role: string; v: number },
  channel: Channel,
): string {
  return jwt.sign(payload, getJwtSecret(), { expiresIn: SESSION_TTL[channel] });
}

/**
 * Module 13 — changement d'église active : émet un nouveau JWT pour une
 * autre église de l'utilisateur (sélecteur d'église), sans ressaisir le
 * mot de passe. Le canal (web / mobile) fixe la durée du jeton.
 */
export async function issueTokenForChurch(
  db: Pool,
  userId: string,
  churchId: string,
  channel: Channel = "mobile",
): Promise<
  | { ok: true; token: string; church: ChurchSummary & { role: string } }
  | { ok: false; reason: "invalid_church" }
> {
  const { rows } = await db.query(
    `SELECT cu.role, c.id, c.code, c.code_fidele, c.name, c.parent_church_id, c.status,
            c.logo_url, c.couleur_principale, c.devise, c.fuseau_horaire,
            c.description, c.horaires_cultes
       FROM church_users cu
       JOIN churches c ON c.id = cu.church_id
      WHERE cu.user_id = $1 AND cu.church_id = $2`,
    [userId, churchId],
  );
  if (rows.length === 0) return { ok: false, reason: "invalid_church" };
  const m = rows[0];
  const { rows: versionRows } = await db.query<{ token_version: number }>(
    `SELECT token_version FROM users WHERE id = $1`,
    [userId],
  );
  const tokenVersion = versionRows[0]?.token_version ?? 0;
  const church: ChurchSummary & { role: string } = {
    id: m.id as string,
    code: m.code as string,
    code_fidele: m.code_fidele as string | null,
    name: m.name as string,
    parent_church_id: m.parent_church_id as string | null,
    status: m.status as string,
    role: m.role as string,
    logo_url: m.logo_url as string | null,
    couleur_principale: m.couleur_principale as string | null,
    devise: m.devise as string,
    fuseau_horaire: m.fuseau_horaire as string,
    description: m.description as string | null,
    horaires_cultes: m.horaires_cultes as unknown,
  };
  const token = signToken(
    { sub: userId, churchId, role: church.role, v: tokenVersion },
    channel,
  );
  await auditLog(db, {
    churchId,
    userId,
    action: "auth.eglise_active_changee",
    details: { channel },
  });
  return { ok: true, token, church };
}

// ---------------------------------------------------------------------------
// Codes et matricules
// ---------------------------------------------------------------------------
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/** Code d'invitation unique par église, ex. ESC-K7M2QX. */
export function generateChurchCode(): string {
  let suffix = "";
  for (let i = 0; i < 6; i++) suffix += CODE_ALPHABET[randomBytes(1)[0] % CODE_ALPHABET.length];
  return `ESC-${suffix}`;
}

/**
 * Code fidèle unique par église, ex. ESC-F-K7M2QX : les membres
 * l'utilisent pour s'inscrire dans la bonne église (le code désigne une
 * seule église, sans ambiguïté). Préfixe distinct du code de tutelle
 * (`ESC-…`, utilisé par les églises secondaires pour se rattacher).
 */
export function generateFideleCode(): string {
  let suffix = "";
  for (let i = 0; i < 6; i++) suffix += CODE_ALPHABET[randomBytes(1)[0] % CODE_ALPHABET.length];
  return `ESC-F-${suffix}`;
}

/**
 * Matricule unique PAR église, séquentiel (M-0001, M-0002…).
 * La contrainte UNIQUE (church_id, matricule) protège des courses :
 * l'appelant réessaie en cas de conflit.
 */
export async function generateMatricule(client: Pool | PoolClient, churchId: string): Promise<string> {
  const { rows } = await client.query<{ n: string }>(
    `SELECT count(*)::text AS n FROM members WHERE church_id = $1`,
    [churchId],
  );
  const next = Number(rows[0]?.n ?? 0) + 1;
  return `M-${String(next).padStart(4, "0")}`;
}

// ---------------------------------------------------------------------------
// Journal d'audit (table audit_logs : church_id, user_id, action, details)
// ---------------------------------------------------------------------------
export async function auditLog(
  client: Pool | PoolClient,
  opts: { churchId: string | null; userId: string | null; action: string; details?: unknown },
): Promise<void> {
  await client.query(
    `INSERT INTO audit_logs (church_id, user_id, action, details) VALUES ($1, $2, $3, $4)`,
    [opts.churchId, opts.userId, opts.action, JSON.stringify(opts.details ?? {})],
  );
}

// ---------------------------------------------------------------------------
// Inscription : crée l'église + son admin (transaction). Décisions de Bouf :
// inscription libre (église créée ACTIVE) ; rattachement à une mère validé
// par la mère ; dons sur le compte de chaque église (aucune centralisation).
// ---------------------------------------------------------------------------
export async function registerChurch(
  db: Pool,
  rawInput: unknown,
): Promise<
  | { ok: true; token: string; user: { id: string; full_name: string; email: string }; church: ChurchSummary; rattachement: { id: string; status: string } | null }
  | { ok: false; reason: "invalid_input" | "email_taken" | "invalid_parent_code" }
> {
  const parsed = registerSchema.safeParse(rawInput);
  if (!parsed.success) return { ok: false, reason: "invalid_input" };
  const { eglise, admin, channel } = parsed.data;

  const client = await db.connect();
  try {
    await client.query("BEGIN");

    const existing = await client.query(`SELECT id FROM users WHERE email = $1`, [admin.email]);
    if (existing.rowCount && existing.rowCount > 0) {
      await client.query("ROLLBACK");
      return { ok: false, reason: "email_taken" };
    }

    // Mère à rejoindre, le cas échéant (par code d'invitation).
    let parent: { id: string } | null = null;
    if (eglise.parent_code) {
      const { rows } = await client.query<{ id: string }>(
        `SELECT id FROM churches WHERE code = $1 AND status = 'active'`,
        [eglise.parent_code],
      );
      parent = rows[0] ?? null;
      if (!parent) {
        await client.query("ROLLBACK");
        return { ok: false, reason: "invalid_parent_code" };
      }
    }

    // Deux codes uniques (réessai en cas de collision) : le code de
    // tutelle (ESC-…) pour rattacher une sous-église, et le code fidèle
    // (ESC-F-…) pour inscrire les membres dans la bonne église.
    let code = "";
    for (let attempt = 0; attempt < 5; attempt++) {
      code = generateChurchCode();
      const clash = await client.query(`SELECT 1 FROM churches WHERE code = $1`, [code]);
      if (clash.rowCount === 0) break;
      if (attempt === 4) throw new Error("Impossible de générer un code d'église unique.");
    }
    let codeFidele = "";
    for (let attempt = 0; attempt < 5; attempt++) {
      codeFidele = generateFideleCode();
      const clash = await client.query(`SELECT 1 FROM churches WHERE code_fidele = $1`, [codeFidele]);
      if (clash.rowCount === 0) break;
      if (attempt === 4) throw new Error("Impossible de générer un code fidèle unique.");
    }

    // Inscription libre : l'église naît ACTIVE. Le parent n'est rattaché
    // qu'après acceptation de la demande (voir rattachements.ts).
    const { rows: churchRows } = await client.query<ChurchSummary>(
      `INSERT INTO churches (code, code_fidele, name, city, phone, email, status)
       VALUES ($1, $2, $3, $4, $5, $6, 'active')
       RETURNING id, code, code_fidele, name, parent_church_id, status,
                 logo_url, couleur_principale, devise, fuseau_horaire,
                 description, horaires_cultes`,
      [code, codeFidele, eglise.name, eglise.city, eglise.phone ?? null, eglise.email ?? null],
    );
    const church = churchRows[0];

    // Départements, fonctions et postes pré-enregistrés (listes par défaut).
    await seedCatalogues(client, church.id);

    const passwordHash = await hashPassword(admin.password);
    const { rows: userRows } = await client.query<{ id: string; full_name: string; email: string }>(
      `INSERT INTO users (email, password_hash, full_name, phone)
       VALUES ($1, $2, $3, $4) RETURNING id, full_name, email`,
      [admin.email, passwordHash, admin.full_name, admin.phone ?? null],
    );
    const user = userRows[0];

    await client.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'admin_eglise')`,
      [user.id, church.id],
    );

    let rattachement: { id: string; status: string } | null = null;
    if (parent) {
      const { rows } = await client.query<{ id: string; status: string }>(
        `INSERT INTO rattachements (church_id, parent_church_id, status)
         VALUES ($1, $2, 'en_attente') RETURNING id, status`,
        [church.id, parent.id],
      );
      rattachement = rows[0];
    }

    await auditLog(client, {
      churchId: church.id,
      userId: user.id,
      action: "eglise.inscrite",
      details: { church_name: church.name, rattachement_demande: rattachement !== null },
    });

    await client.query("COMMIT");

    const token = signToken(
      { sub: user.id, churchId: church.id, role: "admin_eglise", v: 0 },
      channel,
    );
    return { ok: true, token, user, church, rattachement };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw e;
  } finally {
    client.release();
  }
}

/**
 * 16 départements de départ, en 4 pôles (document d'architecture, §3).
 * Catalogue de départ, pas une structure rigide : modifiable ensuite par
 * l'administrateur. Le pôle est conservé en description du département.
 */
export const DEPARTEMENTS_DEFAUT: ReadonlyArray<{ nom: string; pole: string }> = [
  { nom: "Prière et intercession", pole: "Spiritualité et ministère" },
  { nom: "Évangélisation et missions", pole: "Spiritualité et ministère" },
  { nom: "Formation biblique", pole: "Spiritualité et ministère" },
  { nom: "Louange et adoration", pole: "Spiritualité et ministère" },
  { nom: "Accompagnement pastoral", pole: "Spiritualité et ministère" },
  { nom: "Administration générale", pole: "Administration et gestion" },
  { nom: "Finances et comptabilité", pole: "Administration et gestion" },
  { nom: "Ressources humaines", pole: "Administration et gestion" },
  { nom: "Logistique et patrimoine", pole: "Administration et gestion" },
  { nom: "Protocole, accueil et sécurité", pole: "Administration et gestion" },
  { nom: "Communication et médias", pole: "Communication et développement" },
  { nom: "Informatique et numérique", pole: "Communication et développement" },
  { nom: "Événementiel", pole: "Communication et développement" },
  { nom: "Jeunesse et enfants", pole: "Communauté et action sociale" },
  { nom: "Femmes, hommes et familles", pole: "Communauté et action sociale" },
  { nom: "Action sociale et solidarité", pole: "Communauté et action sociale" },
];

/**
 * Fonctions habituelles dans les églises (liste d'Axel, pas celle de
 * CONNEXION PROPHÉTIQUE). « Aucun » veut dire sans fonction précise.
 */
export const FONCTIONS_DEFAUT = [
  "Pasteur",
  "Ancien",
  "Diacre",
  "Diaconesse",
  "Intercesseur",
  "Chantre",
  "Responsable",
  "Secrétaire",
  "Trésorier",
  "Leader",
  "Membre",
  "Aucun",
] as const;

/** Postes d'exemple (document d'architecture, §4). */
export const POSTES_DEFAUT = [
  "Directeur de département",
  "Directeur adjoint",
  "Chef de service ou d'équipe",
  "Responsable d'activité",
  "Collaborateur ou bénévole",
] as const;

/**
 * Amorce les départements, les fonctions et les postes d'une église qui
 * vient d'être créée (listes par défaut, modifiables ensuite par
 * l'administrateur). Idempotente (ON CONFLICT DO NOTHING).
 */
export async function seedCatalogues(
  client: Pool | PoolClient,
  churchId: string,
): Promise<void> {
  for (const d of DEPARTEMENTS_DEFAUT) {
    await client.query(
      `INSERT INTO departements (church_id, nom, description) VALUES ($1, $2, $3)
       ON CONFLICT (church_id, nom) DO NOTHING`,
      [churchId, d.nom, `Pôle : ${d.pole}`],
    );
  }
  for (const nom of FONCTIONS_DEFAUT) {
    await client.query(
      `INSERT INTO fonctions (church_id, nom) VALUES ($1, $2)
       ON CONFLICT (church_id, nom) DO NOTHING`,
      [churchId, nom],
    );
  }
  for (const nom of POSTES_DEFAUT) {
    await client.query(
      `INSERT INTO postes (church_id, nom) VALUES ($1, $2)
       ON CONFLICT (church_id, nom) DO NOTHING`,
      [churchId, nom],
    );
  }
}

export const inscriptionMembreSchema = z.object({
  nom_prenom: z.string().min(2).max(200),
  email: z.string().email().max(254),
  telephone: z.string().min(8).max(30),
  mot_de_passe: z.string().min(8).max(256),
  /** Code fidèle de l'église (ESC-F-…), il fait foi : aucune validation. */
  code_eglise: z.string().min(4).max(20),
  /** Département et fonction choisis à l'inscription (facultatifs). */
  department: z.string().min(2).max(120).optional(),
  fonction: z.string().min(2).max(120).optional(),
  channel: z.enum(["web", "mobile"]).default("web"),
});

export type InscriptionMembreResult =
  | {
      ok: true;
      token: string;
      user: { id: string; full_name: string; email: string };
      church: ChurchSummary & { role: string };
      eglises: Membership[];
      matricule: string;
    }
  | { ok: false; reason: "invalid_input" | "invalid_code" | "email_taken" };

/**
 * Inscription d'un membre par code fidèle, sans validation (décision de
 * Bouf, 11 nov. 2026) : le code fait foi. Comme CONNEXION PROPHÉTIQUE,
 * le membre saisit nom et prénom, e-mail, téléphone, mot de passe et le
 * code fidèle de son église à la place du matricule. Le code fidèle
 * (ESC-F-…) désigne une seule église, sans ambiguïté — le code de
 * tutelle (ESC-…) ne sert qu'aux églises qui se rattachent à une mère.
 * Le matricule est attribué automatiquement (unique par église), la fiche
 * membre et la carte sont créées tout de suite, le compte est lié
 * immédiatement.
 */
export async function inscriptionMembreParCode(
  db: Pool,
  rawInput: unknown,
): Promise<InscriptionMembreResult> {
  const parsed = inscriptionMembreSchema.safeParse(rawInput);
  if (!parsed.success) return { ok: false, reason: "invalid_input" };
  const { nom_prenom, email, telephone, mot_de_passe, code_eglise, department, fonction, channel } = parsed.data;
  const emailNorm = email.toLowerCase();
  const codeNorm = code_eglise.trim().toUpperCase();
  // « Aucun » veut dire sans fonction précise : on ne stocke rien, la
  // carte affichera alors « Membre ».
  const fonctionNorm = fonction && fonction !== "Aucun" ? fonction : null;

  const client = await db.connect();
  try {
    await client.query("BEGIN");

    const { rows: churchRows } = await client.query(
      `SELECT id, code, code_fidele, name, parent_church_id, status,
              logo_url, couleur_principale, devise, fuseau_horaire,
              description, horaires_cultes
         FROM churches WHERE upper(code_fidele) = $1 AND status = 'active'`,
      [codeNorm],
    );
    const church = churchRows[0];
    if (!church) {
      await client.query("ROLLBACK");
      return { ok: false, reason: "invalid_code" };
    }

    const emailPris = await client.query(
      `SELECT id FROM users WHERE lower(email) = $1`,
      [emailNorm],
    );
    if (emailPris.rowCount && emailPris.rowCount > 0) {
      await client.query("ROLLBACK");
      return { ok: false, reason: "email_taken" };
    }

    const passwordHash = await hashPassword(mot_de_passe);
    const { rows: userRows } = await client.query<{ id: string }>(
      `INSERT INTO users (email, password_hash, full_name, phone)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [emailNorm, passwordHash, nom_prenom, telephone],
    );
    const userId = userRows[0].id;

    // Matricule automatique, unique par église. En cas de course sur le
    // compteur, la contrainte UNIQUE déclenche un réessai (SAVEPOINT, la
    // transaction n'est pas perdue).
    let memberId = "";
    let matricule = "";
    for (let attempt = 0; attempt < 5; attempt++) {
      matricule = await generateMatricule(client, church.id as string);
      await client.query("SAVEPOINT matricule");
      try {
        const { rows: memberRows } = await client.query<{ id: string }>(
          `INSERT INTO members (church_id, user_id, matricule, full_name, phone, email, department, fonction, status)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'actif') RETURNING id`,
          [church.id, userId, matricule, nom_prenom, telephone, emailNorm, department ?? null, fonctionNorm],
        );
        memberId = memberRows[0].id;
        await client.query("RELEASE SAVEPOINT matricule");
        break;
      } catch (e) {
        await client.query("ROLLBACK TO SAVEPOINT matricule");
        await client.query("RELEASE SAVEPOINT matricule");
        if ((e as { code?: string }).code !== "23505" || attempt === 4) throw e;
      }
    }

    await client.query(
      `INSERT INTO church_users (user_id, church_id, role) VALUES ($1, $2, 'membre')`,
      [userId, church.id],
    );
    await client.query(`UPDATE users SET member_id = $2 WHERE id = $1`, [userId, memberId]);
    await auditLog(client, {
      churchId: church.id as string,
      userId,
      action: "fidele.inscrit_par_code",
      details: { member_id: memberId, matricule, department: department ?? null, fonction: fonctionNorm },
    });
    await client.query("COMMIT");

    // Connexion immédiate (même réponse que /auth/login, + matricule).
    const result = await login(db, { email: emailNorm, password: mot_de_passe, channel });
    if (!result.ok) {
      throw new Error("Compte créé, mais la connexion a échoué.");
    }
    return {
      ok: true,
      token: result.token,
      user: result.user,
      church: result.church,
      eglises: result.eglises,
      matricule,
    };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw e;
  } finally {
    client.release();
  }
}

// ---------------------------------------------------------------------------
// Connexion : argon2id + verrouillage après 5 échecs → 15 min.
// Le JWT embarque l'église choisie (churchId) et son rôle dans cette église.
// ---------------------------------------------------------------------------
export async function login(db: Pool, rawInput: unknown): Promise<LoginResult> {
  const parsed = loginSchema.safeParse(rawInput);
  if (!parsed.success) return { ok: false, reason: "invalid_input" };
  const { email, password, channel, church_id } = parsed.data;

  const { rows } = await db.query(
    `SELECT id, password_hash, failed_logins, locked_until, full_name, email,
            token_version
       FROM users WHERE email = $1 LIMIT 1`,
    [email],
  );
  const user = rows[0];

  if (!user) {
    await verifyPassword(await getDummyHash(), password);
    return { ok: false, reason: "invalid_credentials" };
  }
  if (user.locked_until && new Date(user.locked_until) > new Date()) {
    return { ok: false, reason: "locked" };
  }
  // Compte créé par invitation, mot de passe pas encore initialisé :
  // la connexion est refusée (sans compter d'échec) et l'utilisateur est
  // renvoyé vers le lien reçu.
  if (!user.password_hash) {
    return { ok: false, reason: "password_not_set" };
  }

  const passwordOk = await verifyPassword(user.password_hash as string, password);
  if (!passwordOk) return recordFailure(db, user);

  await db.query(`UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = $1`, [user.id]);

  const { rows: memberships } = await db.query(
    `SELECT cu.role, c.id, c.code, c.code_fidele, c.name, c.parent_church_id, c.status,
            c.logo_url, c.couleur_principale, c.devise, c.fuseau_horaire,
            c.description, c.horaires_cultes
       FROM church_users cu
       JOIN churches c ON c.id = cu.church_id
      WHERE cu.user_id = $1
      ORDER BY cu.created_at ASC`,
    [user.id],
  );
  const eglises: Membership[] = memberships.map((m) => ({
    role: m.role as string,
    church: {
      id: m.id as string,
      code: m.code as string,
      code_fidele: m.code_fidele as string | null,
      name: m.name as string,
      parent_church_id: m.parent_church_id as string | null,
      status: m.status as string,
      logo_url: m.logo_url as string | null,
      couleur_principale: m.couleur_principale as string | null,
      devise: m.devise as string,
      fuseau_horaire: m.fuseau_horaire as string,
      description: m.description as string | null,
      horaires_cultes: m.horaires_cultes as unknown,
    },
  }));

  let chosen: Membership | undefined = eglises[0];
  if (church_id) {
    chosen = eglises.find((e) => e.church.id === church_id);
    if (!chosen) return { ok: false, reason: "invalid_church" };
  }
  if (!chosen) {
    // Compte sans église : fidèle en attente de validation de sa liaison,
    // ou compte orphelin. Il ne peut pas se connecter tant qu'aucune
    // église ne l'a rattaché.
    return { ok: false, reason: "no_church" };
  }

  const token = signToken(
    {
      sub: user.id as string,
      churchId: chosen.church.id,
      role: chosen.role,
      v: (user.token_version as number) ?? 0,
    },
    channel,
  );
  await auditLog(db, {
    churchId: chosen.church.id,
    userId: user.id as string,
    action: "auth.login",
    details: { channel },
  });

  return {
    ok: true,
    token,
    user: { id: user.id as string, full_name: user.full_name as string, email: user.email as string },
    church: { ...chosen.church, role: chosen.role },
    eglises,
  };
}

/**
 * Un échec d'authentification : compteur +1, verrouillage 15 min au 5e
 * échec (même règle que le login). Renvoie vrai si le compte vient d'être
 * verrouillé. Utilisé par le login et par les tentatives sur les jetons
 * (réinitialisation / initialisation).
 */
export async function recordFailedAttempt(
  db: Pool,
  user: { id: string; failed_logins: number },
): Promise<boolean> {
  const attempts = user.failed_logins + 1;
  const lock = attempts >= MAX_FAILED_LOGINS;
  await db.query(
    `UPDATE users
        SET failed_logins = $2,
            locked_until = CASE WHEN $3 THEN now() + make_interval(mins => $4) ELSE NULL END
      WHERE id = $1`,
    [user.id, lock ? 0 : attempts, lock, LOCK_MINUTES],
  );
  await auditLog(db, {
    churchId: null,
    userId: user.id,
    action: "auth.login_failed",
    details: { locked: lock },
  });
  return lock;
}

async function recordFailure(
  db: Pool,
  user: { id: string; failed_logins: number },
): Promise<LoginResult> {
  const lock = await recordFailedAttempt(db, user);
  return lock ? { ok: false, reason: "locked" } : { ok: false, reason: "invalid_credentials" };
}

// ---------------------------------------------------------------------------
// Jetons à usage unique (modules 15-16) : invitation et réinitialisation.
// Seul le hash SHA-256 est stocké ; le jeton brut (32 octets aléatoires,
// hex) n'existe qu'au moment de sa création.
// ---------------------------------------------------------------------------
export type AuthTokenType = "invitation" | "reinitialisation";

export const TOKEN_TTL_HOURS: Record<AuthTokenType, number> = {
  invitation: 24 * 7,
  reinitialisation: 24,
};

/** SHA-256 hex d'un jeton brut (ce qui est stocké en base). */
export function hashAuthToken(rawToken: string): string {
  return createHash("sha256").update(rawToken).digest("hex");
}

/** Crée un jeton et le stocke hashé. Renvoie le jeton brut (à transmettre une seule fois). */
export async function createAuthToken(
  db: Pool | PoolClient,
  userId: string,
  type: AuthTokenType,
  ttlHours: number = TOKEN_TTL_HOURS[type],
): Promise<{ token: string; expiresAt: Date }> {
  const raw = randomBytes(32).toString("hex");
  const { rows } = await db.query<{ expires_at: Date }>(
    `INSERT INTO auth_tokens (user_id, token_hash, type, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(hours => $4))
     RETURNING expires_at`,
    [userId, hashAuthToken(raw), type, ttlHours],
  );
  return { token: raw, expiresAt: rows[0].expires_at };
}

export type TokenCheck =
  | { ok: true; tokenId: string; userId: string }
  | { ok: false; reason: "introuvable" | "type" | "expire" | "utilise"; userId?: string };

/** Vérifie un jeton brut : hash, type, expiration, usage unique. */
export async function checkAuthToken(
  db: Pool,
  rawToken: string,
  type: AuthTokenType,
): Promise<TokenCheck> {
  const { rows } = await db.query(
    `SELECT id, user_id, type, expires_at, used_at
       FROM auth_tokens WHERE token_hash = $1`,
    [hashAuthToken(rawToken)],
  );
  const t = rows[0];
  if (!t) return { ok: false, reason: "introuvable" };
  if (t.type !== type) return { ok: false, reason: "type", userId: t.user_id as string };
  if (t.used_at) return { ok: false, reason: "utilise", userId: t.user_id as string };
  if (new Date(t.expires_at as string) <= new Date()) {
    return { ok: false, reason: "expire", userId: t.user_id as string };
  }
  return { ok: true, tokenId: t.id as string, userId: t.user_id as string };
}

/** Marque un jeton comme utilisé (usage unique). */
export async function consumeAuthToken(db: Pool, tokenId: string): Promise<void> {
  await db.query(`UPDATE auth_tokens SET used_at = now() WHERE id = $1`, [tokenId]);
}

/**
 * Invalide toutes les sessions d'un utilisateur : les JWT émis avant
 * (version `v` inférieure) sont refusés par requireAuth.
 */
export async function invalidateSessions(db: Pool, userId: string): Promise<void> {
  await db.query(`UPDATE users SET token_version = token_version + 1 WHERE id = $1`, [userId]);
}

/**
 * Définit (ou redéfinit) le mot de passe : hash argon2id, compteurs
 * d'échecs remis à zéro, sessions existantes invalidées.
 */
export async function setPassword(db: Pool, userId: string, password: string): Promise<void> {
  const hash = await hashPassword(password);
  await db.query(
    `UPDATE users
        SET password_hash = $2, failed_logins = 0, locked_until = NULL,
            token_version = token_version + 1, updated_at = now()
      WHERE id = $1`,
    [userId, hash],
  );
}
