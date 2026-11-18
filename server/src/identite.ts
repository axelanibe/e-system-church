import type { Pool, PoolClient } from "pg";

/**
 * Identité institutionnelle (Phase 2) : chaque église mère définit son
 * identité, ses branches en héritent obligatoirement.
 *
 * Source de référence : `eglise_parametres` (migration 037). Les
 * colonnes `churches` restent en place, en lecture seule transitoire,
 * et servent de repli quand la ligne de paramètres est absente ou le
 * champ vide.
 */

/** Message 403 commun quand une annexe touche un champ institutionnel. */
export const MESSAGE_CHAMP_HERITE =
  "Champ institutionnel hérité de l’église mère : modifiable uniquement par l’église mère.";

type Db = Pool | PoolClient;

/** Vrai si `egliseId` est une descendante de `racineId` (tous niveaux). */
export async function estDescendante(
  db: Db,
  racineId: string,
  egliseId: string,
): Promise<boolean> {
  if (racineId === egliseId) return false;
  const { rows } = await db.query(
    `WITH RECURSIVE descendants AS (
       SELECT id FROM churches WHERE id = $1
       UNION ALL
       SELECT c.id FROM churches c JOIN descendants d ON c.parent_church_id = d.id
     )
     SELECT 1 FROM descendants WHERE id = $2`,
    [racineId, egliseId],
  );
  return (rows.length ?? 0) > 0;
}

export interface IdentiteInstitutionnelle {
  eglise_id: string;
  eglise_code: string;
  eglise_nom: string;
  est_annexe: boolean;
  mere: { id: string; code: string; nom: string } | null;
  heritee: boolean;
  statut: string;
  statut_mere: string | null;
  nom_officiel: string;
  sigle: string | null;
  slogan: string | null;
  logo_url: string | null;
  couleur_principale: string | null;
  couleurs: Record<string, unknown>;
  adresse: string | null;
  ville: string | null;
  pays: string | null;
  telephone: string | null;
  email: string | null;
  site_web: string | null;
  devise: string;
  fuseau_horaire: string;
  numero_enregistrement: string | null;
  infos_legales: Record<string, unknown>;
  parametres_documents: Record<string, unknown>;
  description: string | null;
  horaires_cultes: unknown;
  adresse_locale: string | null;
  ville_locale: string | null;
  telephone_local: string | null;
  email_local: string | null;
}

interface LigneEglise {
  id: string;
  code: string;
  name: string;
  parent_church_id: string | null;
  city: string | null;
  country: string | null;
  address: string | null;
  phone: string | null;
  email: string | null;
  logo_url: string | null;
  couleur_principale: string | null;
  devise: string | null;
  fuseau_horaire: string | null;
  description: string | null;
  horaires_cultes: unknown;
}

interface LigneParametres {
  adresse: string | null;
  ville: string | null;
  telephone: string | null;
  email: string | null;
  logo_url: string | null;
  devise: string | null;
  fuseau_horaire: string | null;
  sigle: string | null;
  slogan: string | null;
  site_web: string | null;
  numero_enregistrement: string | null;
  infos_legales: Record<string, unknown> | null;
  couleurs: Record<string, unknown> | null;
  parametres_documents: Record<string, unknown> | null;
  statut: string | null;
}

