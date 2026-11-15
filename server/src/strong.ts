import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { normaliser } from "./bible.js";

/**
 * Concordance Strong (hébreu + grec) — lexiques consultables.
 *
 * Source : dépôt openscriptures/strongs (CC-BY-SA), converti par
 * server/scripts/convertir-strong.py — détail dans
 * server/src/data/bible/SOURCES.md. 8 674 entrées hébreu (H1..H8674,
 * complet) et 5 523 entrées grec (G1..G5624, 101 numéros manquants).
 *
 * La concordance est un lexique, pas un index mot à mot : la LS1910
 * française n'a pas de numéros Strong natifs et les numéros
 * positionnels de l'USFM eBible ne sont pas fiables au niveau du mot,
 * donc AUCUNE correspondance verset -> numéro Strong n'est construite.
 * Recherche par numéro (G1234, H1234) et par mot (lemme, translittération,
 * définitions).
 */

export interface EntreeStrong {
  numero: string;
  langue: "hebreu" | "grec";
  lemma: string;
  translit: string;
  pron?: string;
  derivation?: string;
  strongs_def?: string;
  kjv_def?: string;
}

interface EntreeStrongJson {
  lemma: string;
  translit?: string;
  xlit?: string;
  pron?: string;
  derivation?: string;
  strongs_def?: string;
  kjv_def?: string;
}

const RACINE_SERVEUR = join(dirname(fileURLToPath(import.meta.url)), "..");

function dossierDonnees(): string {
  const candidats = [
    join(RACINE_SERVEUR, "dist", "data", "bible", "strong"),
    join(RACINE_SERVEUR, "src", "data", "bible", "strong"),
  ];
  for (const dir of candidats) {
    if (existsSync(join(dir, "strong-grec.json"))) return dir;
  }
  throw new Error(
    "Données Strong introuvables (strong-grec.json absent de dist/data et src/data).",
  );
}

const cache = new Map<string, Record<string, EntreeStrongJson>>();

function chargerLexique(langue: "hebreu" | "grec"): Record<string, EntreeStrongJson> {
  const enCache = cache.get(langue);
  if (enCache) return enCache;
  const fichier = langue === "hebreu" ? "strong-hébreu.json" : "strong-grec.json";
  const brut = readFileSync(join(dossierDonnees(), fichier), "utf8");
  const lexique = JSON.parse(brut) as Record<string, EntreeStrongJson>;
  cache.set(langue, lexique);
  return lexique;
}

function versEntree(numero: string, brut: EntreeStrongJson): EntreeStrong {
  return {
    numero,
    langue: numero.startsWith("H") ? "hebreu" : "grec",
    lemma: brut.lemma,
    translit: brut.translit ?? brut.xlit ?? "",
    pron: brut.pron,
    derivation: brut.derivation,
    strongs_def: brut.strongs_def,
    kjv_def: brut.kjv_def,
  };
}

/** Numéro Strong normalisé (« g1234 » -> « G1234 »), ou null si invalide. */
export function normaliserNumeroStrong(numero: unknown): string | null {
  if (typeof numero !== "string") return null;
  const maj = numero.trim().toUpperCase();
  if (!/^[GH][0-9]{1,4}$/.test(maj)) return null;
  return maj;
}

/** Une entrée par son numéro (G1234, H1234), ou null si absente. */
export function chercherStrong(numero: string): EntreeStrong | null {
  const langue = numero.startsWith("H") ? "hebreu" : "grec";
  const brut = chargerLexique(langue)[numero];
  if (!brut) return null;
  return versEntree(numero, brut);
}

/** Recherche par mot : lemme, translittération, définitions. */
export function rechercherStrong(terme: string, limite = 50): EntreeStrong[] {
  const aiguille = normaliser(terme.trim());
  if (aiguille.length < 2) return [];
  const resultats: EntreeStrong[] = [];
  // Numéro exact d'abord (la recherche « G1234 » donne l'entrée).
  const numero = normaliserNumeroStrong(terme);
  if (numero) {
    const entree = chercherStrong(numero);
    if (entree) resultats.push(entree);
  }
  for (const langue of ["hebreu", "grec"] as const) {
    const lexique = chargerLexique(langue);
    for (const [cle, brut] of Object.entries(lexique)) {
      if (resultats.length >= limite) return resultats;
      if (numero === cle) continue;
      const champs = [
        brut.lemma,
        brut.translit ?? brut.xlit ?? "",
        brut.strongs_def ?? "",
        brut.kjv_def ?? "",
      ];
      if (champs.some((c) => normaliser(c).includes(aiguille))) {
        resultats.push(versEntree(cle, brut));
      }
    }
  }
  return resultats;
}
