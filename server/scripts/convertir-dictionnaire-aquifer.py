#!/usr/bin/env python3
# Convertisseur du dictionnaire Aquifer Open Bible Dictionary (fra / eng)
# en JSON compact {titre, texte} pour e-System Church (tranche T9).
#
# SOURCE : dépôt GitHub BibleAquifer/AquiferOpenBibleDictionary
#   https://github.com/BibleAquifer/AquiferOpenBibleDictionary
#   « Aquifer Open Bible Dictionary » © 2026 Mission Mutual
#   (https://missionmutual.org), licence CC BY-SA 4.0
#   (https://creativecommons.org/licenses/by-sa/4.0/legalcode.en).
#   Adaptation du « Tyndale Open Bible Dictionary » © 2023 Tyndale House
#   Publishers, également CC BY-SA 4.0.
#   Fichiers d'entrée : <langue>/json/NNN.content.json (listes d'articles
#   avec « title », « index_reference », « content » en HTML).
#
# Le HTML est converti en texte brut (paragraphes séparés par une ligne
# vide, références bibliques conservées : « Ex 7.7 »). Aucun contenu
# n'est inventé : seuls les titres et les textes de la source sont repris.
# Sortie : dictionnaire-<langue>.json — liste triée par titre, format
# compact [{"t": titre, "c": texte}, ...].
#
# Usage : python3 convertir-dictionnaire-aquifer.py <dossier-json-source>
#         <langue: fra|eng> <fichier-sortie>

import html
import json
import os
import re
import sys


def html_vers_texte(page):
    """Convertit le HTML d'un article en texte brut lisible."""
    texte = page
    # Les références bibliques : garder le texte visible (« Ex 7.7 »),
    # retirer la balise <data ...> et ses attributs.
    texte = re.sub(r"<data[^>]*>(.*?)</data>", r"\1", texte, flags=re.S)
    # Sauts de ligne : fin de paragraphe / de titre / d'élément de liste.
    texte = re.sub(r"</(p|h1|h2|h3|h4|li|ul|ol|blockquote)>", "\n\n", texte)
    texte = re.sub(r"<br\s*/?>", "\n", texte)
    # Retirer toutes les autres balises.
    texte = re.sub(r"<[^>]+>", "", texte)
    # Entités HTML (&apos; &amp; &quot; &nbsp; …).
    texte = html.unescape(texte)
    texte = texte.replace("\u00a0", " ")
    # Normaliser les blancs : au plus une ligne vide entre paragraphes.
    texte = re.sub(r"[ \t]+", " ", texte)
    texte = re.sub(r"\n[ \t]*\n+", "\n\n", texte)
    return texte.strip()


def main():
    if len(sys.argv) != 4:
        print("Usage : convertir-dictionnaire-aquifer.py <dossier-json> "
              "<fra|eng> <sortie>")
        sys.exit(2)
    dossier, langue, sortie = sys.argv[1], sys.argv[2], sys.argv[3]
    fichiers = sorted(f for f in os.listdir(dossier)
                      if re.match(r"^\d+\.content\.json$", f))
    if not fichiers:
        print(f"Aucun fichier NNN.content.json dans {dossier}")
        sys.exit(1)
    articles = {}
    doublons = 0
    for nom in fichiers:
        with open(os.path.join(dossier, nom), encoding="utf-8") as f:
            liste = json.load(f)
        for article in liste:
            titre = (article.get("title") or "").strip()
            contenu = article.get("content") or ""
            if not titre or not contenu:
                continue
            texte = html_vers_texte(contenu)
            if not texte:
                continue
            if titre in articles:
                doublons += 1
                continue
            articles[titre] = texte
    tries = sorted(articles.items(), key=lambda kv: kv[0].lower())
    with open(sortie, "w", encoding="utf-8") as f:
        json.dump([{"t": t, "c": c} for t, c in tries], f,
                  ensure_ascii=False, separators=(",", ":"))
    print(f"{langue} : {len(tries)} articles "
          f"({doublons} doublons ignorés) -> {sortie} "
          f"({os.path.getsize(sortie)} o)")


if __name__ == "__main__":
    main()