async function lireEglise(
  db: Db,
  churchId: string,
): Promise<{ eglise: LigneEglise; parametres: LigneParametres } | null> {
  const { rows } = await db.query(
    `SELECT c.id, c.code, c.name, c.parent_church_id, c.city, c.country,
            c.address, c.phone, c.email, c.logo_url, c.couleur_principale,
            c.devise, c.fuseau_horaire, c.description, c.horaires_cultes,
            p.adresse, p.ville, p.telephone, p.email,
            p.logo_url AS p_logo_url, p.devise AS p_devise,
            p.fuseau_horaire AS p_fuseau_horaire,
            p.sigle, p.slogan, p.site_web, p.numero_enregistrement,
            p.infos_legales, p.couleurs, p.parametres_documents, p.statut
       FROM churches c
       LEFT JOIN eglise_parametres p ON p.church_id = c.id
      WHERE c.id = $1`,
    [churchId],
  );
  if (rows.length === 0) return null;
  const r = rows[0];
  // Une ligne de paramètres absente (LEFT JOIN) donne des colonnes NULL
  // partout : la fiche vide s'applique (devise FCFA, fuseau
  // Africa/Abidjan, statut brouillon), via les replis ci-dessous.
  const parametres: LigneParametres = {
    adresse: r.adresse ?? null,
    ville: r.ville ?? null,
    telephone: r.telephone ?? null,
    email: r.email ?? null,
    logo_url: r.p_logo_url ?? null,
    devise: r.p_devise ?? "FCFA",
    fuseau_horaire: r.p_fuseau_horaire ?? "Africa/Abidjan",
    sigle: r.sigle ?? null,
    slogan: r.slogan ?? null,
    site_web: r.site_web ?? null,
    numero_enregistrement: r.numero_enregistrement ?? null,
    infos_legales: r.infos_legales ?? {},
    couleurs: r.couleurs ?? {},
    parametres_documents: r.parametres_documents ?? {},
    statut: r.statut ?? "brouillon",
  };
  const eglise: LigneEglise = {
    id: r.id,
    code: r.code,
    name: r.name,
    parent_church_id: r.parent_church_id ?? null,
    city: r.city ?? null,
    country: r.country ?? null,
    address: r.address ?? null,
    phone: r.phone ?? null,
    email: r.email ?? null,
    logo_url: r.logo_url ?? null,
    couleur_principale: r.couleur_principale ?? null,
    devise: r.devise ?? null,
    fuseau_horaire: r.fuseau_horaire ?? null,
    description: r.description ?? null,
    horaires_cultes: r.horaires_cultes ?? [],
  };
  return { eglise, parametres };
}

/** Résout les champs institutionnels d'une église depuis ses deux magasins. */
function resoudre(
  eglise: LigneEglise,
  p: LigneParametres,
): Omit<
  IdentiteInstitutionnelle,
  | "eglise_id"
  | "eglise_code"
  | "eglise_nom"
  | "est_annexe"
  | "mere"
  | "heritee"
  | "statut"
  | "statut_mere"
  | "adresse_locale"
  | "ville_locale"
  | "telephone_local"
  | "email_local"
> {
  const couleurs = p.couleurs ?? {};
  return {
    nom_officiel: eglise.name,
    sigle: p.sigle,
    slogan: p.slogan,
    logo_url: p.logo_url ?? eglise.logo_url,
    couleur_principale:
      typeof couleurs.principale === "string"
        ? (couleurs.principale as string)
        : eglise.couleur_principale,
    couleurs,
    adresse: p.adresse ?? eglise.address,
    ville: p.ville ?? eglise.city,
    pays: eglise.country,
    telephone: p.telephone ?? eglise.phone,
    email: p.email ?? eglise.email,
    site_web: p.site_web,
    devise: p.devise ?? eglise.devise ?? "FCFA",
    fuseau_horaire: p.fuseau_horaire ?? eglise.fuseau_horaire ?? "Africa/Abidjan",
    numero_enregistrement: p.numero_enregistrement,
    infos_legales: p.infos_legales ?? {},
    parametres_documents: p.parametres_documents ?? {},
    description: eglise.description,
    horaires_cultes: eglise.horaires_cultes ?? [],
  };
}

/**
 * Identité institutionnelle résolue d'une église. Une annexe dont la
 * mère a publié son identité (`statut = 'publié'`) hérite des champs
 * institutionnels de la mère ; sinon (mère brouillon, ou église mère),
 * elle garde ses valeurs propres. `null` si l'église n'existe pas.
 */
