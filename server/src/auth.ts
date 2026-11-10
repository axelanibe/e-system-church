import { randomBytes } from "node:crypto";
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
  name: string;
  parent_church_id: string | null;
  status: string;
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
      reason: "invalid_input" | "invalid_credentials" | "locked" | "invalid_church";
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

const verifyPassword = (hash: string, password: string): Promise<boolean> =>
  argon2.verify(hash, password).catch(() => false);

/** Hachage jetable pour égaliser le temps de réponse quand le compte n'existe pas. */
let dummyHash: Promise<string> | null = null;
const getDummyHash = () =>
  (dummyHash ??= argon2.hash(randomBytes(16).toString("hex"), { type: argon2.argon2id }));

function signToken(payload: { sub: string; churchId: string; role: string }, channel: Channel): string {
  return jwt.sign(payload, getJwtSecret(), { expiresIn: SESSION_TTL[channel] });
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

    // Code d'invitation unique (réessai en cas de collision).
    let code = "";
    for (let attempt = 0; attempt < 5; attempt++) {
      code = generateChurchCode();
      const clash = await client.query(`SELECT 1 FROM churches WHERE code = $1`, [code]);
      if (clash.rowCount === 0) break;
      if (attempt === 4) throw new Error("Impossible de générer un code d'église unique.");
    }

    // Inscription libre : l'église naît ACTIVE. Le parent n'est rattaché
    // qu'après acceptation de la demande (voir rattachements.ts).
    const { rows: churchRows } = await client.query<ChurchSummary>(
      `INSERT INTO churches (code, name, city, phone, email, status)
       VALUES ($1, $2, $3, $4, $5, 'active')
       RETURNING id, code, name, parent_church_id, status`,
      [code, eglise.name, eglise.city, eglise.phone ?? null, eglise.email ?? null],
    );
    const church = churchRows[0];

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

    const token = signToken({ sub: user.id, churchId: church.id, role: "admin_eglise" }, channel);
    return { ok: true, token, user, church, rattachement };
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
    `SELECT id, password_hash, failed_logins, locked_until, full_name, email
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

  const passwordOk = await verifyPassword(user.password_hash as string, password);
  if (!passwordOk) return recordFailure(db, user);

  await db.query(`UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = $1`, [user.id]);

  const { rows: memberships } = await db.query(
    `SELECT cu.role, c.id, c.code, c.name, c.parent_church_id, c.status
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
      name: m.name as string,
      parent_church_id: m.parent_church_id as string | null,
      status: m.status as string,
    },
  }));

  let chosen: Membership | undefined = eglises[0];
  if (church_id) {
    chosen = eglises.find((e) => e.church.id === church_id);
    if (!chosen) return { ok: false, reason: "invalid_church" };
  }
  if (!chosen) {
    // Compte sans église (ne devrait pas arriver en MVP) : pas de session d'église.
    return { ok: false, reason: "invalid_church" };
  }

  const token = signToken(
    { sub: user.id as string, churchId: chosen.church.id, role: chosen.role },
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

async function recordFailure(
  db: Pool,
  user: { id: string; failed_logins: number },
): Promise<LoginResult> {
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
  return lock ? { ok: false, reason: "locked" } : { ok: false, reason: "invalid_credentials" };
}
