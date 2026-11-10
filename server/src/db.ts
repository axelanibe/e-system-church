import { Pool } from "pg";

let pool: Pool | null = null;

/**
 * Pool pg paresseux : lit DATABASE_URL au premier appel, donc après le
 * chargement de dotenv par le point d'entrée (les imports ESM sont évalués
 * avant le corps du module qui appelle config()).
 */
export function getDb(): Pool {
  if (!pool) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error(
        "DATABASE_URL manquante : copier server/.env.example vers server/.env et la remplir.",
      );
    }
    pool = new Pool({ connectionString });
  }
  return pool;
}
