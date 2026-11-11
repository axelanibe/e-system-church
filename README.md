# e-System Church

> **L’église sans frontière.**

Plateforme de centralisation des églises en Côte d'Ivoire : chaque église s'inscrit,
devient église mère ou rejoint une église mère, crée ses sous-églises, et gère
ses membres, ses finances, ses cultes et sa communication — avec des rapports
consolidés qui remontent vers l'église mère.

> **Projet séparé de Connexion Prophétique.** Ce dépôt ne contient que
> e-System Church. La coordination avec Lotte IA se fait ici (issue #1),
> jamais sur l'issue #9 de Connexion-prophetique.

## Le principe

- **Église A** s'inscrit comme admin (église mère) et ajoute ses sous-églises.
- Une sous-église **choisit son église mère** dans le système (code d'invitation
  ou demande à valider) et peut elle-même créer des sous-églises. Pas de limite
  de niveaux.
- Chaque église a son propre admin, ses propres membres, ses propres finances.
- **Isolation stricte** : une église ne voit que ses données. L'église mère voit
  un tableau de bord **consolidé** (totaux, pas le détail d'une antenne sauf
  autorisation).

```
Plateforme
 └─ Église Mère — [Nom de l'église mère], [Ville]
     ├─ Sous-église — [Ville 1]
     ├─ Sous-église — [Ville 2]
     │   └─ Antenne — [Quartier]
     └─ Sous-église — [Ville 3]
```

## Modules (par église)

| Module | Contenu |
| --- | --- |
| Membres | Inscription, carte de membre avec QR, départements, groupes et cellules |
| Finances | Dîmes, offrandes, dons, dépenses, reçus — Wave, Orange Money, MTN MoMo |
| Cultes et événements | Planning, présences par scan QR, intervenants |
| Communication | Annonces, notifications, SMS |
| Médias | Prédications audio/vidéo, Bible Louis Segond |
| Rapports | Chiffres par antenne, consolidés vers l'église mère |

## Pile technique

- **Application** : Flutter (Android / iOS / web) — même base que Connexion Prophétique.
- **Backend** : TypeScript + Fastify + PostgreSQL.
- **Auth** : argon2id, sessions, 2FA TOTP en option, verrouillage après 5 échecs.
- **Paiements** : Wave, Orange Money, MTN MoMo (Mobile Money, Côte d'Ivoire).
- **Hébergement** : à définir (Render en référence pour Connexion Prophétique).

## Structure du dépôt

```
README.md                  — ce fichier
docs/
  cahier-des-charges-mvp.md — périmètre du MVP (phase 1)
  note-pour-lotte-ia.md     — transmission initiale à Lotte IA
db/
  schema.sql               — schéma PostgreSQL (églises, utilisateurs, membres, finances…)
```

## Feuille de route

1. **MVP** : inscription, arborescence mère / sous-églises, membres + finances de base.
2. **V2** : cultes, présences, communication, rapports consolidés.
3. **V3** : annuaire public des églises, médias, application membre.

Détail : `docs/cahier-des-charges-mvp.md`.

## Règles de travail

- Branches dédiées rebasées sur `main` à jour, PR, jamais de push direct sur `main`.
- Ne pas reconstruire ce qui existe déjà ; vérifier avant d'implémenter.
- Ne rien inventer : pas de chiffres, pas de liens, pas de comptes.
- Répartition décidée par Bouf (08/11) : les travaux lourds vont à Lotte IA,
  Phoenix garde vérifications, petites corrections et coordination.
- Mettre à jour l'issue #1 quand on prend ou termine un chantier.

## Questions ouvertes (pour Bouf)

- Inscription libre pour toute église, ou seulement sur invitation d'une mère ?
- Dons sur le compte de chaque église, ou centralisés puis redistribués ?
