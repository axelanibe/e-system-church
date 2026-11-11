# e-System Church — Application Flutter (MVP)

Application mobile / web de la plateforme e-System Church (Côte d'Ivoire) :
inscription d'une église mère ou rattachement à une mère, arborescence,
membres, finances (Wave / Orange Money / MTN MoMo), rapports consolidés,
annonces. Interface en français, Material 3.

L'appli parle uniquement à l'API réelle `server/` (Fastify + PostgreSQL,
JWT bearer). Aucune donnée inventée : l'appli n'affiche que les données
réelles de l'église ; quand il n'y a pas encore de données, les listes
affichent un état vide explicite.

## Prérequis

- Flutter stable récent (SDK ≥ 3.24, Dart ≥ 3.7)
- L'API `server/` lancée (`npm run dev` dans `server/`, PostgreSQL migré
  — voir `server/README.md`)

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

## Connexion à l'API

1. Lancer l'API : `cd server && npm install && npm run migrate && npm run dev`
   (PostgreSQL requis, voir `server/README.md`).
2. Dans l'appli : **Réglages** → saisir l'URL de l'API (par défaut
   `http://localhost:3000`, ou l'URL déployée) → **Enregistrer l'URL** →
   se connecter avec un compte réel (ou en créer un via
   « Inscrire mon église »).

Le jeton JWT est stocké en sécurité (`flutter_secure_storage`) ; il est
effacé à la déconnexion et à chaque changement d'URL.

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
    session_store.dart     # jeton + URL de l'API (stockage sécurisé)
  state/app_state.dart     # session, église active
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

- Paiements : exécution Wave branchée côté serveur ; Orange / MTN /
  M-Pesa / PayPal / Stripe configurables, exécution à brancher (module 14).
- JWT sans révocation côté serveur (30 min web, 2 h mobile).
- Interface en français uniquement (l'anglais viendra plus tard).
