# Comparaison — Appli e-System Church vs Projection (standard strict de Bouf)

**Références** : `~/workspace/user/files/Projection_finale_e-System_Church.html` (écrans + contenu) et `~/workspace/user/files/Projection_couleurs_logo_e-System_Church.html` (aspect final violet/or + logo). Les deux projections ont un contenu identique (vérifié par diff des textes extraits) ; la version couleurs ajoute l'en-tête « e-System Church / L'église sans frontière ».
**Cibles** : (1) build local T9 `~/workspace/.t9finish/app/build/web` servi sur http://127.0.0.1:8080/e-system-church/ ; (2) site en ligne https://e-system-church-web.onrender.com (build antérieur à la T9).
**Compte** : Test@gmail.com, église TEST (ESC-4240), rôle admin_eglise — lecture seule, aucune donnée créée/modifiée/supprimée.
**Viewport** : 1280×800 pour toutes les captures, sauf 40/41 (400×800, largeur téléphone).
**Échelle** : 1280 px ≈ 34 cm → **1 cm ≈ 38 px**. Chaque écart est mesuré en px et en cm approximatifs.
**Règle de Bouf** : TOUT écart avec la projection = ERREUR (position, espacement, taille, couleur, texte, élément manquant ou en trop, ordre). **SEULE EXCEPTION : la première page de connexion est EXCLUE de cette comparaison stricte.**

**Légende** : ERREUR = écart classé selon le standard de Bouf. « Caveat » = réserve expliquée (compte de test, état vierge, aperçu admin).

---

## Verdicts globaux

### Palette — CONFORME
Couleurs mesurées sur les captures (local et en ligne, identiques) : bouton « Se connecter » **#2A0059**, titre **#2A0059**, pilule active du rail **#E8B820**, badge « Prochain culte » **#E8B820**, fond de page **#F6F2FB** (≈ #EFE9F7 de la référence), carte violette du tableau de bord #320064 (même famille que le #360F62 échantillonné sur la projection couleurs). Référence attendue : violet profond #2A0059 / #3D0073, or #E8B820 / #F2C230, violets clairs #D9CCF2 / #EFE9F7. **La palette de l'appli correspond à la projection couleurs & logo.** L'ancienne palette vert/or (#0C5B40 / #C9971C) ne s'applique plus : la palette du logo est la référence.

### Logo — PRÉSENT
Logo officiel ESC (carré violet, ruban or, lettres blanches, asset `icone-esc.png`) présent sur l'écran de connexion et en haut à droite de chaque écran (local et en ligne). Emplacements conformes à la projection couleurs.

### Slogan — PRÉSENT
« L'église sans frontière » présent sur l'écran de connexion (local et en ligne) et dans l'en-tête de la projection couleurs.

### Lien muse.ai — INACCESSIBLE
Le lien partagé https://muse.ai/s/projection-couleurs-logo-e-system-xtxl6exhgobxn0xv/GkpIkEKsw2EkqYA4_MEM7G5-j1kkSYoSfHaT41qIjAA retourne **HTTP 403 « Page unavailable »** (vérifié par curl et par lecture de page). La comparaison utilise le fichier local déposé par Bouf.

---

## A. Écran par écran — Projection finale (contenu)

### 1. Connexion — EXCLUE (décision Bouf)
Non comparée à la projection. Fonctionnement vérifié : connexion OK en local (captures 01, 02a, 02b) et en ligne (01, 01b), après un écran violet vide de ~30–40 s au premier chargement en ligne (réveil Render).

### 2. Accueil administrateur
Projection : `captures-projection/finale/accueil.png` — Appli locale : `captures/04-accueil.png`, `04b-accueil-bas.png`, `04c-accueil-reseau.png` — En ligne : `captures-en-ligne/02-accueil.png`, `02b-accueil-bas.png` (pixel-identiques au local).

| Zone | Projection | Appli | Écart |
|---|---|---|---|
| Titre | « Accueil administrateur » | « Accueil » + « TEST / ESC-4240 » en dessous | **ERREUR E-A1** — texte : le mot « administrateur » manque (~15 caractères, ~150 px / ~4 cm) ; nom d'église ajouté en trop |
| Bannière fidèle | « Démonstration des deux espaces. Le fidèle a sa propre interface, avec sa navigation à lui. Touchez le bouton pour la voir. » + bouton « Voir l'espace fidèle » | Carte « APERÇU FIDÈLE / Espace Fidèle / Prévisualisez l'interface dédiée aux membres de votre assemblée. » + bouton doré « → Aperçu de l'espace fidèle » | **ERREUR E-A2** — texte entièrement différent (2 lignes → 3 lignes, ~180 px de haut en trop, ~4,7 cm) ; libellé du bouton différent |
| Cartes statistiques | 4 cartes : MEMBRES 0 / PRÉSENCES DU JOUR 0 / COTISATIONS DU MOIS 0 FCFA / NOUVEAUX MEMBRES 0, sans sous-titre | 4 cartes avec sous-titres **tronqués** : « Personnes inscrites da… », « Présences pointées auj… », « Cotisations payées ce … », « Nouveaux convertis ins… » | **ERREUR E-A3** — sous-titres en trop (absents de la projection) ET tronqués : chaque sous-titre est coupé à ~60 px / ~1,6 cm (texte 260→408 px dans une carte de 208 px de large) |
| MON RÉSEAU | « Aucun établissement relié / Les établissements de votre réseau apparaîtront ici. » | « Total de mes églises / 0 membres actifs · 0 contributions · 0 FCFA / Aucune église rattachée… » | **ERREUR E-A4** — texte différent : compteurs affichés à la place de la phrase attendue |
| ANNONCES RÉCENTES | « Aucune annonce / Les annonces publiées par la structure apparaîtront ici. » | « Aucune annonce pour l'instant. » + action « + Nouvelle annonce » | **ERREUR E-A5** — texte différent ; bouton « + Nouvelle annonce » en trop (absent de la projection) |
| ACTIONS RAPIDES | Ajouter un membre / Nouveau culte / Nouvelle annonce / Voir les finances | Identiques, mêmes 4 libellés et mêmes sous-titres | CONFORME |
| MON ÉGLISE MÈRE | Section « MON ÉGLISE MÈRE / Rapports à mon église mère / Ouvrir les rapports » | **Absente** | **ERREUR E-A6 (caveat)** — TEST n'a pas d'église mère : écart non vérifiable avec ce compte ; à re-vérifier avec une annexe |
| MES ÉGLISES ANNEXES | « Rapports reçus / Lisez les rapports envoyés par vos églises annexes. / Ouvrir les rapports reçus » | « MES ÉGLISES ANNEXES / Rapports reçus / Ouvrir les rapports reçus » | CONFORME (libellé du bouton identique ; sous-titre absent — voir E-A4 pour le bloc réseau) |

En ligne : mêmes écarts que le local (écrans pixel-identiques), plus les statistiques qui apparaissent avec quelques secondes de délai.

### 3. Membres et familles
Projection : `captures-projection/finale/membres.png` — Appli locale : `captures/05-membres.png` (+ `41-phone-membres.png` à 400 px) — En ligne : `captures-en-ligne/03-membres.png`.

