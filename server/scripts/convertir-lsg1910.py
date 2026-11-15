#!/usr/bin/env python3
r"""Convertit la Bible Louis Segond 1910 (USFM, domaine public) en JSON
par livre.

SOURCE (remplace BibleCorps, sans fichier LICENSE) :
  eBible.org — « Louis Segond 1910 », ID fraLSG / FRELSG, abrév. F10.
  Page : https://ebible.org/Scriptures/details.php?id=fraLSG
  USFM : https://ebible.org/Scriptures/fraLSG_usfm.zip
  Licence : domaine public, explicite sur la page et dans le fichier
  copr.htm du zip : « Cette Bible est dans le domaine public. Il n'est
  pas protégé par copyright. / This Bible is in the Public Domain. It
  is not copyrighted. » (Traduction de Louis Segond, 1re édition 1910 ;
  texte source Digital Bible Library, via eBible.org, fichiers datés du
  30 octobre 2026 ; zip téléchargé le 2026-11-13, sha256 consigné dans
  server/src/data/bible/SOURCES.md).
  L'en-tête USFM de chaque livre précise : « GENFLS1910.PTX, Louis
  Segond 1910, French, 31-10-2011, Moon Sun Kim. Updated for DBL by
  E. Canales, September 2012. »

Usage : python3 convertir-lsg1910.py <dossier-usfm> <dossier-sortie>
Sortie : <code>.json par livre + livres.json (canon : code, nom,
testament, chapitres) ; chaque livre : {"code","nom","testament",
"chapitres": [[verset, ...], ...]}.

Règles : on ne garde que le texte des versets (\v). Tous les autres
marqueurs sont supprimés : titres (\s, \ms, \mr, \mt), paragraphes
(\p, \q, \m... — leur texte FAIT partie du verset en cours quand il
y en a un), références (\r), notes (\f...\f*), renvois (\x...\x*),
mise en forme (\nd, \add, \wj, \qt, \em...). Le texte des versets
n'est jamais modifié (ni inventé, ni réécrit).

Numéros Strong : l'USFM eBible porte des marqueurs \w et \+w avec
attribut strong="Hnnnn"/"Gnnnn" (numérotation positionnelle, héritée
de l'édition UBS — les mots-outils français héritent du numéro du mot
hébreu/grec voisin, ex. « les » tagué H1254). Ces attributs sont
SUPPRIMÉS par la conversion (le texte du mot est gardé) : la LS1910
n'a pas de numéros Strong natifs et AUCUNE correspondance
verset -> numéro Strong n'est construite. La concordance Strong de
l'appli = les lexiques hébreu/grec consultables (Open Scriptures),
sans lien mot à mot avec les versets.
"""
import json
import os
import re
import sys

ORDRE = [
    ("GEN", "ancien"), ("EXO", "ancien"), ("LEV", "ancien"), ("NUM", "ancien"),
    ("DEU", "ancien"), ("JOS", "ancien"), ("JDG", "ancien"), ("RUT", "ancien"),
    ("1SA", "ancien"), ("2SA", "ancien"), ("1KI", "ancien"), ("2KI", "ancien"),
    ("1CH", "ancien"), ("2CH", "ancien"), ("EZR", "ancien"), ("NEH", "ancien"),
    ("EST", "ancien"), ("JOB", "ancien"), ("PSA", "ancien"), ("PRO", "ancien"),
    ("ECC", "ancien"), ("SNG", "ancien"), ("ISA", "ancien"), ("JER", "ancien"),
    ("LAM", "ancien"), ("EZK", "ancien"), ("DAN", "ancien"), ("HOS", "ancien"),
    ("JOL", "ancien"), ("AMO", "ancien"), ("OBA", "ancien"), ("JON", "ancien"),
    ("MIC", "ancien"), ("NAM", "ancien"), ("HAB", "ancien"), ("ZEP", "ancien"),
    ("HAG", "ancien"), ("ZEC", "ancien"), ("MAL", "ancien"),
    ("MAT", "nouveau"), ("MRK", "nouveau"), ("LUK", "nouveau"), ("JHN", "nouveau"),
    ("ACT", "nouveau"), ("ROM", "nouveau"), ("1CO", "nouveau"), ("2CO", "nouveau"),
    ("GAL", "nouveau"), ("EPH", "nouveau"), ("PHP", "nouveau"), ("COL", "nouveau"),
    ("1TH", "nouveau"), ("2TH", "nouveau"), ("1TI", "nouveau"), ("2TI", "nouveau"),
    ("TIT", "nouveau"), ("PHM", "nouveau"), ("HEB", "nouveau"), ("JAS", "nouveau"),
    ("1PE", "nouveau"), ("2PE", "nouveau"), ("1JN", "nouveau"), ("2JN", "nouveau"),
    ("3JN", "nouveau"), ("JUD", "nouveau"), ("REV", "nouveau"),
]

