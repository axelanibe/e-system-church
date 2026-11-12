import type { Pool, PoolClient } from "pg";

/**
 * Postes de dépense prévisibles, pré-créés pour chaque église.
 *
 * Correspondance avec le plan comptable d'Axel (12 novembre 2026) :
 * - Électricité, Eau → 02 Infrastructures (récurrentes)
 * - Transports → 07 Transport et missions (récurrente)
 * - Cas sociaux → 08 Action sociale (ponctuelle)
 * - Location de sono, Achat d'équipement, Maintenance,
 *   Location d'équipement → 03 Culte et spiritualité
 *   (Maintenance récurrente, les trois autres ponctuelles)
 *
 * Un seul endroit définit la liste : la migration 031 l'applique aux
 * églises existantes, `seedPostesPrevisibles` aux nouvelles églises
 * (inscription dans auth.ts, création d'annexe dans eglises.ts).
 * Un poste du même nom déjà créé à la main n'est pas dupliqué
 * (UNIQUE church_id, nom).
 */

export interface PostePrevisible {
  nom: string;
  codeCategorie: string;
  recurrente: boolean;
}

export const POSTES_PREVISIBLES: PostePrevisible[] = [
  { nom: "Électricité", codeCategorie: "02", recurrente: true },
  { nom: "Eau", codeCategorie: "02", recurrente: true },
  { nom: "Transports", codeCategorie: "07", recurrente: true },
  { nom: "Cas sociaux", codeCategorie: "08", recurrente: false },
  { nom: "Location de sono", codeCategorie: "03", recurrente: false },
  { nom: "Achat d'équipement", codeCategorie: "03", recurrente: false },
  { nom: "Maintenance", codeCategorie: "03", recurrente: true },
  { nom: "Location d'équipement", codeCategorie: "03", recurrente: false },
];

/** Crée les huit postes pour une église, sans doublon. */
export async function seedPostesPrevisibles(
  client: Pool | PoolClient,
  churchId: string,
): Promise<void> {
  for (const poste of POSTES_PREVISIBLES) {
    await client.query(
      `INSERT INTO postes_budgetaires (church_id, nom, categorie, categorie_id, est_recurrente)
       SELECT $1, $2, 'depense', id, $3 FROM categories_depenses WHERE code = $4
       ON CONFLICT (church_id, nom) DO NOTHING`,
      [churchId, poste.nom, poste.recurrente, poste.codeCategorie],
    );
  }
}
