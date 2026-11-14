# Migrations — e-System Church

Migrations numérotées dans `db/migrations/`, appliquées dans l'ordre
alphabétique par `server/src/migrate.ts`, après le schéma initial
`db/schema.sql` (bases vides uniquement). Chaque migration est
enregistrée par son **nom de fichier complet** dans `schema_migrations`.

## Procédure unique (T13, P0-3)

**Toujours `npm run migrate` complet, jamais un fichier seul.**

La procédure historique sur Render — exécuter un fichier seul par
Start Command temporaire — a fait échouer la migration 028 en
production (« relation "mandats" does not exist », PR #89) : le fichier
commençait par des `CREATE INDEX` sur des tables créées plus loin dans
le même fichier. Les tests locaux ne l'avaient pas vu, parce qu'ils
appliquent `db/schema.sql` d'abord. Ne pas reproduire cette procédure.

Après fusion d'une PR qui ajoute une migration : appliquer
`npm run migrate` sur Render (Start Command temporaire, puis retour à
`npm start`), vérifier `/sante` 200.

## Règles d'écriture (vérifiées par `server/test-migrations-t13.mjs`)

1. **Un index ne vise jamais une table créée après lui dans l'ordre
   global** : `db/schema.sql`, puis migrations triées. En pratique, dans
   un fichier, chaque `CREATE INDEX` suit le `CREATE TABLE` de sa table.
   Le garde-fou est le contrôle statique du test, qui reproduit le motif
   exact du bug 028.
2. **Ne jamais renommer une migration déjà appliquée en production** :
   `migrate.ts` la reverrait comme nouvelle et la réappliquerait.
3. **Une migration doit être rejouable par `migrate.ts` sans effet la
   deuxième fois** : le test vérifie que la deuxième exécution
   n'applique rien (`schema_migrations` inchangé).

Limite assumée : l'exécution d'un fichier seul, sur une base vide après
`schema.sql` uniquement, n'est pas exigée — la migration 025 vise
légitimement des tables de la 001 (`caisse_mouvements`) et du schéma
(`contributions`). Le garde-fou contre le bug 028 est le contrôle
statique (règle 1), pas l'exécution isolée.

## Numéros en double — déjà appliqués en production, à ne pas renommer

| Numéro | Fichiers | Contenu |
|---|---|---|
| 001 | `001_fonctionnalites_eglise.sql` | Fonctionnalités d'une église (miroir de l'extension du schéma). |
| 001 | `001_transferts_membre.sql` | Transferts de membre entre branches. |
| 005 | `005_modules_eglise.sql` | Modules activables par église (US1). |
| 005 | `005_rapports_nombres.sql` | Rapports consolidés : agrégats en nombres, pas en chaînes. |
| 011 | `011_ajout_sexe_membre.sql` | Sexe du membre (matricule, système du permis du Québec). |
| 011 | `011_checkins_enfants.sql` | Check-ins enfants, double QR ECODIM. |

Deux fichiers partagent le même préfixe mais pas le même nom complet :
`migrate.ts` les distingue par le nom de fichier. Tout renommage ou
toute migration « 001bis » casserait la traçabilité.

## Numéros manquants

| Numéro | Raison |
|---|---|
| 017 | Trou historique dans la numérotation (aucun fichier 017). |
| 027 | Migration T9 (école biblique + Bible), dans la PR #88 uniquement, pas sur `main`. |

Tout nouveau doublon ou trou fait échouer
`server/test-migrations-t13.mjs` : le documenter ici avant de fusionner.

## Doublon latent assumé

`consultations_sensibles` est créée en 029 puis de nouveau en 030 avec
`IF NOT EXISTS` (défense assumée dans la PR #91 : l'ordre de fusion
n'a donc pas d'importance). À documenter, pas à « corriger » à
l'aveugle en production.
