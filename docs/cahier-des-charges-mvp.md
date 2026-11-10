# Cahier des charges — MVP e-System Church (phase 1)

Date : 10 novembre 2026. Statut : fondation posée, à valider par Bouf.
Références : `README.md`, `db/schema.sql`, maquette démo du 10/11
(artefact « e-System Church — Maquette démo » dans le Muse de Bouf).

## 1. Objectif du MVP

Prouver le cœur du concept avec une première église mère et ses sous-églises :
s'inscrire, rattacher des sous-églises, gérer membres et finances, et consolider
les chiffres vers la mère. Rien d'autre dans le MVP.

## 2. Périmètre — IN

### 2.1 Comptes et églises
- Inscription d'une église : nom, ville, téléphone, e-mail, mot de passe.
  Le créateur devient `admin_eglise` de son église.
- Choix à l'inscription : **« Je crée une église mère »** ou
  **« Je rejoins une église mère »** (recherche par nom ou code d'invitation,
  demande en attente de validation par la mère).
- Une église mère crée des sous-églises depuis son tableau de bord
  (elle en devient l'admin initial, transférable ensuite).
- Une sous-église peut créer ses propres antennes (même mécanisme, un niveau plus bas).
- Codes d'invitation uniques par église (`ESC-…`), régénérables.

### 2.2 Membres
- Ajout manuel d'un membre (nom, téléphone, département, cellule).
- Matricule unique **par église**, carte de membre avec QR.
- Recherche par nom ou matricule ; liste avec filtres (département, statut).
- Statuts : actif, nouveau converti, inactif.

### 2.3 Finances
- Enregistrer une dîme, une offrande, un don ou une dépense (montant FCFA,
  moyen de paiement : Wave, Orange Money, MTN MoMo, espèces, virement).
- Référence de paiement Mobile Money ; statut en attente → confirmé / annulé.
- Reçu simple après confirmation. Totaux par type et par période.
- Rôle `tresorier` : il voit et saisit les finances, pas la gestion des membres.

### 2.4 Tableau de bord de l'église mère
- Totaux consolidés du réseau : églises, membres actifs, contributions (nombre
  et montant FCFA) — via la vue `v_rapports_consolides`, agrégats uniquement.
- Liste des sous-églises avec leurs chiffres, demandes de rattachement en attente
  (accepter / refuser).
- Annonce diffusée à tout le réseau en un clic.

### 2.5 Sécurité (non négociable)
- Authentification argon2id ; sessions ; verrouillage après 5 échecs.
- **Isolation** : chaque requête API est filtrée par la `church_id` de la session.
  Un admin de sous-église ne voit jamais les données d'une autre église.
- Journal d'audit (`audit_logs`) sur les actions sensibles.

## 3. Périmètre — OUT (V2 / V3)

- Cultes et présences par scan (tables déjà prévues, écrans en V2).
- Communication SMS / notifications push, médias et Bible (V2 / V3).
- Annuaire public des églises (V3).
- Application membre (V3).
- Paiement Mobile Money **automatique** (webhook Wave / Orange / MTN) : en MVP,
  l'enregistrement est manuel avec référence ; l'automatisation viendra après.

## 4. Parcours types à tester (critères d'acceptation)

1. L'église A s'inscrit comme mère → tableau de bord vide mais fonctionnel.
2. L'église A crée la sous-église de Yopougon → elle apparaît dans l'arbre.
3. Une église existante demande à rejoindre l'église A → A accepte → elle
   apparaît dans l'arbre ; A refuse une autre demande → elle n'apparaît pas.
4. L'admin de Yopougon ajoute 3 membres, enregistre une dîme Wave et une
   offrande en espèces → ses totaux sont justes, l'église A les voit en
   consolidé, l'église de Bouaké ne voit rien de Yopougon.
5. Une sous-église crée sa propre antenne → l'arbre a 3 niveaux.
6. Un trésorier ne peut pas créer de membre ; un membre simple ne voit pas
   les finances.

## 5. API (MVP, Fastify + PostgreSQL)

| Route | Rôle |
| --- | --- |
| `POST /auth/register` | Créer église + admin |
| `POST /auth/login` | Connexion (renvoie l'église, comme SanteCI) |
| `GET /moi/eglise` | Mon église et mon rôle |
| `POST /eglises` | Créer une sous-église (admin de la mère) |
| `GET /eglises/arbre` | Mon arborescence |
| `POST /rattachements` | Demander à rejoindre une mère |
| `POST /rattachements/:id/accepter\|refuser` | Décision de la mère |
| `GET/POST /membres` | Membres de mon église |
| `GET/POST /contributions` | Finances de mon église |
| `GET /rapports/consolide` | Totaux du réseau (mère seulement) |
| `POST /annonces` | Annonce (+ diffusion réseau) |

## 6. Questions ouvertes (pour Bouf, bloquent le MVP si non tranchées)

1. Inscription libre pour toute église, ou seulement sur invitation d'une mère ?
2. Dons sur le compte de chaque église, ou centralisés puis redistribués ?

## 7. Prochaines étapes

1. Bouf valide ce cahier des charges (ou le corrige).
2. Lotte IA : implémentation du MVP (travaux lourds, selon la répartition
   décidée le 08/11) à partir de cette fondation — schéma, routes, écrans.
3. Phoenix : vérifications, petites corrections, coordination (issue #1).
