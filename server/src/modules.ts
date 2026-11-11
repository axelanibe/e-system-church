import type { FastifyReply, FastifyRequest } from "fastify";
import type { Pool } from "pg";

/**
 * US1 — Modules activables par église.
 *
 * Noyau, toujours actif, jamais désactivable : membres, finances, rapports.
 * Chaque église décide seule pour elle-même : une église mère ne peut pas
 * forcer l'activation d'un module pour ses antennes (question ouverte du
 * document US1, tranchée ici par la règle la plus simple et la plus sûre).
 *
 * État stocké dans `eglise_modules` (church_id, module, actif). Absence de
 * ligne = module inactif : à la création d'une église, seuls le noyau est
 * actif. Les églises créées avant US1 sont remplies à l'activation par la
 * migration 005 (tout actif), pour ne rien leur couper.
 */

export interface ModuleInfo {
  code: string;
  label: string;
  noyau: boolean;
}

export const MODULES_NOYAU: ModuleInfo[] = [
  { code: "membres", label: "Membres", noyau: true },
  { code: "finances", label: "Finances", noyau: true },
  { code: "rapports", label: "Rapports", noyau: true },
];

export const MODULES_ACTIVABLES: ModuleInfo[] = [
  { code: "annonces", label: "Annonces", noyau: false },
  { code: "familles", label: "Familles", noyau: false },
  { code: "cultes", label: "Cultes", noyau: false },
  { code: "presences", label: "Présences", noyau: false },
  { code: "budget", label: "Budget & caisse", noyau: false },
  { code: "prieres", label: "Prières & messages", noyau: false },
  { code: "pastoral", label: "Suivi pastoral", noyau: false },
  { code: "serviteurs", label: "Serviteurs", noyau: false },
  { code: "enfants", label: "Enfants & jeunesse", noyau: false },
  { code: "medias", label: "Médias & bibliothèque", noyau: false },
  { code: "biens", label: "Biens de l'église", noyau: false },
  { code: "parametres", label: "Paramètres", noyau: false },
  { code: "mon_eglise", label: "Mon église", noyau: false },
];

export const TOUS_LES_MODULES: ModuleInfo[] = [...MODULES_NOYAU, ...MODULES_ACTIVABLES];

export function estModuleActivable(code: string): boolean {
  return MODULES_ACTIVABLES.some((m) => m.code === code);
}

export function libelleModule(code: string): string {
  return TOUS_LES_MODULES.find((m) => m.code === code)?.label ?? code;
}

/** Vrai si le module est actif pour l'église (le noyau l'est toujours). */
export async function isModuleActif(db: Pool, churchId: string, code: string): Promise<boolean> {
  if (MODULES_NOYAU.some((m) => m.code === code)) return true;
  if (!estModuleActivable(code)) return true;
  const { rows } = await db.query<{ actif: boolean }>(
    `SELECT actif FROM eglise_modules WHERE church_id = $1 AND module = $2`,
    [churchId, code],
  );
  return rows.length > 0 && rows[0].actif === true;
}

/**
 * preHandler : exige que le module soit actif pour l'église de la session.
 * Sinon : 403 avec le code `module_desactive`, et la route ne s'exécute pas.
 * À placer APRÈS requireAuth(db) dans le tableau preHandler.
 */
export function requireModule(db: Pool, code: string) {
  return async (req: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const actif = await isModuleActif(db, req.session.churchId, code);
    if (!actif) {
      reply.code(403).send({
        error: "module_desactive",
        message: `Module « ${libelleModule(code)} » désactivé pour cette église.`,
      });
    }
  };
}