# Nombre de chapitres attendu par livre (canon protestant, 66 livres).
CHAPITRES_ATTENDUS = {
    "GEN": 50, "EXO": 40, "LEV": 27, "NUM": 36, "DEU": 34, "JOS": 24,
    "JDG": 21, "RUT": 4, "1SA": 31, "2SA": 24, "1KI": 22, "2KI": 25,
    "1CH": 29, "2CH": 36, "EZR": 10, "NEH": 13, "EST": 10, "JOB": 42,
    "PSA": 150, "PRO": 31, "ECC": 12, "SNG": 8, "ISA": 66, "JER": 52,
    "LAM": 5, "EZK": 48, "DAN": 12, "HOS": 14, "JOL": 3, "AMO": 9,
    "OBA": 1, "JON": 4, "MIC": 7, "NAM": 3, "HAB": 3, "ZEP": 3,
    "HAG": 2, "ZEC": 14, "MAL": 4, "MAT": 28, "MRK": 16, "LUK": 24,
    "JHN": 21, "ACT": 28, "ROM": 16, "1CO": 16, "2CO": 13, "GAL": 6,
    "EPH": 6, "PHP": 4, "COL": 4, "1TH": 5, "2TH": 3, "1TI": 6,
    "2TI": 4, "TIT": 3, "PHM": 1, "HEB": 13, "JAS": 5, "1PE": 5,
    "2PE": 3, "1JN": 5, "2JN": 1, "3JN": 1, "JUD": 1, "REV": 22,
}

# Marqueurs en paire : contenu entièrement supprimé (pile, imbrication
# gérée).
PAIRES = {"f", "fe", "x", "fig", "fm", "jmp", "vp", "va", "ca"}
# Marqueurs de paragraphe / poésie : le texte qui suit fait partie du
# verset en cours (continuation), sinon il est ignoré.
PARAGRAPHE = {
    "p", "m", "pi", "pi1", "pi2", "pi3", "q", "q1", "q2", "q3", "q4",
    "qm1", "qm2", "qm3", "li", "li1", "li2", "lh", "lf", "lim", "mi",
    "nb", "pc", "ph", "ph1", "ph2", "ph3", "pm", "pmc", "pmr", "po",
    "pr", "ps", "psi", "b", "cls", "qac", "qr", "qs", "d", "sp",
}
# Marqueurs en ligne : la balise est supprimée, le texte est gardé
# (seulement quand on est dans un verset).
EN_LIGNE = {
    "nd", "add", "wj", "qt", "em", "bk", "it", "bd", "sc", "sig",
    "sls", "tl", "k", "ord", "pn", "w", "rb", "rq",
}

# Le "+" préfixe les marqueurs imbriqués (ex. \+w dans \wj ou \qs) :
# il faut les reconnaître comme des marqueurs à part entière, sinon
# le "w" resterait dans le texte du verset.
TOKEN = re.compile(r"\\\+[a-z0-9]+\*?|\\[a-z0-9]+\*?|\\\+")
NUMERO_VERSET = re.compile(r"^\s*(\d+(?:-\d+)?)\s*")
# Attributs de type |strong="H1234" (ou '...') : supprimés avec leur
# valeur, avant tout autre nettoyage (sinon il resterait
# strong="H1234" dans le texte).
ATTRIBUT = re.compile(r"\|[A-Za-z0-9_]+=(?:\"[^\"]*\"|'[^']*')")


