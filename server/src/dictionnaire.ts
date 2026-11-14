import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { normaliser } from "./bible.js";

/**
 * Dictionnaire biblique — articles encyclopédiques (personnes, lieux,
 * termes), par langue.
 *
 * Source : « Aquifer Open Bible Dictionary » © 2026 Mission Mutual,
 * CC BY-SA 4.0 (adaptation du Tyndale Open Bible Dictionary © 2023) —
 * détail dans server/src/data/bible/SOURCES.md. Français : 4 475
 * articles ; anglais : 6 074 articles (la traduction française est
 * partielle). La langue suit celle de la version biblique choisie
 * (LS1910 -> français, KJV -> anglais).
 */

export interface ArticleDictionnaire {
  titre: string;
  texte: string;
}

export type LangueDictionnaire = "fra" | "eng";

interface ArticleJson {
  t: string;
  c: string;
}

const RACINE_SERVEUR = join(dirname(fileURLToPath(import.meta.url)), "..");

function dossierDonnees(): string {
  const candidats = [
    join(RACINE_SERVEUR, "dist", "data", "bible", "dictionnaire"),
    join(RACINE_SERVEUR, "src", "data", "bible", "dictionnaire"),
  ];
  for (const dir of candidats) {
    if (existsSync(join(dir, "dictionnaire-fra.json"))) return dir;
  }
  throw new Error(
    "Données du dictionnaire introuvables (dictionnaire-fra.json absent de dist/data et src/data).",
  );
}

const cache = new Map<LangueDictionnaire, ArticleJson[]>();

export function normaliserLangueDictionnaire(
  langue: unknown,
): LangueDictionnaire | null {
  if (langue === undefined || langue === null || langue === "") return "fra";
  const id = String(langue).toLowerCase();
  if (id === "fra" || id === "fr") return "fra";
  if (id === "eng" || id === "en") return "eng";
  return null;
}

function chargerDictionnaire(langue: LangueDictionnaire): ArticleJson[] {
  const enCache = cache.get(langue);
  if (enCache) return enCache;
  const brut = readFileSync(
    join(dossierDonnees(), `dictionnaire-${langue}.json`),
    "utf8",
  );
  const articles = JSON.parse(brut) as ArticleJson[];
  cache.set(langue, articles);
  return articles;
}

/** Nombre d'articles (par langue). */
export function compterArticles(langue: LangueDictionnaire): number {
  return chargerDictionnaire(langue).length;
}

/** Un article par son titre exact (insensible à la casse), ou null. */
export function chercherArticle(
  titre: string,
  langue: LangueDictionnaire = "fra",
): ArticleDictionnaire | null {
  const aiguille = titre.trim().toLowerCase();
  if (!aiguille) return null;
  const trouve = chargerDictionnaire(langue).find(
    (a) => a.t.toLowerCase() === aiguille,
  );
  if (!trouve) return null;
  return { titre: trouve.t, texte: trouve.c };
}

/**
 * Recherche par mot : titres contenant le terme d'abord (par ordre
 * alphabétique), puis articles dont le texte contient le terme.
 */
export function rechercherDictionnaire(
  terme: string,
  langue: LangueDictionnaire = "fra",
  limite = 50,
): ArticleDictionnaire[] {
  const aiguille = normaliser(terme.trim());
  if (aiguille.length < 2) return [];
  const articles = chargerDictionnaire(langue);
  const parTitre: ArticleDictionnaire[] = [];
  const parTexte: ArticleDictionnaire[] = [];
  for (const article of articles) {
    if (normaliser(article.t).includes(aiguille)) {
      parTitre.push({ titre: article.t, texte: article.c });
    } else if (normaliser(article.c).includes(aiguille)) {
      parTexte.push({ titre: article.t, texte: article.c });
    }
  }
  return [...parTitre, ...parTexte].slice(0, limite);
}
