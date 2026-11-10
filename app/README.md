# e-System Church — Application Flutter (MVP)

Application mobile / web de la plateforme e-System Church (Côte d'Ivoire) :
inscription d'une église mère ou rattachement à une mère, arborescence,
membres, finances (Wave / Orange Money / MTN MoMo), rapports consolidés,
annonces. Interface en français, Material 3.

L'appli parle à l'API `server/` (Fastify + PostgreSQL, JWT bearer) — ou
fonctionne **sans serveur** en **mode démo** (données fictives « Grâce Divine »
en mémoire).

## Prérequis

- Flutter stable récent (SDK ≥ 3.24, Dart ≥ 3.7)
- Pour le mode API réelle : l'API `server/` lancée (`npm run dev` dans
  `server/`, PostgreSQL migré — voir `server/README.md`)

## Lancer

```bash
cd app
flutter pub get

# Web (navigateur)
flutter run -d chrome

# Android (émulateur ou téléphone branché)
flutter run

# Windows / macOS / Linux (bureau)
flutter run -d windows   # ou macos / linux
```

## Modes de fonctionnement

### Mode démo (par défaut)

Aucun serveur requis. L'appli démarre en mode démo : connectez-vous avec
un compte de démonstration (mot de passe : `demo1234`) :

| Compte | Rôle |
| --- | --- |
| `admin@gracedivine.ci` | Admin de l'église mère (Plateau) |
| `admin@yopougon.ci` | Admin de la sous-église de Yopougon |
| `tresorier@gracedivine.ci` | Trésorier du Plateau |
| `membre@gracedivine.ci` | Membre simple du Plateau |

Tout fonctionne : arborescence (Plateau → Yopougon, Bouaké → Bouaké Centre,
Yamoussoukro, San Pedro), ajout de sous-église, demandes de rattachement
(accepter / refuser), membres, finances, annonces. Les données vivent en
mémoire : basculer de mode les réinitialise.

### Mode API réelle

1. Lancer l'API : `cd server && npm install && npm run migrate && npm run dev`
   (PostgreSQL requis, voir `server/README.md`).
2. Dans l'appli : **Réglages** → désactiver « Mode démo » → saisir l'URL
   de l'API (par défaut `http://localhost:3000`, ou l'URL déployée, ex.
   `https://…onrender.com`) → **Enregistrer l'URL** → se connecter avec un
   compte réel (ou en créer un via « Inscrire mon église »).

Le jeton JWT est stocké en sécurité (`flutter_secure_storage`) ; il est
effacé à la déconnexion et à chaque changement de mode ou d'URL.

## Construire

```bash
flutter analyze        # 0 erreur exigée
flutter build web      # build/web/
flutter build apk      # Android (release)
```

## Structure de `lib/`

```
lib/
  main.dart            # bootstrap léger (ChangeNotifierProvider + MaterialApp)
  config/app_config.dart
  models/              # church, member, contribution, rattachement,
                       # announcement, rapport, auth
  services/
    api_service.dart       # interface unique parlée par les écrans
    http_api_service.dart  # API réelle (http + JWT)
    mock_api_service.dart  # mode démo (données en mémoire)
    mock_data.dart         # réseau fictif « Grâce Divine »
    session_store.dart     # jeton + réglages (stockage sécurisé)
  state/app_state.dart     # session, église active, mode démo / API
  screens/             # un fichier par écran (login, register, home,
                       # dashboard, tree, rattachements, membres,
                       # member_form, member_detail, finances,
                       # contribution_form, receipt, annonces, settings)
  utils/format.dart        # montants FCFA, dates (sans intl)
  widgets/common_widgets.dart
```

## Rôles (appliqués par l'API, reflétés dans l'interface)

| Rôle | Droits dans son église |
| --- | --- |
| `admin_eglise` | Tout (églises, rattachements, membres, finances, rapports, annonces) |
| `tresorier` | Finances (lecture + saisie + confirmation), lecture des membres — **pas de création de membre** |
| `responsable_culte` | Membres (lecture + création), lecture des finances |
| `membre` | Lecture des membres, de l'arbre et des annonces — **pas de finances** |

## Limites connues du MVP

- Pas de changement d'église active dans l'interface (un utilisateur de
  plusieurs églises se reconnecte en choisissant son église — V2).
- Paiements Mobile Money enregistrés manuellement (référence) ; pas de
  webhook Wave / Orange / MTN (V2).
- JWT sans révocation côté serveur (30 min web, 2 h mobile).
- Interface en français uniquement (l'anglais viendra plus tard).
