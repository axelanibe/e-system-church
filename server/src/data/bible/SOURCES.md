# Sources des données bibliques (tranche T9, Lot B)

Ce dossier contient les textes et ouvrages de référence de l'application.
**Aucun texte n'est inventé** : chaque fichier provient d'une source
vérifiable, citée ci-dessous avec sa licence et son empreinte SHA-256.
Les conversions (USFM -> JSON, JS -> JSON, HTML -> texte brut) ne font
que retirer les marqueurs et mettre en forme ; elles ne réécrivent
jamais le contenu. Les scripts de conversion sont dans
`server/scripts/` (`convertir-lsg1910.py`, `convertir-strong.py`,
`convertir-dictionnaire-aquifer.py`).

## 1. Bible Louis Segond 1910 — `lsg1910/` (67 fichiers, 4,4 Mo)

- **Texte** : Louis Segond 1910, 66 livres, 31 170 versets.
  (Versification Segond : les suscriptions des Psaumes comptent comme
  verset 1 ; écart de 68 versets vs la référence 31 102, expliqué
  livre par livre à la livraison de la T9.)
- **Source** : eBible.org, édition « Louis Segond 1910 »
  (ID fraLSG / FRELSG), USFM téléchargé le 2026-11-13 :
  https://ebible.org/Scriptures/fraLSG_usfm.zip
  (3 474 538 octets,
  SHA-256 `64c4fe2a84d92f958deb0d1add4247d126a21c8a51e5b3058338f661a42d4900`).
- **Licence** : **domaine public** — la page eBible.org indique :
  « Cette Bible est dans le domaine public. Il n'est pas protégé par
  copyright. / This Bible is in the Public Domain. It is not
  copyrighted. » (https://ebible.org/Scriptures/details.php?id=fraLSG).
- **Note** : le dépôt BibleCorps/FRA-B-LSG1910-PD-UBS, utilisé à l'origine
  par la T9, a été écarté le 2026-11-13 car il ne contient **aucun
  fichier LICENSE ni licence explicite** (sans licence, le contenu est
  par défaut tous droits réservés). Le texte eBible a été re-converti et
  vérifié : 66 livres, 31 170 versets, 0 résidu de balise ; 3 versets
  seulement diffèrent de l'ancienne conversion, tous des artefacts de
  l'ancienne jointure corrigés ici (« ( c’est » -> « (c’est »,
  « 5Éloignez-vous » -> « Éloignez-vous »).
- **Numéros Strong** : l'USFM eBible porte des attributs `|strong=`
  (705 728 attributs) mais ils sont **supprimés à la conversion** : c'est
  une numérotation positionnelle héritée de l'édition UBS (les mots-outils
  français héritent du numéro du mot hébreu/grec voisin), donc non fiable
  au niveau du mot. **Aucune correspondance verset -> numéro Strong
  n'est construite.**

## 2. Bible King James Version — `kjv/` (67 fichiers, 4,2 Mo)

- **Texte** : King James (Authorized) Version, texte normalisé de 1769,
  protocanon uniquement (66 livres), 31 102 versets (référence KJV
  standard, vérifiée : 31 102 lignes `\v`).
- **Source** : eBible.org, édition « King James (Authorized) Version »
  (ID eng-kjv2006 / ENGKJV), USFM téléchargé le 2026-11-13 :
  https://ebible.org/Scriptures/eng-kjv2006_usfm.zip
  (2 466 540 octets,
  SHA-256 `dce1ec3ea45a155ac05e975fc8d817da403a817713d554eb9cc3a2177a6cfd1c`).
- **Licence** : **domaine public** — la page eBible.org indique
  « public domain » (https://ebible.org/find/show.php?id=eng-kjv2006),
  avec la nuance suivante, sans effet hors du Royaume-Uni : les lettres
  patentes du roi Jacques réservent l'impression au Royaume-Uni
  (Cambridge, Oxford, Collins) ; hors du Royaume-Uni, l'œuvre est
  « firmly in the Public Domain ». Les églises utilisatrices sont en
  Côte d'Ivoire et l'utilisateur au Canada.
- **Numéros Strong** : comme pour la LS1910, les attributs `|strong=`
  de l'USFM sont supprimés à la conversion (numérotation positionnelle,
  non fiable au niveau du mot).

