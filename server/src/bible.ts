import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Bibles (domaine public) — lecture, par version.
 *
 * - Louis Segond 1910 (« lsg1910 », français, 66 livres, 31 170 versets)
 *   et King James Version (« kjv », anglais, 66 livres, 31 102 versets).
 * - Sources et licences : eBible.org (fraLSG et eng-kjv2006, domaine
 *   public) — détail dans server/src/data/bible/SOURCES.md. Le texte
 *   n'est jamais inventé ni réécrit : seuls les marqueurs USFM sont
 *   retirés à la conversion (server/scripts/convertir-lsg1910.py).
 * - La version par défaut est « lsg1910 » (compatibilité avec la T9
 *   d'origine et les appels sans paramètre) ; une version inconnue est
 *   rejetée (400 côté route) plutôt que remplacée silencieusement.
 *
 * Les JSON vivent sous src/data/bible/<version>/ (et sous dist/data/
 * quand le build les y a copiés) : on sonde les deux emplacements.
 */

export interface VersionBible {
  id: string;
  nom: string;
  langue: "fr" | "en";
  dossier: string;
  livres: number;
  versets: number;
}

export interface LivreBible {
  code: string;
  nom: string;
  testament: "ancien" | "nouveau";
  chapitres: number;
}

export interface VersetBible {
  numero: number;
  texte: string;
}

export interface ResultatRecherche {
  livre: string;
  code: string;
  chapitre: number;
  verset: number;
  texte: string;
}

interface LivreJson {
  code: string;
  nom: string;
  testament: "ancien" | "nouveau";
  chapitres: string[][];
}

const VERSIONS: Record<string, { nom: string; langue: "fr" | "en" }> = {
  lsg1910: { nom: "Louis Segond 1910", langue: "fr" },
  kjv: { nom: "King James Version", langue: "en" },
};

export const VERSION_PAR_DEFAUT = "lsg1910";

const RACINE_SERVEUR = join(dirname(fileURLToPath(import.meta.url)), "..");

function dossierDonnees(version: string): string {
  const candidats = [
    join(RACINE_SERVEUR, "dist", "data", "bible", version),
    join(RACINE_SERVEUR, "src", "data", "bible", version),
  ];
  for (const dir of candidats) {
    if (existsSync(join(dir, "livres.json"))) return dir;
  }
  throw new Error(
    `Données bibliques introuvables pour la version ${version} ` +
      "(livres.json absent de dist/data et src/data).",
  );
}

const canonCache = new Map<string, LivreBible[]>();
const livresCache = new Map<string, LivreJson>();

/** Version demandée, ou null si inconnue (à rejeter en 400). */
export function normaliserVersion(version: unknown): string | null {
  if (version === undefined || version === null || version === "") {
    return VERSION_PAR_DEFAUT;
  }
  const id = String(version).toLowerCase();
  return id in VERSIONS ? id : null;
}

export function listerVersions(): VersionBible[] {
  return Object.entries(VERSIONS).map(([id, meta]) => {
    const livres = listerLivres(id);
    return {
      id,
      nom: meta.nom,
      langue: meta.langue,
      dossier: id,
      livres: livres.length,
      versets: livres.reduce((total, l) => {
        const livre = chargerLivre(l.code, id);
        return (
          total +
          (livre?.chapitres.reduce((s, c) => s + c.length, 0) ?? 0)
        );
      }, 0),
    };
  });
}

export function listerLivres(version = VERSION_PAR_DEFAUT): LivreBible[] {
  const enCache = canonCache.get(version);
  if (enCache) return enCache;
  const brut = readFileSync(
    join(dossierDonnees(version), "livres.json"),
    "utf8",
  );
  const livres = JSON.parse(brut) as LivreBible[];
  canonCache.set(version, livres);
  return livres;
}

export function livreExiste(
  code: string,
  version = VERSION_PAR_DEFAUT,
): boolean {
  return listerLivres(version).some((l) => l.code === code.toUpperCase());
}

export function chargerLivre(
  code: string,
  version = VERSION_PAR_DEFAUT,
): LivreJson | null {
  const maj = code.toUpperCase();
  const cle = `${version}:${maj}`;
  const enCache = livresCache.get(cle);
  if (enCache) return enCache;
  if (!livreExiste(maj, version)) return null;
  const brut = readFileSync(join(dossierDonnees(version), `${maj}.json`), "utf8");
  const livre = JSON.parse(brut) as LivreJson;
  livresCache.set(cle, livre);
  return livre;
}

export function lireChapitre(
  code: string,
  chapitre: number,
  version = VERSION_PAR_DEFAUT,
): VersetBible[] | null {
  const livre = chargerLivre(code, version);
  if (!livre) return null;
  if (chapitre < 1 || chapitre > livre.chapitres.length) return null;
  return livre.chapitres[chapitre - 1].map((texte, i) => ({
    numero: i + 1,
    texte,
  }));
}

/** Normalisation insensible à la casse et aux accents (recherche). */
export function normaliser(texte: string): string {
  return texte
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

export function rechercher(
  terme: string,
  version = VERSION_PAR_DEFAUT,
  limite = 50,
): ResultatRecherche[] {
  const aiguille = normaliser(terme.trim());
  if (aiguille.length < 2) return [];
  const resultats: ResultatRecherche[] = [];
  for (const meta of listerLivres(version)) {
    const livre = chargerLivre(meta.code, version);
    if (!livre) continue;
    for (let c = 0; c < livre.chapitres.length; c += 1) {
      const chapitre = livre.chapitres[c];
      for (let v = 0; v < chapitre.length; v += 1) {
        if (normaliser(chapitre[v]).includes(aiguille)) {
          resultats.push({
            livre: meta.nom,
            code: meta.code,
            chapitre: c + 1,
            verset: v + 1,
            texte: chapitre[v],
          });
          if (resultats.length >= limite) return resultats;
        }
      }
    }
  }
  return resultats;
}
