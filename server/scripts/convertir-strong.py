#!/usr/bin/env python3
# Convertisseur des dictionnaires Strong (hébreu + grec) en JSON compact
# pour e-System Church (tranche T9).
#
# SOURCE : dépôt GitHub openscriptures/strongs (branche master, commit
#   0acd2f251c2d35ff8db2dece4e0593979d3ac223) :
#   greek/strongs-greek-dictionary.js — « Copyright 2009, Open Scriptures.
#     CC-BY-SA. Derived from XML. » (James Strong, 1890 ; XML préparé en
#     2006 par Ulrik Petersen).
#   hebrew/strongs-hebrew-dictionary.js — « Copyright 2010, Open Scriptures.
#     CC-BY-SA. Derived from XML. » (James Strong, 1894 ; source David
#     Instone-Brewer, édition David Troidl).
#   Licence des données : CC-BY-SA (indiquée dans les fichiers sources).
#
# Les fichiers sources sont des modules JS (« var strongsGreekDictionary =
# {...}; module.exports = ... »). Ce script en extrait l'objet et l'écrit
# en JSON compact, sans modifier le contenu : les champs sont repris tels
# quels (lemma, translit/xlit, pron, derivation, strongs_def, kjv_def).
# Aucune correspondance verset -> numéro Strong n'est construite : la
# LS1910 française n'a pas de numéros Strong natifs et les numéros
# positionnels de l'USFM eBible ne sont pas fiables au niveau du mot.
#
# Usage : python3 convertir-strong.py <dossier-sources> <dossier-sortie>
#   (le dossier source contient strongs-greek-dictionary.js et
#   strongs-hebrew-dictionary.js ; sortie : strong-grec.json et
#   strong-hebreu.json)

import json
import os
import re
import sys


def convertir(fichier, sortie):
    brut = open(fichier, encoding="utf-8").read()
    m = re.search(r"=\s*(\{.*\});\s*module\.exports", brut, re.S)
    if not m:
        print(f"Objet introuvable dans {fichier}")
        sys.exit(1)
    obj = json.loads(m.group(1))
    with open(sortie, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))
    nums = sorted(int(k[1:]) for k in obj)
    print(f"{os.path.basename(fichier)} : {len(obj)} entrées "
          f"({obj and list(obj)[0]}..{list(obj)[-1]}, "
          f"{nums[-1] - nums[0] + 1 - len(nums)} numéros manquants) "
          f"-> {sortie} ({os.path.getsize(sortie)} o)")


def main():
    if len(sys.argv) != 3:
        print("Usage : convertir-strong.py <dossier-sources> "
              "<dossier-sortie>")
        sys.exit(2)
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    convertir(os.path.join(src, "strongs-greek-dictionary.js"),
              os.path.join(dst, "strong-grec.json"))
    convertir(os.path.join(src, "strongs-hebrew-dictionary.js"),
              os.path.join(dst, "strong-hebreu.json"))


if __name__ == "__main__":
    main()
