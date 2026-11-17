// Script ponctuel : crée le compte super admin de la Plateforme.
// Usage (une seule fois, depuis Render) :
//   node scripts/creer-super-admin.mjs '<hash_argon2id>'
// Le hash n'est jamais écrit dans ce fichier ni dans le dépôt.
// Variables : DATABASE_URL (déjà définie sur Render).
// Idempotent : relancer le script ne crée pas de doublon.

import pg from 'pg';

const { Client } = pg;

const EMAIL = 'axelanibe@outlook.fr';
const NOM = 'Axel Maurice Anibe';
const CODE_EGLISE_MERE = 'ESC-XZ2SCA';

const hash = process.argv[2];
if (!hash || !hash.startsWith('$argon2id$')) {
  console.error('Usage : node scripts/creer-super-admin.mjs \'<hash_argon2id>\'');
  process.exit(2);
}

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error('DATABASE_URL manquante');
  process.exit(2);
}

const client = new Client({ connectionString, ssl: { rejectUnauthorized: false } });
await client.connect();

const r1 = await client.query(
  `INSERT INTO users (email, password_hash, full_name, failed_logins, locked_until)
   VALUES ($1, $2, $3, 0, NULL)
   ON CONFLICT (email) DO UPDATE SET
     password_hash = EXCLUDED.password_hash,
     failed_logins = 0,
     locked_until = NULL,
     token_version = users.token_version + 1
   RETURNING id, email`,
  [EMAIL, hash, NOM],
);
console.log('utilisateur :', JSON.stringify(r1.rows));

const r2 = await client.query(
  `INSERT INTO church_users (user_id, church_id, role)
   SELECT u.id, c.id, 'super_admin'
   FROM users u JOIN churches c ON c.code = $1
   WHERE lower(u.email) = $2
   ON CONFLICT (user_id, church_id) DO UPDATE SET role = 'super_admin'
   RETURNING user_id, church_id, role`,
  [CODE_EGLISE_MERE, EMAIL],
);
console.log('rôle :', JSON.stringify(r2.rows));

const r3 = await client.query(
  `SELECT u.email, u.full_name, cu.role, c.code, c.name
   FROM users u
   JOIN church_users cu ON cu.user_id = u.id
   JOIN churches c ON c.id = cu.church_id
   WHERE lower(u.email) = $1`,
  [EMAIL],
);
console.log('vérification :', JSON.stringify(r3.rows));

await client.end();
console.log('super admin créé');