def nettoyer(texte, apostrophe_francaise=False):
    """Supprime les balises USFM restantes d'un morceau de verset."""
    texte = re.sub(r"\\\+", "", texte)
    texte = re.sub(r"\\[a-z0-9]+\*?", "", texte)
    texte = ATTRIBUT.sub("", texte)
    texte = texte.replace("|", "")
    texte = re.sub(r"\s+", " ", texte).strip()
    # FRANÇAIS UNIQUEMENT — apostrophe élidée : l'USFM découpe « l’ »
    # en « l’ » + « homme » (le « ’ » termine le morceau « l’ », le mot
    # suivant porte l'espace) : la jointure laisse « l’ homme ».
    # En français, aucun espace après ’ (« l’homme », « d’où »,
    # « jusqu’à » — 1 111 occurrences de jusqu’/lorsqu’/puisqu’/quoiqu’
    # dans la LS1910). En ANGLAIS, le possessif pluriel (« sons’ house »)
    # garde son espace : la règle ne s'applique donc qu'au français.
    if apostrophe_francaise:
        texte = re.sub(r"([’'])\s+", r"\1", texte)
    # Espaces parasites après une parenthèse ouvrante (« ( des » au
    # lieu de « (des ») : la découpe \w introduit un espace après (.
    # (Valable en français comme en anglais : jamais d'espace après (.)
    texte = re.sub(r"([(\[])\s+", r"\1", texte)
    # Espaces parasites après un guillemet ouvrant « “ » / « ‘ »
    # (« “ Meurs » au lieu de « “Meurs ») : même cause. (« « » français
    # n'est pas touché : il prend une espace en typographie française.)
    # Les points de suspension « … » ne sont PAS traités ici : « … ans »
    # (1SA 13:1) et « … Parce que » (2CO 11:11) prennent une espace dans
    # le texte imprimé, seul « …Vaheb » (NUM 21:14, omission en citation)
    # n'en prend pas — ce cas est traité au niveau des morceaux.
    texte = re.sub(r"([“‘])\s+", r"\1", texte)
    return texte