| Zone | Projection | Appli | Écart |
|---|---|---|---|
| Onglets | Liste / Fiche / Familles / Anniversaires / Fréquentation | **Aucun onglet** (la Fiche et les Familles vivent dans « Départements ») | **ERREUR E-M1** — 5 onglets attendus, 0 présent ; « Anniversaires » et « Fréquentation » introuvables nulle part dans l'appli |
| Recherche | Champ « Rechercher un membre par nom ou matricule » | Simple icône loupe, aucun champ visible | **ERREUR E-M2** — champ de recherche absent (remplacé par une icône ~24 px) |
| Filtres | Tous / Anciens / Nouveaux / Familles | Tous / Actif / Nouveau converti / Inactif / Ancien | **ERREUR E-M3** — libellés différents (« Actif », « Nouveau converti », « Inactif » en trop ; « Familles » manquant) |
| État vide | « Aucun membre enregistré / La liste se remplira dès la première inscription. » | « Aucun membre trouvé. » + bouton « Nouveau membre » | **ERREUR E-M4** — texte différent (« trouvé » au lieu de « enregistré », 2e phrase manquante ~60 px / ~1,6 cm) |
| Filtre département | Absent | « Département : Tous » (menu déroulant) | **ERREUR E-M5** — élément en trop |
| Bouton de création | « Créer un membre » | « Nouveau membre » (bouton violet pleine largeur + bouton flottant doré « Nouveau membre » sur mobile) | **ERREUR E-M6** — libellé différent ; à 400 px le bouton apparaît **deux fois** sur le même écran (pleine largeur + flottant, ~48 px de haut chacun, ~1,3 cm) — duplication |
| Filtres à 400 px | Cadre téléphone : filtres visibles | Le 5e filtre « Inactif » est coupé au bord droit (« Inac… ») | **ERREUR E-M7** — débordement horizontal à 400 px (~40 px / ~1 cm coupés) ; défilement non signalé |

### 4. Finances (écran Contributions) — PAS DE CORRESPONDANT DIRECT DANS LA PROJECTION
La projection « Finances » est en réalité le contenu **Finances complètes** (voir § 5). L'écran « Finances » de l'appli (onglet Contributions) n'a **pas d'équivalent** dans la projection.
Appli locale : `captures/06-finances.png`, `06b-finances-bas.png` — En ligne : `captures-en-ligne/04-finances.png`.
Contenu de l'appli : onglets Contributions / Finances complètes ; filtres type + statut ; 4 cartes Dîmes / Offrandes / Dons / Dépenses confirmés (0 FCFA) ; lignes Finances complètes, Campagnes de collecte, Promesses de don, Dons en nature, Transparence financière, Budget & caisse. **Écart de structure** : la projection attend directement les 4 cartes « COTISATIONS DU MOIS / CAISSE / ENTRÉES DU JOUR / SORTIES DU JOUR » sur l'écran Finances ; l'appli les place un niveau plus bas (Finances complètes). **ERREUR E-F0** — l'écran Finances de l'appli ne correspond à aucun écran de la projection ; le contenu attendu est enterré d'un clic.

### 5. Finances complètes (sous-écran)
Projection : `captures-projection/finale/finances.png` — Appli locale : `captures/26-finances-completes.png` — En ligne (vérifié par audit navigateur) : 4 cartes Cotisations du mois 0 FCFA / Caisse 0 FCFA / Entrées du jour 0 FCFA / Sorties du jour 0 FCFA, « Aucune cotisation reçue », « Aucun compte enregistré », Rapprochement 0 FCFA, période octobre 2026 « Ouvert », 0 reçu — **contenu OK**.

| Zone | Projection | Appli (en ligne) | Écart |
|---|---|---|---|
| 4 cartes | COTISATIONS DU MOIS / CAISSE / ENTRÉES DU JOUR / SORTIES DU JOUR, 0 FCFA | Identiques | CONFORME |
| Couleur des valeurs | 4 valeurs dans la même couleur | « SORTIES DU JOUR 0 FCFA » en **rouge** (et « 0 FCFA » du Rapprochement en vert) | **ERREUR E-FC1** — couleur différente de la projection (~20 px de texte rouge) |
| Cotisations / Comptes / Rapprochement / Clôture | « Aucune cotisation reçue / Aucun compte enregistré / Écart 0 FCFA / Aucune période clôturée » | Identiques | CONFORME |
| Reçus numérotés / Budgets | « 0 reçu / Aucun budget défini » | 0 reçu (vérifié en ligne) ; budgets : voir § 14l (8 postes prédéfinis — E-BU1) | Voir E-BU1 |
| DÉCLARATIONS ET EXPORTS | Section « États financiers SYCEBNL / Ouvrir l'export SYCEBNL » | Section sous le pli de la capture 26 (non visible) ; écran SYCEBNL non capturé | Non vérifié (voir § F) |

### 6. Départements (Familles / Cellules)
Appli locale : `captures/07-departements.png` — En ligne : OK (audit navigateur). La projection ne consacre pas d'écran aux Départements (les Familles sont un onglet de « Membres et familles »).
Contenu local : onglets Familles / Cellules, recherche, « Aucune famille pour l'instant », sections FICHE D'UN MEMBRE, ENFANTS & JEUNESSE. **ERREUR E-D1** — la projection place « Familles » comme onglet de l'écran Membres ; l'appli en fait un écran séparé « Départements » : déplacement de navigation (1 niveau de plus). Onglet Cellules en attente (enfant A, n° 32).

### 7. Cultes en direct
Projection : `captures-projection/finale/cultes.png` (« T5 · Construit, en ligne ») — Appli locale : `captures/09-cultes.png`, `09b-cultes-bas.png` — En ligne : OK avec ~10 s de chargement (audit navigateur).

| Zone | Projection | Appli | Écart |
|---|---|---|---|
| Conducteur chronométré | « 00:00 / Chronomètre en pause / Démarrer / Remettre à zéro / Aucun moment au conducteur » | **Absent** — seul « Aucun culte planifié pour l'instant. » + « Planifier un culte » | **ERREUR E-C1** — conducteur, chronomètre et boutons absents (écran entier manquant, ~600 px / ~16 cm de contenu) |
| Transposition | « − / 0 DEMI-TONS / + » | **Absente** | **ERREUR E-C2** — bloc absent (~150 px / ~4 cm) |
| Compteur de portes | « − / 0 ENTRÉES / + » | **Absent** | **ERREUR E-C3** — bloc absent (~150 px / ~4 cm) |
| Pointage QR | « Présences pointées 0 / Scanner une carte » | **Absent** de cet écran | **ERREUR E-C4** — bloc absent |
| Caveat | — | Le conducteur n'apparaît peut-être que pendant un culte en cours ; impossible de le vérifier sans créer un culte (interdit : lecture seule). | Réserve — voir § F |

