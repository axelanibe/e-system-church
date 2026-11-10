# Note pour Lotte IA — e-System Church (nouveau projet, séparé)

> ⚠️ **Projet séparé de Connexion Prophétique.** Ne pas mélanger les deux chantiers :
> Connexion Prophétique = une seule structure, son appli, son dépôt, son issue #9.
> e-System Church = une plateforme pour **toutes** les églises de Côte d'Ivoire.
> Aucun fichier, aucune PR, aucun commentaire d'e-System Church ne va dans le dépôt
> Connexion-prophetique. Un dépôt GitHub dédié sera créé pour e-System Church.

## 1. Le concept (demande de Bouf, 10 novembre 2026)

Une application qui **centralise des églises en Côte d'Ivoire**, nommée **e-System Church**.

Exemple donné par Bouf : « moi je suis l'église A, je me connecte à l'interface,
je m'inscris en tant qu'admin, j'ai la possibilité d'ajouter des sous-églises.
Ces sous-églises pourront choisir dans le système leur église principale et,
à partir de leur église principale, créer des sous-églises, avec des systèmes
de gestion intégrés. »

## 2. Arborescence

- **Plateforme** (super-admin e-System Church) : annuaire des églises, validation des inscriptions.
- **Église mère** : s'inscrit comme admin, crée ses sous-églises (antennes).
- **Sous-église** : a son propre admin, ses propres membres, ses propres finances.
  Elle choisit son église mère dans le système (code d'invitation ou demande à valider).
  Elle peut elle-même devenir mère et créer ses propres antennes. Pas de limite de niveaux.
- **Isolation stricte** : chaque église ne voit que ses données (même règle que
  « pas de chevauchement entre cliniques » sur SanteCI Connect : chaque requête
  filtrée par l'église de l'utilisateur). L'église mère voit un tableau de bord
  **consolidé** (totaux, pas le détail d'une antenne sauf autorisation).

## 3. Modules de gestion intégrés (dans chaque église)

- **Membres** : inscription, carte de membre avec QR, départements, groupes et cellules, suivi des nouveaux convertis.
- **Finances** : dîmes, offrandes, dons, dépenses, reçus automatiques — Wave, Orange Money, MTN MoMo.
- **Cultes et événements** : planning, présences par scan QR, intervenants, programmes.
- **Communication** : annonces, notifications dans l'appli, SMS.
- **Médias** : prédications audio/vidéo, Bible Louis Segond.
- **Rapports** : chaque antenne remonte ses chiffres, la mère les consolide.

## 4. Où on en est (10 novembre 2026)

- Proposition d'architecture faite par Phoenix, validée dans son principe par Bouf.
- **Maquette démo interactive livrée le 10/11** (dans le Muse de Bouf, artefact
  « e-System Church — Maquette démo », données fictives : réseau « Grâce Divine »,
  mère au Plateau, sous-églises Yopougon, Bouaké, Yamoussoukro, San Pedro).
  5 écrans : vue d'ensemble consolidée, arborescence avec ajout de sous-église,
  gestion par église (membres, finances, cultes et présences), inscription en
  4 étapes (devenir mère ou rejoindre une mère), annonces + rapports.
- Aucun dépôt GitHub, aucun code : le projet n'existe que comme proposition + maquette.
- **Questions ouvertes pour Bouf** : inscription libre pour toute église, ou
  seulement sur invitation d'une mère ? Dons sur le compte de chaque église, ou
  centralisés puis redistribués ?

## 5. Technique proposée (à confirmer)

Repartir de ce qu'on maîtrise : Flutter (Android / iOS / web), backend Fastify +
PostgreSQL, pensé pour la Côte d'Ivoire (connexion faible, français, Mobile Money).
Même discipline que sur Connexion Prophétique : branches dédiées rebasées sur main,
PR, jamais de push direct sur main, ne rien inventer, ne pas reconstruire ce qui existe.

## 6. Feuille de route proposée

1. **MVP** : inscription, arborescence mère / sous-églises, membres + finances de base.
2. **V2** : cultes, présences, communication, rapports consolidés.
3. **V3** : annuaire public des églises, médias, application membre.

## 7. Ce qui t'est demandé

- Prends connaissance du projet et de la maquette (Bouf te la partagera).
- Dis si tu prends le chantier et par quoi tu commencerais : architecture / schéma
  de base de données, ou directement le MVP.
- Répartition des tokens décidée par Bouf le 08/11 : les travaux lourds vont à toi,
  Phoenix garde vérifications, petites corrections et coordination.

*Note préparée par Phoenix, 10 novembre 2026. En attente du dépôt GitHub dédié
(Bouf doit le créer, l'intégration ne peut pas créer de dépôt) pour y ouvrir
l'issue de suivi d'e-System Church.*
