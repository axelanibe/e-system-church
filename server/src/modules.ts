/**
 * Catalogue des modules de l'église.
 *
 * Règle décidée par Axel le 11/11/2026 : on ne choisit plus les modules
 * à afficher, église mère ou annexes, tous les modules sont affichés
 * pour tous. Le choix d'activation US1 est abandonné : il n'y a plus
 * d'interrupteur d'activation, plus de garde 403 `module_desactive`,
 * plus de table `eglise_modules` lue ici (la table reste en base,
 * inutilisée, une migration pourra la supprimer plus tard).
 *
 * Ce fichier ne garde que le catalogue (codes et libellés), utilisé
 * par le détail d'une annexe (`routes/annexes.ts`).
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
