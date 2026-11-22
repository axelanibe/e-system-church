/**
 * Chaîne de prière (lot 3d) — constantes et aides pures, sans accès
 * base, pour être testées sans serveur ni base (comme les aides de
 * Connexion Prophétique, `server-production/src/chaine_priere.js`,
 * dont elles sont adaptées). Les routes vivent dans
 * `routes/chaine_priere.ts`.
 *
 * Règles : 24 créneaux d'une heure par jour, un membre par créneau,
 * un créneau par membre et par jour. La chaîne est celle du jour
 * demandé, en AAAA-MM-JJ ; sans jour, le jour courant de l'église
 * (fuseau horaire de l'église, côté base). Les jours passés sont en
 * lecture seule. Le prénom affiché est le premier mot du nom complet
 * en base, jamais inventé.
 */

/// Nombre de créneaux dans une journée, un par heure.
export const NB_CRENEAUX = 24;

/// Première et dernière heure d'un créneau.
export const HEURE_MIN = 0;
export const HEURE_MAX = 23;

/** Vrai quand l'heure est un créneau valide, 0 à 23. */
export function heureValide(heure: unknown): heure is number {
  return (
    typeof heure === "number" &&
    Number.isInteger(heure) &&
    heure >= HEURE_MIN &&
    heure <= HEURE_MAX
  );
}

/** Heure normalisée depuis le corps de la requête : l'entier quand il
 *  est valide, null sinon. Une chaîne de chiffres est acceptée, comme
 *  l'envoie un formulaire. */
export function normaliserHeure(valeur: unknown): number | null {
  if (typeof valeur === "string" && valeur.trim() !== "") {
    const nombre = Number(valeur);
    return Number.isInteger(nombre) ? nombre : null;
  }
  return Number.isInteger(valeur) ? (valeur as number) : null;
}

/** Vrai quand la chaîne est un jour AAAA-MM-JJ réel, par exemple
 *  2026-11-22. Le mois et le jour doivent exister, 2026-02-30 est
 *  refusé. */
export function jourValide(jour: unknown): jour is string {
  if (typeof jour !== "string") return false;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(jour);
  if (!m) return false;
  const annee = Number(m[1]);
  const mois = Number(m[2]);
  const quantieme = Number(m[3]);
  if (mois < 1 || mois > 12 || quantieme < 1 || quantieme > 31) {
    return false;
  }
  const d = new Date(Date.UTC(annee, mois - 1, quantieme));
  return (
    d.getUTCFullYear() === annee &&
    d.getUTCMonth() === mois - 1 &&
    d.getUTCDate() === quantieme
  );
}

/** Jour normalisé depuis la demande : la chaîne quand elle est un jour
 *  AAAA-MM-JJ réel, null sinon. Une chaîne vide vaut absence, comme
 *  pour l'heure. */
export function normaliserJour(valeur: unknown): string | null {
  if (typeof valeur !== "string" || valeur.trim() === "") return null;
  return jourValide(valeur) ? valeur : null;
}

/** Vrai quand le jour demandé est avant le jour de référence, les deux
 *  en AAAA-MM-JJ : la comparaison de chaînes suffit. Un jour passé est
 *  en lecture seule, on ne peut ni réserver ni libérer dessus. */
export function jourPasse(jour: string, aujourdHui: string): boolean {
  return jour < aujourdHui;
}

/** Refus d'engagement, null quand tout est bon. La prise du créneau et
 *  le créneau déjà pris par le membre sont vérifiés par l'appelant en
 *  base, jamais ici. Le jour, quand il est fourni, doit être un jour
 *  AAAA-MM-JJ réel. */
export function validerEngagement(args: {
  heure?: unknown;
  jour?: unknown;
}): { statut: number; message: string } | null {
  const h = normaliserHeure(args.heure);
  if (h == null || !heureValide(h)) {
    return {
      statut: 400,
      message: "Créneau invalide : une heure de 0 à 23.",
    };
  }
  if (
    args.jour != null &&
    args.jour !== "" &&
    normaliserJour(args.jour) == null
  ) {
    return { statut: 400, message: "Jour invalide : un jour AAAA-MM-JJ." };
  }
  return null;
}

/** Prénom depuis le nom complet en base : le premier mot, vide quand
 *  le nom est vide. Même règle que le prénom d'auteur des stories et
 *  des témoignages de Connexion Prophétique. */
export function prenomDepuisNomComplet(nomComplet: unknown): string {
  if (typeof nomComplet !== "string") return "";
  const propre = nomComplet.trim();
  if (propre === "") return "";
  return propre.split(/\s+/)[0];
}

export interface LigneCreneau {
  heure: number;
  member_id?: string | null;
  nom_complet?: string | null;
  prenom?: string | null;
}

export interface CreneauPublic {
  heure: number;
  member_id: string | null;
  prenom: string;
}

/** Forme publique d'un créneau pris : l'heure, l'identifiant du membre
 *  et son prénom seulement, jamais son nom complet ni son matricule. */
export function formaterCreneauPublic(ligne: LigneCreneau): CreneauPublic {
  return {
    heure: ligne.heure,
    member_id: ligne.member_id ?? null,
    prenom: prenomDepuisNomComplet(
      ligne.nom_complet ?? ligne.prenom ?? "",
    ),
  };
}

/** Chaîne complète du jour : les 24 créneaux, de 0 h à 23 h, dans
 *  l'ordre. Un créneau libre a member_id null et un prénom vide, un
 *  créneau pris porte le membre en base. */
export function chaineComplete(
  lignes: LigneCreneau[] | null | undefined,
): CreneauPublic[] {
  const parHeure = new Map<number, CreneauPublic>();
  for (const ligne of lignes ?? []) {
    if (heureValide(ligne.heure) && !parHeure.has(ligne.heure)) {
      parHeure.set(ligne.heure, formaterCreneauPublic(ligne));
    }
  }
  const creneaux: CreneauPublic[] = [];
  for (let heure = HEURE_MIN; heure <= HEURE_MAX; heure += 1) {
    creneaux.push(
      parHeure.get(heure) ?? { heure, member_id: null, prenom: "" },
    );
  }
  return creneaux;
}

/** Nombre d'heures couvertes sur 24, pour l'en-tête. */
export function compterCouverts(
  creneaux: CreneauPublic[] | null | undefined,
): number {
  return (creneaux ?? []).filter((c) => c.member_id != null).length;
}