### 8. Espace membre (accueil fidèle)
Projection : `captures-projection/finale/membre.png` + `fidele-accueil.png` (deux écrans quasi identiques) — Appli locale : `captures/12-fidele-accueil.png`, `12b-fidele-accueil-bas.png` (mode « Aperçu Fidèle » depuis l'admin) — En ligne : en attente (enfant C, n° 06–07).

| Zone | Projection | Appli | Écart |
|---|---|---|---|
| Structure | DEUX écrans : « Espace membre » (T2) et « Accueil » fidèle | UN SEUL écran d'accueil fidèle | **ERREUR E-FI1** — l'appli fusionne deux écrans de la projection en un seul |
| Bannière d'aperçu | Absente | « Mode Aperçu Fidèle » + « ‹ Retour Admin » (bandeau jaune pâle, ~48 px / ~1,3 cm) | **ERREUR E-FI2 (caveat)** — chrome du mode aperçu admin ; n'existe peut-être pas dans la vraie vue membre |
| Salutation | « Bonjour, fidèle » (+ date « Samedi 14 Novembre 2026 ») | « 14/11/2026 / Bonjour, TEST » + « TEST » répété | **ERREUR E-FI3** — nom d'église affiché à la place de « fidèle » ; ligne « TEST » en trop |
| Carte de membre | Photo, Nom du membre, Matricule affiché après inscription, ÉGLISE / Nom de l'église, MEMBRE DEPUIS / À compléter, bouton « Voir ma carte » | Avatar initiale « T », « TEST » ×3, « ESC-4240 · TEST », badge « Église mère », bouton doré « Voir ma carte de membre », « À montrer à l'entrée de l'église. » | **ERREUR E-FI4** — pas de photo, pas de champ « MEMBRE DEPUIS », pas de matricule affiché ; badge « Église mère » en trop (vue membre) ; texte « À montrer à l'entrée… » en trop |
| Prochain culte | « À venir / COMPTE À REBOURS -- JOURS -- HEURES -- MINUTES / LIEU Lieu à confirmer / HEURE Heure à confirmer / Je serai présent » | « Aucun culte prévu pour l'instant. Revenez bientôt, votre église vous attend. » | **ERREUR E-FI5** — compte à rebours ABSENT (~120 px / ~3,2 cm), lieu/heure ABSENTS, bouton « Je serai présent » ABSENT |
| MES ACCÈS / ACTIONS RAPIDES | 4 accès en liste verticale : Ma Bible, Mes cotisations, Mon journal, Message à mon église (+ Prendre rendez-vous) | Grille 2×2 : Ma Bible, École biblique, Mes cotisations, Mon journal (+ Messagerie et rendez-vous pleine largeur plus bas) | **ERREUR E-FI6** — ordre et présentation différents : la T9 insère « École biblique » en 2e position ; « Message à mon église » (nommé « Messagerie ») est relégué plus bas. En ligne (pré-T9), la grille est Ma Bible, Mes cotisations, Mon journal, Messagerie — **dans l'ordre de la projection** (voir § 13a) |
| Cartes d'accès | Lignes compactes (~90 px de haut) avec « Ouvrir → » | Cartes géantes ~420 px de haut pour 2 lignes de texte, ~300 px de vide vertical par carte | **ERREUR E-FI7** — hauteur excessive : ~330 px / ~8,7 cm de vide en trop par carte |
| Mon Parcours | « Mon Parcours 0 % » + 4 étapes (Inscription, Baptême, Intégration, Service) + compteurs (0 Présences, 0 Contributions, 0 Attestations) | **Absent** | **ERREUR E-FI8** — section entière absente (~350 px / ~9,2 cm) |
| Prière du jour / Sujet de prière privé / Mes camps / Mes attestations | 4 sections présentes | **Absentes** | **ERREUR E-FI9** — 4 sections absentes (~500 px / ~13 cm cumulés) |
| Largeur du contenu (1280) | Cadre plein (400 px dans la projection) | Colonne étroite ~650 px (x 380→1030), ~250 px de vide à droite | **ERREUR E-FI10** — contenu non élargi à 1280 px : ~250 px / ~6,6 cm de vide à droite |

### 9. Ma Bible (fidèle)
Projection : `captures-projection/finale/membre-bible.png` (« Ma Bible ») et `bible.png` (écran admin T9 « À venir ») — Appli locale : `captures/13-bible-lsg.png`, `34-bible-kjv.png`, `35-bible-psaume23.png`, `36-concordance.png`, `37-dictionnaire.png` (+ sondes `34b-probe-*.png`).

| Zone | Projection | Appli locale T9 | Écart |
|---|---|---|---|
| Contenu | Recherche, onglets Ancien / Nouveau Testament, LISTE DES LIVRES (Genèse, Exode, Lévitique, Nombres, Deutéronome, Josué, Juges, Ruth, Psaumes, Proverbes, Ésaïe, Jérémie…), Passage / Chapitre / Verset | Recherche + onglet « Ancien Testament » + « Rechercher un livre », puis **grosse erreur rouge « Impossible de charger la Bible : Route inconnue. »** | **ERREUR E-B1 (CRITIQUE)** — la liste des livres est ABSENTE ; l'écran affiche une erreur au lieu du texte |
| Routes | — | 404 « Route inconnue » sur **5 routes** : `/bible/versions`, `/bible/livres?version=lsg1910`, `/bible/recherche?q=Psaume+23&version=lsg1910`, `/bible/strong/recherche?q=H1`, `/bible/dictionnaire/recherche?q=amour&langue=fra` | Le repli hors ligne ne se déclenche pas sur un 404 (il ne se déclenche que sur une erreur réseau, code `hors_ligne` — vérifié dans `http_api_service.dart`) — les actifs JSON embarqués existent dans le build mais ne sont pas utilisés quand le serveur répond 404. **Défaut du build T9, pas de la projection.** |
| Sélecteur de version | LSG / KJV attendus (choix de Bouf) | **Aucun sélecteur de version affiché** — KJV inaccessible | **ERREUR E-B7** — version KJV impossible à atteindre |
| Recherche Psaume 23 | « Rechercher un livre ou un passage » | Recherche « Psaume 23 » → « Recherche impossible : Route inconnue. » ; navigation par livre impossible (liste vide) | **ERREUR E-B8** — aucun passage affichable |
| Concordance / Dictionnaire | (écrans T9, pas de maquette détaillée) | Les écrans s'ouvrent (« Concordance Strong », champ « Numéro Strong ou mot (ex. H1, father) » ; « Dictionnaire biblique (français) », champ « Rechercher un mot (ex. Moïse) ») mais chaque recherche échoue : « Recherche impossible : Route inconnue. » | **ERREUR E-B9** — écrans présents, données absentes (même cause 404) |
| Arrière-plan | Carte blanche | Plein écran violet foncé | **ERREUR E-B2** — fond différent (violet foncé au lieu de blanc) |
| En-tête | « ← Retour à mon espace / Ma Bible / Votre Bible, dans votre interface. Choisissez un testament, puis un livre. » | **Aucun en-tête, aucun titre « Ma Bible », aucune flèche retour** — le haut de l'écran (bande 0–140 px) est un aplat violet uniforme (42,0,89) | **ERREUR E-B3** — en-tête absent |
| Texte d'intro + boutons Concordance / Dictionnaire | Visibles sur fond clair | **Rendus sombre-sur-sombre sur fond violet #2A0059, invisibles** (bande 0–140 px uniformément (42,0,89)) ; les boutons existent et fonctionnent (clics vérifiés en (478,100) et (802,100) → ouverture des écrans 36/37) mais un utilisateur ne peut pas les découvrir | **ERREUR E-B4 (CRITIQUE)** — contenu invisible : ~140 px / ~3,7 cm de haut illisibles |
| Sélecteur de testament | « Ancien Testament » (actif, foncé) / « Nouveau Testament » | Moitié gauche « ✓ Ancien Testament » (lavande clair) ; **moitié droite vide — libellé « Nouveau Testament » invisible/absent** | **ERREUR E-B5** — libellé manquant (~130 px / ~3,4 cm) |
| Placeholder de recherche | « Rechercher un livre ou un passage » | « Rechercher dans le texte (ex. berger) » | **ERREUR E-B6** — texte différent |

En ligne : Bible **ABSENTE** (aucune rubrique Bible ; carte Modules « Bible et école — T9 · À venir », clic → « Bible et école biblique : tranche T9 en cours, pas encore en ligne. ») — écart attendu : le site déployé est antérieur à la T9.

### 10. Navigation — rail (1280) vs barre du bas (400) — RÉSOLU
Projection : cadre téléphone 400 px avec barre du bas Accueil / Membres / Finances / Départements.
Appli locale à 1280 : rail latéral gauche (icônes + libellés) + tiroir (☰). Appli locale à 400 px (`captures/40-phone-accueil.png`, `41-phone-membres.png`) : **barre du bas Accueil / Membres / Finances / Départements, pilule dorée sur l'actif — identique à la projection**. **CONFORME (comportement adaptatif)** : le rail n'est pas un écart, c'est la mise en page tablette/bureau ; à largeur téléphone l'appli bascule sur la même navigation que la projection.
Écarts relevés à 400 px : sous-titres des cartes statistiques toujours tronqués (« Personnes inscrit… », « Présences pointé… ») — voir E-A3 ; bouton « Nouveau membre » en double — voir E-M6.

### 11. Tiroir (menu latéral) — navigation de l'appli
Appli locale : `captures/08-tiroir.png`, `10-tiroir-bas.png`, `11-tiroir-bas2.png` — En ligne : `captures-en-ligne/05-tiroir.png`, `05b-tiroir-bas.png`.
Items du tiroir : TEST (badge « Église mère », ESC-4240, Admin d'église), « Changer d'église », Cultes et Présences, Suivi pastoral, Rendez-vous, Prières, Serviteurs, Gouvernance, Confiance, Rapports d'annexe, Mes annexes et Réseau, Mon abonnement, Modules de l'église, Réglages, À propos de e-System Ch…, Se déconnecter.
**Observations** : pas de « Bible », pas d'« École biblique », pas de « Rapports consolidé » dans le tiroir (la Bible vit uniquement dans l'espace fidèle ; le consolidé n'est accessible que depuis un rapport reçu). L'item « À propos de e-System Ch… » est **tronqué** (« À propos de e-System Church » coupé, ~60 px / ~1,6 cm). Les écrans de chaque item sont capturés et comparés au § 14.

### 12. Espace fidèle — écrans détaillés (enfant B, TERMINÉ 14/11 ~20:42)
Captures `captures/34-bible-kjv.png` à `captures/43-fidele-messages.png` — toutes vérifiées visuellement, aucune n'est un aplat.

#### 12a. École biblique — `38-ecole-biblique.png`
| Zone | Projection (`bible.png`) | Appli locale T9 | Écart |
|---|---|---|---|
| Contenu | « École biblique, cours / Aucun cours publié / Les cours créés par la structure apparaîtront ici, leçon par leçon. / Ma progression 0 % / 0 leçon terminée sur 0. » | En-tête « ← École biblique » correct, puis **« Impossible de charger les cours : Route inconnue. »** (404 `/cours-ecole`, `/inscriptions-ecole` ; `PAGEERROR Error` journalisé) + bouton « + » doré | **ERREUR E-EB1** — erreur affichée au lieu de l'état vide attendu (« Aucun cours publié ») |
| Ma progression | « Ma progression 0 % / 0 leçon terminée sur 0. » | **Absente** | **ERREUR E-EB2** — section absente |
| Bouton « + » | Absent (le fidèle ne crée pas de cours) | Bouton « + » doré en bas à droite | Observation — création de cours exposée dans l'espace fidèle (aperçu admin ?) |

#### 12b. Mes cotisations — `39-cotisations.png`
| Zone | Projection (`membre-cotisations.png`) | Appli locale T9 | Écart |
|---|---|---|---|
| Contenu | « TOTAL COTISÉ 0 FCFA / 0 cotisation / Historique / DATE MONTANT REÇU / Aucune cotisation pour le moment / Payer ma cotisation » | En-tête « ← Mes cotisations » correct, puis **« Action non autorisée pour le rôle « admin_eglise ». »** (403 `GET /moi/contributions`) + bouton « Réessayer » | **ERREUR E-CO1** — l'aperçu fidèle par un admin ne peut pas afficher les cotisations ; « Réessayer » redéclenche le même 403. Contrairement à Carte/Messages (voir 12d–12e), aucun message d'aperçu explicite |
| Total / Payer | « TOTAL COTISÉ 0 FCFA / Payer ma cotisation » | **Absents** | **ERREUR E-CO2** — total et paiement absents |

#### 12c. Mon journal — `40-journal.png`
Projection `membre-journal.png` : « Mes notes 0 note / Aucune note pour le moment / Nouvelle note / Exporter en JSON / Importer en JSON ». Appli : journal **local fonctionnel, état vide correct** (« Aucune note pour le moment… », « 0 notes », « + Nouvelle note », Export/Import JSON), aucun appel API. **CONFORME** — l'un des rares écrans fidèles sans écart.

#### 12d. Plus (Mon menu) — `41-fidele-plus.png`
Projection `fidele-plus.png` : « Mon menu / Tout votre espace, en un seul endroit. / Prendre rendez-vous / Mon journal / Mes cotisations / Mes camps / Mes attestations / Prière du jour / Sujet de prière privé / Paramètres / À propos de e-System Church / DÉMONSTRATION Voir l'espace admin / Se déconnecter / Tu es un don de Dieu ».
Appli : mêmes items dans le même ordre, plus **« Transparence financière »** et **« Carte dans le portefeuille »** insérés entre « Mes attestations » et « Prière du jour » — **ERREUR E-PL1** (2 items en trop, ordre modifié). Section « COMPTE » au lieu de « DÉMONSTRATION » — **ERREUR E-PL2** (libellé de section différent). « Se déconnecter » et « Tu es un don de Dieu » sont sous le pli de la capture (non visibles) — non vérifiés ici.

#### 12e. Carte — `42-fidele-carte.png` ; Messages — `43-fidele-messages.png`
- Carte : « En aperçu, la carte d'un membre n'est pas visible. Connectez-vous avec un compte fidèle pour voir votre carte. » — **gestion d'aperçu explicite, CONFORME** en tant que telle ; la vraie carte (projection `fidele-carte.png` : Photo, Nom, Matricule, ÉGLISE, MEMBRE DEPUIS) n'est pas vérifiable avec ce compte (réserve, voir § F).
- Messages : « En aperçu, la conversation privée du fidèle ne s'affiche pas. » — **gestion d'aperçu explicite, CONFORME** ; un 403 `/moi/messages` est journalisé en arrière-plan (même pattern que E-CO1, mais géré proprement ici).

### 13. Site en ligne — écrans détaillés (enfant C, TERMINÉ 14/11 ~20:57)
Captures `captures-en-ligne/06-fidele-accueil.png` à `12-confiance-en-ligne.png` — toutes vérifiées visuellement. **Limite de méthode (headless)** : les clics sur les tuiles/boutons de la zone de contenu sont inertes en headless (md5 identique avant/après clic, 4 tentatives) alors que les lignes du tiroir naviguent normalement — deux écrans n'ont pas pu être atteints en headless (voir 13d). Les lenteurs Render (~30–40 s de réveil) s'ajoutent.

#### 13a. Accueil fidèle + Mes accès (en ligne) — `06-fidele-accueil.png`, `07-fidele-mes-acces.png`
Accueil fidèle en ligne = pixel-identique au local (même sha256 que `12-fidele-accueil.png`) : bandeau « Mode Aperçu Fidèle », « Bonjour, TEST », carte membre, « PROCHAIN CULTE — Aucun culte prévu ». Mêmes erreurs E-FI1 à E-FI5, E-FI10.
Grille « MES ACCÈS » en ligne : **Ma Bible, Mes cotisations, Mon journal, Messagerie** — **sans « École biblique »** (build pré-T9, correct) et **dans l'ordre de la projection** (Ma Bible, Mes cotisations, Mon journal, Message à mon église). Le build local T9, lui, insère « École biblique » en 2e position — voir E-FI6. Sous-titre « Mes cotisations : Historique, reçus et total. » (projection : « Historique, reçus et total à 0 FCFA. » — « à 0 FCFA » manquant, ~60 px / ~1,6 cm) ; « Messagerie » au lieu de « Message à mon église ». Mêmes cartes géantes vides qu'en local (E-FI7, ~420 px de haut).

#### 13b. Cultes en ligne — `08-cultes-en-ligne.png`
« Cultes en direct : Aucun culte planifié pour l'instant. » + « Planifier un culte » — pixel-identique au local (même sha256 que `09-cultes.png`). Mêmes erreurs E-C1 à E-C4.

#### 13c. Modules en ligne — `09-modules-en-ligne.png`, `09b-modules-bible-en-ligne.png`
Projection `modules.png` : 13 cartes (T1–T13) + Connexion, chacune avec son badge de tranche.
| Zone | Projection | Site en ligne | Écart |
|---|---|---|---|
| Titre / sous-titre | « Tous les modules / T1 à T13 / Chaque module de l'application finale, construit ou prévu. » | « Tous les modules » + badge doré « T1 à T13 » + « Chaque module de l'application finale, construit ou prévu. **Tous les modules sont affichés pour toutes les églises.** » | **ERREUR E-MO2** — phrase ajoutée en trop (~70 px / ~1,8 cm) — reflète la règle de Bouf « tous les modules affichés pour tous » |
| Cartes | 13 cartes : Accueil admin (T3), Espace membre (T2), Membres et familles (T4), Cultes en direct (T5), Radar pastoral (T6), Finances (T7), Bible et école (T9), Gouvernance (T10), Réglages et confiance (T11), Paiements automatiques (T8), US restantes (T12), Qualité (T13), Connexion (T1) | Mêmes titres et sous-titres (textes identiques à la projection) + **carte supplémentaire « Cartes de membre / Voir les cartes et les imprimer. »** (sans badge de tranche, entre Membres et familles et Cultes en direct) | **ERREUR E-MO1** — carte en trop (14e carte) |
| Tuile Bible et école | « Bible et école / Lecture, cours et progression des membres. / T9 · À venir » | **« Bible et école — Lecture, cours et progression des membres. — T9 · À venir »** (entre Finances T7 et Gouvernance T10) | CONFORME (libellé) — mais le détail derrière la tuile n'a pas pu être ouvert en headless (clic inerte, voir 13d) |
| Hauteur des cartes | Cartes compactes (~90 px) | Cartes géantes ~480 px de haut pour 2 lignes de texte, ~300 px de vide par carte | **ERREUR E-MO3** — même défaut systémique que E-FI7 (~300 px / ~7,9 cm de vide par carte) |

#### 13d. Rapports reçus en ligne — `10-rapports-recus-en-ligne.png` — NON ATTEINT EN HEADLESS
Le fichier montre le bas du tableau de bord avec le bouton « Ouvrir les rapports reçus » : **le bouton est inerte en headless** (clic souris après molette + 5 s, drag-scroll + clic, tap tactile — aucun effet, md5 avant/après identique). L'écran Rapports reçus n'a donc **pas pu être atteint par l'enfant C**, et le bug « Impossible de charger les rapports reçus. » **n'a pas pu être re-vérifié par lui**. **E-L2 reste établi par l'audit en navigateur réel du 14/11** (erreur persistante après « Réessayer », vérifiée par l'agent navigateur du parent). Suite indiquée : contrôle en navigateur réel, pas une autre passe headless. En local, l'écran a été atteint par le tiroir (capture 20, § 14g).

#### 13e. Gouvernance en ligne — `11-gouvernance-en-ligne.png`
Projection `gouvernance.png` (T10 « À venir ») : Mandats, Nominations, Procès-verbaux, Documents — avec états vides (« Aucun mandat en cours », « Aucune nomination », « Aucun procès-verbal », « Aucun document classé »).
Appli : liste de **8 lignes** : Mandats, Nominations, **Réunions et décisions**, Procès-verbaux, Documents, **Certificats, Action sociale, Patrimoine** — **ERREUR E-G1** (4 sections en trop : Réunions et décisions, Certificats, Action sociale, Patrimoine) ; **ERREUR E-G2** (ordre : « Réunions et décisions » insérée en 3e position). Sous-titres descriptifs quasi identiques à la projection (« Mandats des responsables, avec leurs dates. », « Chaque nomination garde sa décision et sa date d'effet. »…). **ERREUR E-G3** : aucun état vide « Aucun… » affiché sur la liste (les écrans de détail derrière les lignes n'ont pas été ouverts — les états vides y vivent peut-être). Structure : la projection montre 4 blocs sur un écran ; l'appli est une liste de 8 sous-écrans (1 niveau de navigation en plus).

#### 13f. Confiance en ligne — `12-confiance-en-ligne.png`
Projection `reglages.png` (T11 « À venir ») : « Réglages et confiance » — Sauvegarde, Mode hors ligne, Notifications, Double authentification (2FA), Journal d'audit.
Appli : écran **« Confiance »** à part (l'écran « Réglages » de l'enfant A, n° 24, détient le reste) — 5 lignes : Sauvegardes, File hors ligne, Double authentification, Journal d'audit, Notifications.
**ERREUR E-CF1** — ordre différent : Notifications passe de la 3e place (projection) à la 5e (appli) ; 2FA et Journal permutés. **ERREUR E-CF2** — libellés différents : « Sauvegardes » (vs « Sauvegarde »), « File hors ligne » (vs « Mode hors ligne »), « Double authentification » (vs « Double authentification, 2FA »). **ERREUR E-CF3** — sous-titres entièrement différents (descriptions de la fonction : « Sauvegarde chiffrée de l'église, restauration testée. », « Code à 6 chiffres pour Pasteur, Trésorier et Admin. »…) au lieu des textes d'état de la projection. **ERREUR E-CF4** — la projection a UN écran « Réglages et confiance » ; l'appli en a DEUX (« Réglages » + « Confiance »).

### 14. Tiroir + Finances (enfant A — captures intégrées par le coordinateur)
L'enfant A a capturé 14–33 (tailles réelles, aucune page d'erreur dans ses journaux — tous « (aucun log) »). Ses captures 14–17 initiales (écrans violets vides, 4 716 o) ont été re-capturées (28 931 / 19 060 / 34 050 / 31 988 o). Son rapport écrit n'est pas arrivé (silence ~32 min, dernière activité 20:56 UTC) — les sections ci-dessous sont rédigées par le coordinateur à partir des captures elles-mêmes, vérifiées visuellement une par une. 18-gouvernance, 19-confiance et 23-modules (local) sont **byte-identiques** (même sha256) à leurs homologues en ligne 11/12/09 → voir § 13e/13f/13c.

#### 14a. Suivi pastoral (= Radar pastoral) — `14-suivi-pastoral.png`
Projection `radar.png` : « Radar pastoral et rendez-vous / Absences consécutives / Aucune absence signalée / Rendez-vous / Aucun rendez-vous / Matin Après-midi Soir / Visites / Aucune visite planifiée / Accompagnements / Aucun accompagnement en cours ».
Appli : titre « Suivi pastoral », onglets Radar (actif) / Parcours / Visites / Accompagnements ; texte « Attention bienveillante : le radar signale les membres absents plusieurs cultes de suite, pour organiser un appel ou une visite, jamais une sanction. » + menu « 3 cultes » ; état vide « Aucune alerte pour l'instant. »
**ERREUR E-R1** — titre « Suivi pastoral » au lieu de « Radar pastoral et rendez-vous ». **ERREUR E-R2** — structure par onglets au lieu d'une page unique : les sections Rendez-vous (Matin/Après-midi/Soir), Visites et Accompagnements ne sont pas visibles sur l'onglet Radar (leurs contenus n'ont pas été capturés — voir § F). **ERREUR E-R3** — onglet « Parcours » en trop (le parcours vit dans l'espace fidèle, pas dans le radar). **ERREUR E-R4** — texte « Attention bienveillante… » en trop (~2 lignes, ~50 px). **ERREUR E-R5** — réglage « 3 cultes » en trop. **ERREUR E-R6** — état vide « Aucune alerte pour l'instant. » au lieu de « Aucune absence signalée / Le radar se remplit à partir des pointages de présence. » (2e phrase manquante). **ERREUR E-R7** — icône gâteau en haut à droite, sans libellé (probablement les anniversaires — rien ne l'indique).

