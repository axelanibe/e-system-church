# User stories — e-System Church (extensions proposées)

Statut : proposition, à valider par Bouf. Format : cahier des charges MVP.
Date : 11 novembre 2026.

## US1 : Modules activables par église

*En tant qu'admin d'une église, je veux activer ou désactiver les modules dont mon église a besoin, afin de n'afficher que les fonctionnalités utiles.*

**Critères d'acceptation**
- À la création, seul le noyau (membres, finances, rapports) est activé.
- Un module désactivé n'apparaît ni dans la navigation ni dans les tableaux de bord.
- Une requête API vers un module désactivé renvoie `403` avec le code `module_desactive`, pour toute église concernée.
- Seul l'`admin_eglise` peut modifier l'activation, et chaque changement est écrit dans `audit_logs`.
- Désactiver un module ne supprime aucune donnée ; le réactiver restaure l'accès à l'identique.

## US2 : Campagnes de collecte

*En tant que trésorier, je veux créer une campagne avec un objectif et une période, afin de suivre les dons qui lui sont affectés.*

**Critères d'acceptation**
- Une campagne comporte un nom, un objectif en FCFA strictement positif, une date de début et une date de fin postérieure, et un statut : brouillon, active ou clôturée.
- Une contribution confirmée peut être affectée à une campagne active de son église. Sans affectation, elle va au fonds général.
- Une contribution ne peut jamais être affectée à une campagne d'une autre église.
- Le total collecté est la somme des contributions confirmées affectées. Au-delà de 100 % de l'objectif, l'écran l'indique explicitement au lieu de le masquer.
- Clôturer une campagne interdit toute nouvelle affectation, sans modifier les contributions déjà enregistrées.
- Si aucune campagne n'existe, l'écran affiche « Aucune campagne pour l'instant ».
- L'église choisit si les membres voient le total de chaque campagne.

## US3 : Attestations annuelles de dons

*En tant que trésorier, je veux générer pour chaque donateur une attestation annuelle, afin qu'il puisse justifier ses contributions.*

**Critères d'acceptation**
- Pour une année civile donnée, le trésorier génère un PDF par donateur identifié, listant ses dons confirmés (date, type, montant en FCFA) et leur total.
- Seules les contributions au statut « confirmé » sont incluses. Les contributions en attente ou annulées sont exclues.
- Chaque attestation porte le nom, le logo et le code unique de l'église, un numéro d'attestation unique et sa date d'émission.
- Un don anonyme, sans fiche membre, ne donne pas lieu à attestation.
- Une attestation émise est figée. Une correction produit une nouvelle attestation qui annule la précédente, et les deux restent tracées dans l'audit.
- Le membre consulte et télécharge ses attestations depuis l'application, et ne voit que les siennes.
- La valeur fiscale de l'attestation ne doit être affirmée qu'après validation par un juriste, selon le droit ivoirien.

## Questions ouvertes

1. Une église mère peut-elle activer des modules pour ses antennes, ou chaque antenne décide-t-elle seule ?
2. Les campagnes doivent-elles être visibles publiquement sur l'espace de présentation de l'église ?
3. Qui valide la valeur juridique des attestations ?

## Intégration au dépôt

Ce fichier est prévu pour `docs/user-stories-mvp-extensions.md`. Selon les règles du dépôt, il doit être ajouté par une branche dédiée rebasée sur `main`, puis une PR, sans push direct sur `main`. Mettre à jour l'issue #1 lors de l'ajout.