## 3. Concordance Strong — `strong/` (2 fichiers, 3,2 Mo)

- **Contenu** : lexiques hébreu (8 674 entrées, H1..H8674, complet) et
  grec (5 523 entrées, G1..G5624, 101 numéros manquants) de James Strong
  (1890 / 1894). Champs : lemma, translit/xlit, pron, derivation,
  strongs_def, kjv_def. La définition Strong (`strongs_def`) est
  absente sur 19 entrées grecques (ex. G687, G5184, G814) ; la
  définition KJV (`kjv_def`) reste disponible sur celles-ci.
- **Source** : dépôt GitHub openscriptures/strongs, branche master,
  commit `0acd2f251c2d35ff8db2dece4e0593979d3ac223`, téléchargé le
  2026-11-13 :
  https://github.com/openscriptures/strongs
  - `greek/strongs-greek-dictionary.js` (1 200 839 o,
    SHA-256 `7624ee738ae47e80f1a352223e28a26d011c9cd4898822cee52f47a010c04efd`)
  - `hebrew/strongs-hebrew-dictionary.js` (2 003 130 o,
    SHA-256 `5ce6aeed551c709f49bcfa341cadf2f34bc7599b85d9de9e6ac2ecbf60fc3739`)
- **Licence** : **CC-BY-SA**, indiquée dans les fichiers sources
  (« Copyright 2009, Open Scriptures. CC-BY-SA. Derived from XML. »
  pour le grec ; « Copyright 2010, Open Scriptures. CC-BY-SA. Derived
  from XML. » pour l'hébreu).
- **Fichiers convertis** :
  - `strong-grec.json` (1 194 319 o,
    SHA-256 `b32ebf3cf754426e7ae7d1a24a640d991cafbc27496f94e57a37c887e0f7b1a5`)
  - `strong-hebreu.json` (1 993 684 o,
    SHA-256 `0d190a866e05929aa11cf2b87b9b1712cca9740335941304606f50d1a3fc045d`)

## 4. Dictionnaire biblique — `dictionnaire/` (2 fichiers, 17,9 Mo)

- **Contenu** : « Aquifer Open Bible Dictionary » — dictionnaire
  biblique complet (personnes, lieux, termes) :
  - français : **4 475 articles** (`dictionnaire-fra.json`,
    8 857 171 o,
    SHA-256 `7e1d4a09616640611ca14b06aa7b371e75cacceb9110617a08f092a1135304d6`)
  - anglais : **6 074 articles** (`dictionnaire-eng.json`,
    9 017 923 o,
    SHA-256 `bb6fa5a9b6a27205318b371dea75d37e6a6208c1e18e89b97f9bddb1f63f5a5d`)
  Le français compte moins d'articles que l'anglais : la traduction
  française est partielle. Les deux langues sont embarquées ; le
  dictionnaire suit la langue de la version biblique choisie
  (LS1910 -> français, KJV -> anglais).
- **Source** : dépôt GitHub BibleAquifer/AquiferOpenBibleDictionary,
  téléchargé le 2026-11-14 :
  https://github.com/BibleAquifer/AquiferOpenBibleDictionary
  (dossiers `fra/json/` et `eng/json/`, métadonnées version 1.1.2).
- **Licence** : **CC BY-SA 4.0** — « Aquifer Open Bible Dictionary »
  © 2026 Mission Mutual (https://missionmutual.org), adaptation du
  « Tyndale Open Bible Dictionary » © 2023 Tyndale House Publishers,
  également CC BY-SA 4.0.
  (https://creativecommons.org/licenses/by-sa/4.0/legalcode.en)
- **Note** : le dictionnaire Easton's (1897, domaine public, ~4 000
  entrées, via le jeu de données Theographic de Robert Rouse,
  CC BY-SA 4.0) a été écarté au profit d'Aquifer : plus récent (2026),
  plus complet (4 475 / 6 074 articles contre ~4 000), avec une version
  française, et une langue moderne (Easton's reflète la pensée
  chrétienne du XIXe siècle).