#### 14b. Rendez-vous — `15-rendez-vous.png`
Filtres « ✓ Tous / En attente / Confirmé / Refusé / Annulé » ; état vide « Aucun rendez-vous pour l'instant. »
**ERREUR E-RV1** — créneaux Matin/Après-midi/Soir absents de cette vue (liste de gestion par statut, pas la vue par créneaux de la projection). **ERREUR E-RV2** — texte « Aucun rendez-vous pour l'instant. » au lieu de « Aucun rendez-vous / Les demandes approuvées apparaîtront ici avec leur créneau. » (2e phrase manquante). Le formulaire fidèle « Prendre rendez-vous » (projection `fidele-rendezvous.png`) n'a pas été capturé — voir § F.

#### 14c. Prières — `16-prieres.png`
Onglets « Demandes de prière » / « Messages internes » ; recherche « Rechercher une demande de prière » ; filtres « ✓ Toutes / Nouvelles / En cours / Terminées » ; état vide « Aucune demande de prière pour l'instant. » + bouton pleine largeur « Créer une demande » + bouton flottant doré « + Nouvelle demande ».
Pas d'écran « Prières » dans la projection (le sujet de prière privé vit dans l'espace fidèle). Écran fonctionnel, état vide correct. **Observation E-PR1** — bouton d'action en double (pleine largeur + flottant, même action, ~48 px chacun) — même motif que E-M6.