def convertir_livre(chemin, nom_court=False):
    brut = open(chemin, encoding="utf-8").read()
    nom = None
    # Noms courts : \h (« Genesis », « Genèse ») ; noms longs : \toc1.
    # LS1910 : \toc1 donne « Genèse » (\h donne « GENÈSE ») ;
    # KJV : \toc1 donne « The First Book of Moses, called Genesis »
    # (\h donne « Genesis ») — la KJV utilise donc les noms courts.
    marqueurs_nom = ("\\h", "\\toc1") if nom_court else ("\\toc1", "\\h")
    for marque in marqueurs_nom:
        m = re.search(rf"{re.escape(marque)}\s+(.+)", brut)
        if m and m.group(1).strip():
            nom = m.group(1).strip()
            break
    if not nom:
        nom = "?"
    # Découpe en jetons : ("marqueur", "\v") ou ("texte", "...").
    jetons = []
    pos = 0
    for mm in TOKEN.finditer(brut):
        if mm.start() > pos:
            jetons.append(("texte", brut[pos:mm.start()]))
        jetons.append(("marqueur", mm.group(0)))
        pos = mm.end()
    if pos < len(brut):
        jetons.append(("texte", brut[pos:]))

    chapitres = []
    chapitre = None          # liste de versets (str) du chapitre en cours
    verset = None            # liste de morceaux du verset en cours
    numeros = []             # numeros de versets (pour détecter les plages)
    mode = "ignorer"         # "verset" : le texte appartient au verset
    pile = []                # paires ouvertes (f, x, ...)
    attend_numero = False    # le prochain texte commence par le n° du verset

    def vider_verset():
        nonlocal verset
        if verset is not None and chapitre is not None:
            # Jointure SANS séparateur : les morceaux portent déjà leurs
            # espaces d'origine (l'USFM eBible découpe au niveau du mot
            # avec \w ; joindre avec " " créerait des espaces parasites
            # devant la ponctuation : "terre ." au lieu de "terre.").
            # Apostrophe autonome : un morceau réduit à « ’ » (ex. KJV
            # « ’tis ») rejoint le mot suivant sans espace. En français,
            # le « ’ » termine le morceau (« l’ ») : c'est la règle
            # apostrophe_francaise de nettoyer() qui s'en charge.
            # Points de suspension : un morceau qui SE TERMINE par « … »
            # (sans espace finale, ex. « : … » de NUM 21:14) rejoint le
            # mot suivant sans espace (« …Vaheb ») ; un morceau « … »
            # suivi d'une espace (« … » de 1SA 13:1, « ?… » de 2CO 11:11)
            # garde son espace (« … ans », « … Parce que »).
            morceaux = list(verset)
            for i in range(len(morceaux) - 1):
                if morceaux[i].strip() in ("’", "'") or morceaux[i].endswith("…"):
                    morceaux[i + 1] = morceaux[i + 1].lstrip()
            # nettoyer() réduit ensuite les blancs multiples à un seul.
            chapitre.append(nettoyer(
                "".join(morceaux), apostrophe_francaise=not nom_court))
        verset = None

    def vider_chapitre():
        nonlocal chapitre
        vider_verset()
        if chapitre is not None:
            chapitres.append(chapitre)
        chapitre = None

    for kind, val in jetons:
        if kind == "texte":
            if pile:
                continue
            if mode == "verset" and verset is not None:
                if attend_numero:
                    mm = NUMERO_VERSET.match(val)
                    if mm:
                        numeros.append(mm.group(1))
                        val = val[mm.end():]
                    attend_numero = False
                verset.append(val)
            continue
        # Marqueur.
        if val == "\\+":
            continue
        corps = val[1:]
        if corps.startswith("+"):
            corps = corps[1:]
        ferme = corps.endswith("*")
        nom_m = corps[:-1] if ferme else corps
        if nom_m in PAIRES:
            if not ferme:
                pile.append(nom_m)
            elif pile and pile[-1] == nom_m:
                pile.pop()
            elif pile and nom_m in pile:
                pile.remove(nom_m)
            continue
        if pile:
            continue
        if nom_m == "c":
            vider_chapitre()
            chapitre = []
            mode = "ignorer"
            continue
        if nom_m == "v":
            vider_verset()
            verset = []
            mode = "verset"
            attend_numero = True
            continue
        if nom_m in PARAGRAPHE:
            mode = "verset" if verset is not None else "ignorer"
            continue
        if nom_m in EN_LIGNE:
            continue
        # Tout autre marqueur (titres, références, métadonnées...) :
        # le texte qui suit n'appartient pas à un verset.
        mode = "ignorer"
    vider_chapitre()
    return nom, chapitres, numeros


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    fichiers = sorted(os.listdir(src))
    livres = []
    total_versets = 0
    for code, testament in ORDRE:
        # eBible LS1910 : NN-CODEfraLSG.usfm ; eBible KJV :
        # NN-CODEeng-kjv2006.usfm ; BibleCorps (ancien) : ...-CODE.p.sfm
        nom_fichier = next(
            (f for f in fichiers if re.search(rf"-{code}fraLSG\.usfm$", f)),
            None)
        if not nom_fichier:
            nom_fichier = next(
                (f for f in fichiers
                 if re.search(rf"-{code}eng-kjv2006\.usfm$", f)),
                None)
        if not nom_fichier:
            nom_fichier = next(
                (f for f in fichiers if f.endswith(f"-{code}.p.sfm")), None)
        if not nom_fichier:
            print(f"MANQUANT : {code}")
            sys.exit(1)
        nom, chapitres, numeros = convertir_livre(
            os.path.join(src, nom_fichier),
            nom_court="eng-kjv2006" in nom_fichier)
        attendu = CHAPITRES_ATTENDUS[code]
        if len(chapitres) != attendu:
            print(f"ERREUR {code} : {len(chapitres)} chapitres, attendu {attendu}")
            sys.exit(1)
        vides = [n + 1 for n, ch in enumerate(chapitres)
                 if not ch or any(v == "" for v in ch)]
        if vides:
            print(f"ERREUR {code} : chapitres/versets vides : {vides}")
            sys.exit(1)
        plages = [n for n in numeros if "-" in n]
        if plages:
            print(f"ATTENTION {code} : versets en plage : {plages[:10]}")
        total_versets += sum(len(ch) for ch in chapitres)
        livres.append({
            "code": code, "nom": nom, "testament": testament,
            "chapitres": len(chapitres),
        })
        with open(os.path.join(dst, f"{code}.json"), "w", encoding="utf-8") as fh:
            json.dump(
                {"code": code, "nom": nom, "testament": testament,
                 "chapitres": chapitres},
                fh, ensure_ascii=False, separators=(",", ":"))
        print(f"{code} {nom} : {len(chapitres)} chapitres, "
              f"{sum(len(ch) for ch in chapitres)} versets")
    with open(os.path.join(dst, "livres.json"), "w", encoding="utf-8") as fh:
        json.dump(livres, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"TOTAL : {len(livres)} livres, {total_versets} versets")


if __name__ == "__main__":
    main()