export async function identiteInstitutionnelle(
  db: Db,
  churchId: string,
): Promise<IdentiteInstitutionnelle | null> {
  const propre = await lireEglise(db, churchId);
  if (!propre) return null;
  const { eglise, parametres } = propre;
  const estAnnexe = eglise.parent_church_id !== null;
  let mere: IdentiteInstitutionnelle["mere"] = null;
  let statutMere: string | null = null;
  let heritee = false;
  let champs = resoudre(eglise, parametres);
  if (estAnnexe) {
    const mereLue = await lireEglise(db, eglise.parent_church_id as string);
    if (mereLue) {
      mere = { id: mereLue.eglise.id, code: mereLue.eglise.code, nom: mereLue.eglise.name };
      statutMere = mereLue.parametres.statut ?? "brouillon";
      if (statutMere === "publié") {
        champs = resoudre(mereLue.eglise, mereLue.parametres);
        heritee = true;
      }
    }
  }
  return {
    eglise_id: eglise.id,
    eglise_code: eglise.code,
    eglise_nom: eglise.name,
    est_annexe: estAnnexe,
    mere,
    heritee,
    statut: parametres.statut ?? "brouillon",
    statut_mere: statutMere,
    ...champs,
    // Coordonnées propres de l'annexe (jamais héritées) ; null pour une mère.
    adresse_locale: estAnnexe ? (parametres.adresse ?? eglise.address) : null,
    ville_locale: estAnnexe ? (parametres.ville ?? eglise.city) : null,
    telephone_local: estAnnexe ? (parametres.telephone ?? eglise.phone) : null,
    email_local: estAnnexe ? (parametres.email ?? eglise.email) : null,
  };
}

/** Colonnes de `eglise_parametres` synchronisables par upsert. */
export const COLONNES_PARAMETRES_IDENTITE = [
  "adresse",
  "ville",
  "telephone",
  "email",
  "logo_url",
  "devise",
  "fuseau_horaire",
  "sigle",
  "slogan",
  "site_web",
  "numero_enregistrement",
  "infos_legales",
  "couleurs",
  "parametres_documents",
  "statut",
] as const;

export type ChampsParametresIdentite = Partial<
  Record<(typeof COLONNES_PARAMETRES_IDENTITE)[number], unknown>
>;

/**
 * Upsert des colonnes fournies dans `eglise_parametres`, pour garder les
 * deux magasins synchronisés pendant la transition (les colonnes
 * `churches` restent, en lecture seule transitoire). `couleurs` est
 * fusionnée (merge JSONB), pas remplacée, pour ne pas perdre les
 * couleurs déjà définies par une autre route.
 */
export async function synchroniserParametresIdentite(
  db: Db,
  churchId: string,
  champs: ChampsParametresIdentite,
): Promise<void> {
  const cles = (Object.keys(champs) as (keyof ChampsParametresIdentite)[]).filter(
    (k) => COLONNES_PARAMETRES_IDENTITE.includes(k) && champs[k] !== undefined,
  );
  if (cles.length === 0) return;
  const colonnes = ["church_id", ...cles];
  const placeholders = colonnes.map((_, i) => `$${i + 1}`).join(", ");
  const misesAJour = cles
    .map((k) =>
      k === "couleurs"
        ? `couleurs = COALESCE(eglise_parametres.couleurs, '{}'::jsonb) || EXCLUDED.couleurs`
        : `${k} = EXCLUDED.${k}`,
    )
    .join(", ");
  const valeurs: unknown[] = [
    churchId,
    ...cles.map((k) => {
      const v = champs[k];
      return typeof v === "object" && v !== null ? JSON.stringify(v) : v;
    }),
  ];
  await db.query(
    `INSERT INTO eglise_parametres (${colonnes.join(", ")})
     VALUES (${placeholders})
     ON CONFLICT (church_id) DO UPDATE SET ${misesAJour}, updated_at = now()`,
    valeurs,
  );
}