#### 14d. Serviteurs — `17-serviteurs.png`
Onglets « Affectations » / « Planning » ; recherche « Rechercher un serviteur » ; menu « Département : Tous les départements » ; état vide « Aucun serviteur affecté pour l'instant. » + bouton pleine largeur « Affecter un serviteur » + bouton flottant doré « + Nouveau serviteur ».
Pas d'écran « Serviteurs » dans la projection. Écran fonctionnel, état vide correct. Même motif bouton double (libellés légèrement différents : « Affecter un serviteur » vs « Nouveau serviteur »).

#### 14e. Gouvernance (local) — `18-gouvernance.png` ; Confiance (local) — `19-confiance.png`
Byte-identiques (même sha256) à `captures-en-ligne/11-gouvernance-en-ligne.png` et `12-confiance-en-ligne.png` → voir § 13e (E-G1 à E-G3) et § 13f (E-CF1 à E-CF4).

#### 14f. Modules (local) — `23-modules.png`, `23b-modules-bible.png`
Byte-identique (même sha256) à `captures-en-ligne/09-modules-en-ligne.png` → voir § 13c (E-MO1 à E-MO3). La capture 23b (grille défilée) montre la tuile « Bible et école / Lecture, cours et progression des membres. » — le clic sur la tuile n'a produit **aucun dialogue visible** en headless (même limitation que § 13d : tuiles inertes en headless). Le message périmé « Bible et école biblique : tranche T9 en cours, pas encore en ligne. » **n'a été ni confirmé ni infirmé en local** (il est confirmé en ligne par l'audit en navigateur réel). Le badge de la tuile locale n'est pas visible sur cette capture (sous le pli — non affirmé absent).

#### 14g. Rapports reçus (local, via le tiroir) — `20-rapports-annexe.png` — CORRECTION IMPORTANTE
L'item « Rapports d'annexe » du tiroir ouvre l'écran « Rapports reçus » — **qui fonctionne en local T9** (aucune erreur) : « Les rapports envoyés par vos églises annexes arrivent ici, et aussi par e-mail. » + carte « Statistiques et exports / Chiffres du réseau, exports CSV et PDF. » + « Aucun rapport reçu pour l'instant. » + carte EXEMPLE « Bilan annuel / EXEMPLE / Envoyé par une église annexe. Rapport d'exemple, avec des chiffres d'exemple. / [Ouvrir] ».
Projection `rapports-recus.png` : même intro, même carte EXEMPLE, même bouton « Ouvrir ». **Quasi CONFORME** — **ERREUR E-RR1** : carte « Statistiques et exports » en trop. **ERREUR E-RR2** : ligne « Aucun rapport reçu pour l'instant. » en trop (la projection ne montre que la carte exemple). **Conséquence** : le correctif `_call` de la T9 fonctionne — la liste des rapports reçus s'affiche ; c'est le build en ligne (pré-T9) qui échoue (E-L2). Le détail ouvert par « Ouvrir » sur la carte exemple (vue consolidée, projection `rapport-exemple.png`) n'a pas été capturé — voir § F. Le chemin par le bouton « Ouvrir les rapports reçus » du tableau de bord, lui, est inerte en headless (captures 33, identiques à l'en-ligne 10) — voir § 13d.

#### 14h. Mes annexes — `21-mes-annexes.png`
Recherche « Rechercher une annexe » ; 4 lignes : Transferts de membres, Arbre du réseau, Demandes de rattachement, Alertes du réseau ; état vide « Aucune annexe pour l'instant. Une église se rattache à vous avec votre code permanent ou un code de tutelle, depuis « Demandes de rattachement ». » + bouton « Voir les demandes de rattachement » + bouton flottant doré « Code de tutelle ».
Pas d'écran « Mes annexes » dans la projection. Écran fonctionnel, état vide riche et correct (mention du code permanent et du code de tutelle, conforme au système à deux codes).

#### 14i. Mon abonnement — `22-abonnement.png`
« L'abonnement de votre église mère. / MON PLAN / Abonnement annuel / 200 000 FCFA par an. Il couvre l'église mère et toutes ses annexes. / Essai gratuit : 30 jours pour essayer l'application avant de payer. / Statut : Actif / Date d'expiration : À compléter / DURÉE / Choisissez la durée. La remise grandit avec la durée. / 1 an 200 000 FCFA / 3 ans 540 000 FCFA, au lieu de 600 000 FCFA / 10 ans 1 600 000 FCFA, au lieu de 2 000 000 FCFA / Total pour 1 an : 200 000 FCFA / La remise de durée est déjà incluse dans le total affiché. / CODE PROMO… »
Projection `abonnement.png` : mêmes montants, mêmes textes. **Quasi CONFORME** — **ERREUR E-AB1** (mineure) : « Essai gratuit : 30 jours » et « Pour essayer l'application avant de payer. » fusionnés en une seule ligne en gras au lieu de deux lignes. Contenu sous le pli (Code promo, IMPORTANT lecture seule, Renouveler, « Voir la vue d'une annexe ») non vérifié sur cette capture — voir § F.

#### 14j. Réglages — `24-reglages.png`
Sections ÉGLISE : « Paramètres de l'église / Coordonnées, paiements mobiles, devise, fuseau horaire, rôles et journal d'audit. », « Mon église / Logo, présentation, horaires des cultes, pasteur et antennes. », « Biens de l'église / Salles, réservations, matériel et maintenance. », « Listes configurables / Rôles, catégories, statuts, départements, seuils et dîme suggérée. », « Consultations sensibles / Qui a consulté les données sensibles. » ; section COMPTE : « Changer mon mot de passe / Vérifie l'ancien mot de passe. Les autres sessions sont déconnectées. »
Projection `reglages.png` (« Réglages et confiance ») : Sauvegarde, Mode hors ligne, Notifications, 2FA, Journal d'audit — **aucun de ces 5 items n'est sur cet écran** (ils vivent dans « Confiance », voir § 13f).
**ERREUR E-RG1** — l'écran unique « Réglages et confiance » de la projection est scindé en deux (« Réglages » + « Confiance »). **ERREUR E-RG2** — 6 rubriques sans équivalent dans la projection (Paramètres de l'église, Mon église, Biens de l'église, Listes configurables, Consultations sensibles, Changer mon mot de passe). Note positive : « Mon église / Logo, présentation, horaires des cultes, pasteur et antennes » et « Paramètres de l'église / … devise, fuseau horaire… » appliquent directement l'exigence d'identité de Bouf (logo + présentation + devise + fuseau par église).

#### 14k. À propos — `25-a-propos.png`
Grande carte violette avec le logo ESC, « e-System Church », « « L'église sans frontière » » en or ; « C'EST QUOI » (texte identique à la projection), « SON OBJECTIF » (texte identique), « SON UTILITÉ » (« Pour la Plateforme — Voir l'ensemble des églises. / Pour l'église mère — Gérer son église et ses annexes. » — suite sous le pli).
**ERREUR E-AP1** — carte héros violette ~220 px de haut (~5,8 cm) au lieu de l'en-tête compact de la projection (petit badge « eS » + titre). **ERREUR E-AP2** — titre « À propos » au lieu de « ← Retour ». Textes « C'est quoi » et « Son objectif » **CONFORMES** (identiques). « Son créateur » et « Version et contact » (dont le +1 873 307 5022 de la projection) sous le pli — non vérifiés sur cette capture (voir § F).

#### 14l. Finances — sous-écrans (27–31) + Cellules (32)
- **Campagnes** (`27-campagnes.png`) : « Aucune campagne pour l'instant. » + FAB « + Nouvelle campagne ». OK.
- **Promesses de don** (`28-promesses.png`) : « Rien pour le moment. » + FAB « + Nouvelle promesse ». **Observation E-PR2** — état vide générique (« Rien pour le moment. ») au lieu d'un « Aucune promesse… » explicite.
- **Dons en nature** (`29-dons-nature.png`) : « Les dons en nature ne comptent pas dans les totaux financiers. » + « Rien pour le moment. » + FAB « + Nouveau don en nature ». Même observation (E-DN1).
- **Transparence financière** (`30-transparence.png`) : « TEST · 2026-11 / Totaux seulement, aucune ligne nominative. » ; RECETTES 0 FCFA / DÉPENSES 0 FCFA (rouge) / SOLDE 0 FCFA ; sections « PAR TYPE » et « PAR POSTE » **sans aucun contenu** (ni ligne ni état vide). **ERREUR E-TR1** — sections vides sans état vide explicite (~100 px de vide sous chaque titre).
- **Budget & caisse** (`31-budget-caisse.png`) : onglets Budget / Dépenses / Caisse / Rapport / Suivi mensuel ; recherche « Rechercher un poste budgétaire » ; **8 POSTES BUDGÉTAIRES prédéfinis** : Électricité, Eau, Transports, Cas sociaux, Location de sono, Achat d'équipement, Maintenance, Location d'équipement (chaque ligne : Dépense · code catégorie · libellé · Récurrente/Ponctuelle ; icônes modifier/supprimer) + FAB « + Poste ». **ERREUR E-BU1 (QUESTION POUR BOUF)** — la projection attend « Budgets par département / Aucun budget défini » pour une église vierge ; l'appli affiche 8 postes prédéfinis (modèles des catégories 01–10 du schéma). Montants à 0 — pas d'argent inventé — mais les postes existent sans avoir été créés : modèles ou données inventées ? Les onglets Dépenses / Caisse / Rapport / Suivi mensuel n'ont pas été capturés (voir § F).
- **Cellules** (`32-cellules.png`, onglet de Départements) : « Aucune cellule pour l'instant / Appuyez sur le bouton + en bas pour en créer une. » + FAB « + Cellule ». OK.

#### 14m. Rapports reçus via le bouton du tableau de bord — `33-rapports-recus.png` (+ `33-mid.png`, `33-mid2.png`, `33-probe.png`)
Les 4 captures sont **byte-identiques** (même sha256) à `captures-en-ligne/10-rapports-recus-en-ligne.png` : le bas du tableau de bord avec le bouton « Ouvrir les rapports reçus » — le bouton est inerte en headless (local comme en ligne). Voir § 13d. L'écran lui-même fonctionne en local via le tiroir (voir § 14g).

## B. Couleurs & logo (projection couleurs & logo)

Référence : `Projection_couleurs_logo_e-System_Church.html` — « La même application finale, recolorée avec la palette du logo, violet et or. Application vierge, aucun membre, 0 FCFA partout. » Palette : violet profond #2A0059 / #3D0073, or #E8B820 / #F2C230, violets clairs #D9CCF2 / #EFE9F7 / #DCD2F0, ors #5c4a08 / #e6d48f / #8A6A12. Logo : « Icône ESC, carré violet, ruban or et lettres blanches ». Slogan : « L'église sans frontière ».
Badges de la projection : Or = tranche construite et fusionnée ; Violet profond = tranche construite ; Gris = écran final prévu, non construit.

| Point | Attendu | Appli (locale + en ligne) | Verdict |
|---|---|---|---|
| Palette globale | Violet #2A0059 / #3D0073 + or #E8B820 / #F2C230, fonds #EFE9F7 | Mesuré : #2A0059 (boutons, titres), #E8B820 (pilules, badges), #F6F2FB (fond) | **CONFORME** |
| Logo ESC | Carré violet, ruban or, lettres blanches — connexion, en-têtes | Présent sur la connexion et en haut à droite de chaque écran | **CONFORME** |
| Slogan | « L'église sans frontière » | Présent sur la connexion | **CONFORME** |
| Badges des tranches | Or / Violet / Gris par écran | L'appli n'affiche pas de badges de tranche sur les écrans (les états de tranche vivent dans l'écran Modules) | Écart de présentation — à préciser avec la capture Modules (enfant A, n° 23 ; en ligne, enfant C, n° 09) |
| Écrans « Gris » (non construits) | Gouvernance (T10), Réglages (T11), Paiements (T8), US restantes (T12), Qualité (T13), Bible admin (T9) | L'appli A des écrans Gouvernance / Confiance / Réglages / Paiements (contenu à comparer — enfant A/C) ; l'écran admin « Bible et école biblique » n'existe pas (la Bible vit dans l'espace fidèle) | À compléter avec les captures 18, 19, 24 (A) et 11, 12 (C) |

---

## C. Site en ligne vs Projection couleurs & logo (priorité de Bouf)

Site : https://e-system-church-web.onrender.com — captures `captures-en-ligne/01-connexion.png`, `01b-connexion-remplie.png`, `02-accueil.png`, `02b-accueil-bas.png`, `03-membres.png`, `04-finances.png`, `05-tiroir.png`, `05b-tiroir-bas.png` (+ audit navigateur indépendant, 14/11 : connexion, accueil, membres, finances, finances complètes, cultes, départements, modules).

| Point | Projection couleurs & logo | Site en ligne | Verdict |
|---|---|---|---|
| Palette | Violet #2A0059 / or #E8B820, fond #EFE9F7 | Mêmes couleurs mesurées que le local (#2A0059, #E8B820, #F6F2FB) | **CONFORME** |
| Logo | Carré violet / ruban or / lettres blanches | Présent (connexion + en-têtes) | **CONFORME** |
| Slogan | « L'église sans frontière » | Présent sur la connexion | **CONFORME** |
| Accueil | Voir § A.2 | Pixel-identique au build local (même sha256) | Mêmes erreurs E-A1 à E-A6 |
| Membres | Voir § A.3 | Pixel-identique au local | Mêmes erreurs E-M1 à E-M6 |
| Finances | Voir § A.4–A.5 | Finances complètes OK (4 cartes, 0 FCFA partout) | Voir E-F0 ; contenu Finances complètes CONFORME |
| Cultes | Conducteur, transposition, portes, QR | « Aucun culte planifié pour l'instant. » ; chargement ~10 s | **ERREUR E-C1 à E-C4** (mêmes qu'en local) + lenteur ~10 s |
| Bible + École biblique | Ma Bible (livres, passage), École (cours, progression) | **ABSENTES** : aucune rubrique Bible ; Modules → carte « Bible et école — T9 · À venir », clic → « Bible et école biblique : tranche T9 en cours, pas encore en ligne. » | **ERREUR E-L1 (MAJEURE)** — nouveautés T9 absentes du site déployé (build pré-T9 ; disparaîtra à la fusion de la PR #107 + redéploiement) |
| Rapports reçus | « Rapports reçus / Bilan annuel EXEMPLE / Ouvrir » | **« Impossible de charger les rapports reçus. » + bouton « Réessayer » — persistant après « Réessayer »** | **ERREUR E-L2 (MAJEURE)** — écran inutilisable en ligne ; cause : bug `_call` (tableau JSON nu) déjà corrigé dans le code T9 (PR #107) — et la liste fonctionne en local T9 via le tiroir (§ 14g) |
| Départements | (onglet de Membres) | OK (Familles / Cellules, « Aucune famille pour l'instant ») | Voir E-D1 |
| Modules | 13 cartes avec badges Or/Violet/Gris | OK (T1–T13 listés, ex. « T10 · Construit en ligne », « Bible et école — T9 · À venir ») | À préciser avec la capture 09 (enfant C) |
| Lenteurs | — | Écran violet vide ~30–40 s au premier chargement (réveil Render) ; ~10 s sur Cultes ; statistiques différées sur l'accueil | **ERREUR E-L3** — temps de chargement (pas un écart de contenu, mais un écart d'expérience : la projection s'affiche instantanément) |

---

## D. Top 5 des écarts les plus importants (final)

1. **Toute la Bible inutilisable en local (T9) — E-B1, E-B7 à E-B9** : 404 « Route inconnue » sur 5 routes (`/bible/versions`, `/bible/livres`, `/bible/recherche`, `/bible/strong/recherche`, `/bible/dictionnaire/recherche`) ; le repli hors ligne ne se déclenche pas sur un 404 ; pas de sélecteur LSG/KJV, pas de liste de livres, pas de Psaume 23. La fonction phare de la T9 est inutilisable contre l'API de production.
2. **Écran Bible en partie invisible — E-B4, E-B5** : texte d'intro et boutons Concordance/Dictionnaire rendus sombre-sur-sombre sur fond #2A0059 (bande 0–140 px uniformément (42,0,89)) ; libellé « Nouveau Testament » invisible ; aucun en-tête ni retour. Les boutons existent mais ne peuvent pas être découverts.
3. **Bible + École biblique absentes du site en ligne — E-L1** : le site déployé est pré-T9 ; « tranche T9 en cours, pas encore en ligne. »
4. **École biblique en erreur + Mes cotisations refusées (aperçu admin) — E-EB1, E-EB2, E-CO1, E-CO2** : « Impossible de charger les cours : Route inconnue. » au lieu de « Aucun cours publié » ; « Ma progression » absente ; « Action non autorisée pour le rôle « admin_eglise ». » (403) sur Mes cotisations — sans le message d'aperçu explicite qu'ont Carte et Messages.
5. **Rapports reçus en échec persistant (en ligne) — E-L2** : « Impossible de charger les rapports reçus. », même après « Réessayer ». Nuance : la liste fonctionne en local T9 via le tiroir (§ 14g) — le correctif `_call` est dans le code T9 ; c'est le build déployé (pré-T9) qui échoue.
Suivent de près : Cultes en direct vide de ses fonctions (E-C1 à E-C4) ; espace membre incomplet (E-FI5, E-FI8, E-FI9) ; **8 postes budgétaires prédéfinis** dans une église vierge (E-BU1 — modèles ou données inventées ?) ; défaut systémique des cartes géantes vides (E-FI7, E-MO3, ~300–330 px de vide par carte) ; sous-titres des statistiques tronqués (E-A3, ~60 px / ~1,6 cm).

## E. Écrans de l'appli absents de la projection
- **Finances — onglet Contributions** (Dîmes / Offrandes / Dons / Dépenses confirmés + Campagnes, Promesses, Dons en nature, Transparence, Budget & caisse) : aucun écran équivalent dans la projection (la projection n'a que « Finances complètes »).
- **Départements** (Familles / Cellules, Fiche d'un membre, Enfants & jeunesse) : la projection met les Familles dans l'écran Membres.
- **Serviteurs, Prières, Mes annexes et Réseau, Changer d'église** : rubriques du tiroir sans écran de projection dédié (à confirmer avec les captures 16, 17, 21 de l'enfant A).
- **École biblique dans l'espace fidèle** : la projection finale la place dans l'écran admin « Bible et école biblique » (T9 « À venir ») ; l'appli la met dans l'espace fidèle.

## F. Non-vérifiables / réserves
- **Détail d'un rapport (vue consolidée)** : la LISTE des rapports reçus fonctionne en local T9 via le tiroir (capture 20, § 14g — carte EXEMPLE présente) ; en revanche le détail ouvert par « Ouvrir » sur la carte exemple (vue consolidée, projection `rapport-exemple.png` : Membres 120, Recettes 2 450 000 FCFA…) n'a pas été capturé — le clic n'a pas été tenté en headless (boutons de contenu inertes). L'écran « Rapports à mon église mère » (projection `rapports-mere.png`, flux en 5 étapes) n'a pas pu être comparé dans son contexte réel (TEST n'a pas de mère).
- **Conducteur de culte** : n'apparaît peut-être que pendant un culte en cours ; créer un culte est interdit (lecture seule) → E-C1 à E-C4 portent une réserve.
- **Section MON ÉGLISE MÈRE** (accueil) : TEST n'a pas d'église mère → E-A6 non vérifiable avec ce compte.
- **« Anniversaires » et « Fréquentation »** (onglets Membres) : absents de l'appli ; introuvables ailleurs (E-M1).
- **Écran SYCEBNL** : existe dans le code (`sycebnl_screen.dart`) ; accès depuis Finances complètes non encore capturé.
- **Limite headless (constat de l'enfant C)** : en Chromium headless, les clics sur les tuiles/boutons de la zone de contenu sont inertes (md5 identique avant/après, 4 tentatives) alors que les lignes du tiroir naviguent normalement. Conséquences : l'écran Rapports reçus en ligne n'a pas pu être atteint en headless (E-L2 reste établi par l'audit en navigateur réel) ; en local, le même écran a été atteint par le tiroir (§ 14g) — seule la voie « bouton du tableau de bord » est inerte ; le détail derrière la tuile « Bible et école » de Modules n'a pas pu être ouvert en headless (le message « tranche T9 en cours… » reste établi par l'audit en navigateur réel). Un contrôle en navigateur réel est la suite indiquée pour ces deux points.
- **Vue membre réelle** : les captures fidèles sont en mode « Aperçu Fidèle » (admin) — bannière et badge « Église mère » peuvent ne pas exister dans la vraie vue membre (E-FI2, E-FI4).
- **Annexe** : aucun compte annexe testé ; les écrans « Mon abonnement » version annexe (`abonnement-annexe.png` : « Votre accès est couvert par l'abonnement de votre église mère ») et « Rapports à mon église mère » n'ont pas pu être comparés dans leur contexte réel.
- **Formulaire « Prendre rendez-vous » (fidèle)** : présent dans le menu Plus (capture 41), mais le formulaire lui-même (projection `fidele-rendezvous.png` : pasteur, date, créneau, motif) n'a pas été ouvert — non vérifié.
- **Contenus d'onglets non ouverts** : Suivi pastoral, onglets Parcours / Visites / Accompagnements (seul l'onglet Radar est capturé) ; Budget & caisse, onglets Dépenses / Caisse / Rapport / Suivi mensuel (seul l'onglet Budget est capturé) ; Prières, onglet « Messages internes » ; Serviteurs, onglet « Planning ».
- **Bas de pages non capturés (sous le pli)** : Abonnement (Code promo, encadré IMPORTANT lecture seule, « Renouveler mon abonnement », « Voir la vue d'une annexe ») ; À propos (« Son créateur », « Version et contact » dont le +1 873 307 5022 de la projection) ; Finances complètes (Reçus numérotés, Budgets par département, section SYCEBNL) ; Modules (badges des tuiles sous le pli, dont celui de « Bible et école » en local).
- **Numérotation des captures** : les n° 40 et 41 de l'enfant B (Journal, Plus) recoupent ceux des captures téléphone (40-phone-accueil.png, 41-phone-membres.png) — aucun écrasement : noms de fichiers différents (40-journal.png, 41-fidele-plus.png). Simple confusion de numérotation.

## Captures
- Appli locale : `~/workspace/audit-t9-app/captures/` (01 à 13, 40, 41 + captures des enfants 14–33, 34–43)
- Site en ligne : `~/workspace/audit-t9-app/captures-en-ligne/` (01 à 05b + captures de l'enfant C 06–12)
- Projection : `~/workspace/audit-t9-app/captures-projection/finale/` (30 écrans) et `~/workspace/audit-t9-app/captures-projection/couleurs/` (30 écrans)
- Scripts : `~/workspace/audit-t9-app/step*.mjs` (modèle : step8.mjs ; téléphone : step14-phone.mjs)
