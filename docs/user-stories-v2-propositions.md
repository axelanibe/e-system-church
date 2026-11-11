# User stories — e-System Church (propositions V2)

Statut : proposition, à valider par Bouf et par les églises qui utiliseront la plateforme. Format : cahier des charges MVP.
Date : 11 novembre 2026.

Suite de `docs/user-stories-mvp-extensions.md` (US1 modules activables, US2 campagnes de collecte, US3 attestations annuelles de dons). Les idées ci-dessous viennent de la lecture du dépôt. Ce sont des propositions, pas des décisions. Aucune n'est implémentée. Les sujets de prière restent par e-mail seulement, jamais par WhatsApp ni par notification.

## US4 : Promesses de don

*En tant que membre, je veux m'engager à donner une somme sur plusieurs mois, afin que mon église sache ce qui est promis et ce qui est reçu.*

**Critères d'acceptation**
- Une promesse comporte un montant total en FCFA strictement positif, une période, et un échéancier en versements.
- Le système affiche, pour chaque promesse, ce qui est promis, ce qui est reçu et ce qui reste à recevoir.
- Un versement reçu est une contribution confirmée, rattachée à la promesse et à l'église du membre, jamais à une autre église.
- Une relance est envoyée seulement aux dates prévues, jamais plus d'une fois par échéance, et seulement au membre concerné.
- Annuler une promesse ne supprime pas les versements déjà reçus ; l'historique reste visible.
- Seul l'`admin_eglise` et le trésorier voient l'ensemble des promesses ; un membre ne voit que les siennes.

## US5 : Dons en nature

*En tant que trésorier, je veux enregistrer un don en nature, matériel, nourriture ou temps de bénévolat, afin qu'il soit compté sans passer par les finances en argent.*

**Critères d'acceptation**
- Un don en nature comporte une description, une quantité, une unité, une date, et le donateur quand il est identifié.
- Il est enregistré séparément des contributions en argent ; il n'entre jamais dans les totaux financiers ni dans le solde.
- Le temps de bénévolat est enregistré en heures, sans valeur monétaire imposée.
- Un don en nature anonyme est accepté, sans fiche membre.
- Seul l'`admin_eglise` et le trésorier peuvent créer ou modifier un don en nature, et chaque changement est écrit dans `audit_logs`.
- Le membre voit ses propres dons en nature dans son historique, jamais ceux des autres membres.

## US6 : Fiche visiteur et suivi des nouveaux

*En tant que responsable d'accueil, je veux enregistrer un visiteur de passage, afin de le recontacter et de suivre les nouveaux.*

**Critères d'acceptation**
- Une fiche visiteur comporte un nom, une date de venue, l'église ou l'antenne visitée, et un moyen de contact quand le visiteur l'a donné.
- Aucun champ n'est obligatoire sauf le nom et la date de venue ; un visiteur qui ne donne pas ses coordonnées reste enregistrable.
- Une relance d'accueil est proposée après la visite, une seule fois, et seulement si un contact a été donné.
- Un visiteur devient membre par le parcours d'inscription existant, sans ressaisie de sa fiche ; la fiche reste liée à son dossier.
- Un visiteur n'apparaît jamais dans les listes de membres ni dans les finances, tant qu'il n'est pas devenu membre.
- Seuls les responsables désignés par l'`admin_eglise` voient les fiches visiteurs de leur église.

## US7 : Rappels d'événements de vie

*En tant que pasteur, je veux être alerté des anniversaires et des événements de vie des membres, afin de renforcer le suivi pastoral sans effort de mémoire.*

**Critères d'acceptation**
- Les événements suivis sont : anniversaire, anniversaire de mariage, anniversaire de conversion et anniversaire de baptême, avec la date renseignée par le membre ou par un responsable.
- Une alerte est envoyée au pasteur ou à la cellule concernée, quelques jours avant la date, jamais au réseau entier.
- Un membre peut masquer un événement de vie ; il n'apparaît alors dans aucune alerte.
- Aucune donnée de vie n'est visible par un membre qui n'a pas le rôle pour la voir.
- L'alerte ne contient que le prénom, le type d'événement et la date, jamais d'autre donnée du dossier.

## US8 : Transparence financière agrégée

*En tant que membre, je veux voir une vue simple des totaux et de l'usage des fonds de mon église, afin d'avoir confiance dans la gestion.*

**Critères d'acceptation**
- La vue montre les totaux par type et par période, et l'usage des fonds par poste, sans aucun détail nominatif.
- Aucun membre, aucune contribution individuelle et aucun montant individuel n'y apparaît.
- Les chiffres affichés sont les mêmes que ceux du rapport consolidé, pour la même période.
- L'église choisit si cette vue est visible par tous ses membres ou seulement par son bureau.
- Une antenne voit la vue de sa propre église mère, jamais celle d'une autre église mère.

## US9 : Carte de membre dans le portefeuille du téléphone

*En tant que membre, je veux afficher ma carte avec son QR dans Apple Wallet ou Google Wallet, afin de pointer au culte sans ouvrir l'application.*

**Critères d'acceptation**
- La carte du portefeuille reprend le nom, le matricule et le QR de la carte de membre existante, sans donnée nouvelle.
- Elle est générée seulement à la demande du membre, depuis sa propre carte.
- Le QR reste lisible par le scan de présences existant ; un QR du portefeuille refusé par une autre église est rejeté comme celui de l'application.
- La carte est révoquée quand la carte de membre est révoquée ou quand le membre quitte l'église.
- Aucune donnée du portefeuille n'est envoyée au serveur, sauf la demande de génération.

## US10 : Communication via WhatsApp

*En tant qu'admin d'une église, je veux envoyer des annonces par WhatsApp, afin de joindre les membres là où ils lisent déjà leurs messages.*

**Critères d'acceptation**
- WhatsApp est un canal en plus, jamais un remplacement des annonces dans l'application ni des e-mails.
- Un membre ne reçoit rien par WhatsApp sans son consentement explicite, donné et modifiable dans l'application.
- Chaque envoi respecte l'opt-out : un membre désinscrit ne reçoit plus rien, et son choix est enregistré.
- Les sujets de prière ne passent jamais par WhatsApp, ils restent par e-mail seulement.
- L'envoi est limité aux membres de l'église qui envoie, avec le numéro enregistré dans leur dossier, jamais à une autre église.
- Le coût de chaque envoi, s'il y en a un, est visible par l'`admin_eglise` avant l'envoi.

## US11 : Alertes pour la mère

*En tant qu'admin d'une église mère, je veux être alerté des anomalies de mes antennes, afin d'agir avant que la situation ne se dégrade.*

**Critères d'acceptation**
- Les alertes suivent : antenne inactive depuis plusieurs semaines, contributions en baisse sur la période, rapport non soumis à la date attendue.
- Chaque alerte indique l'antenne concernée, le type d'anomalie et la période, sans détail nominatif.
- Une alerte n'est envoyée qu'une fois par antenne et par type, tant qu'elle n'est pas traitée.
- Traiter une alerte la ferme, avec la date et la personne qui l'a fermée, et l'action reste dans `audit_logs`.
- Une antenne ne voit jamais les alertes d'une autre antenne.

## US12 : Rôles et catégories configurables

*En tant qu'admin d'une église, je veux configurer les rôles et les catégories de mon église, afin qu'ils correspondent à notre organisation réelle.*

**Critères d'acceptation**
- Les rôles, par exemple pasteur, trésorier, secrétaire, et les catégories, par exemple postes de dépense et de recette, sont configurables par église, jamais figés dans le code.
- Modifier un rôle ou une catégorie ne supprime aucune donnée existante ; les enregistrements gardent leur ancienne valeur, marquée comme archivée.
- Un rôle configuré ne donne jamais plus de droits que ceux prévus par son niveau ; la sécurité reste vérifiée côté serveur, par `church_id` et par rôle.
- Seul l'`admin_eglise` peut modifier la configuration, et chaque changement est écrit dans `audit_logs`.
- La configuration d'une église ne s'applique jamais à une autre église.

## US13 : Statuts de membre et départements configurables

*En tant qu'admin d'une église, je veux configurer les statuts de membre et les départements, afin qu'ils correspondent à notre église.*

**Critères d'acceptation**
- Les statuts de membre et les départements sont configurables par église, avec au moins un statut actif par défaut.
- Une église pentecôtiste, une église catholique et une église de jeunes peuvent avoir des listes différentes, sans se gêner.
- Changer la liste ne change pas le statut des membres existants ; un statut retiré reste affiché sur les dossiers existants, marqué comme archivé.
- Seul l'`admin_eglise` peut modifier la configuration, et chaque changement est écrit dans `audit_logs`.
- La carte de membre affiche le statut et le département du membre, selon la configuration de son église.

## US14 : Seuils et montants suggérés

*En tant qu'admin d'une église, je veux proposer un montant de référence configurable pour la dîme, afin d'aider les membres sans jamais l'imposer.*

**Critères d'acceptation**
- Le montant de référence est configurable par église, en FCFA, et peut être désactivé.
- Il est affiché comme une suggestion, avec une formulation qui respecte la liberté du donateur, jamais comme un montant dû.
- Aucun blocage ni aucune relance n'est déclenché par un montant inférieur à la suggestion.
- Le montant saisi par le membre reste libre ; la suggestion ne modifie jamais une contribution.
- Seul l'`admin_eglise` peut modifier la suggestion, et chaque changement est écrit dans `audit_logs`.

## US15 : Langue

*En tant que membre, je veux utiliser l'application en français d'abord, puis en anglais, afin qu'elle serve aussi les églises à l'étranger.*

**Critères d'acceptation**
- Le français est la langue par défaut de toute l'application.
- L'anglais arrive tôt, pour les écrans principaux d'abord : connexion, accueil, membres, finances et carte.
- La langue se choisit dans l'application, par membre, et elle est conservée d'une session à l'autre.
- Les messages d'erreur et les libellés existent dans les deux langues ; aucun texte français ne reste en dur dans l'écran anglais.
- Les données saisies par les membres ne sont jamais traduites automatiquement.

## US16 : Mode économique

*En tant que membre sur une connexion très faible, je veux un affichage léger qui fonctionne en dégradé, afin d'utiliser l'application sans attendre.*

**Critères d'acceptation**
- Le mode économique réduit les images et les listes longues, et affiche un texte plus lisible.
- Les actions essentielles, consulter sa carte, voir ses présences, restent possibles sur connexion très faible.
- Un repli sur SMS est proposé pour les actions essentielles quand la connexion est indisponible, avec le consentement du membre.
- Le mode économique est activable par le membre, et l'application le propose automatiquement quand la connexion est très faible.
- Aucune donnée n'est perdue en mode économique ; les actions en attente sont rejouées quand la connexion revient.

## US17 : Confidentialité par défaut

*En tant que membre, je veux que mes données sensibles soient masquées par défaut, afin qu'elles ne soient visibles que selon le rôle.*

**Critères d'acceptation**
- Les données sensibles, baptême, situation familiale, prières, sont masquées par défaut.
- Elles ne sont visibles que selon le rôle, et seulement pour l'église du membre concerné.
- Chaque consultation d'une donnée sensible est écrite dans un historique des consultations, avec la date, la personne et le motif.
- Un membre voit l'historique des consultations de son propre dossier.
- Aucune donnée sensible n'apparaît dans les exports, les rapports consolidés ni les annonces.

## Questions ouvertes

1. Qui valide le contenu et le prix des envois WhatsApp, et quel opérateur ou prestataire est retenu en Côte d'Ivoire ?
2. La carte dans le portefeuille du téléphone doit-elle être disponible pour toutes les églises, ou seulement pour celles qui l'activent ?
3. Le repli SMS du mode économique est-il facturé à l'église ou au membre, et avec quel plafond ?
4. Qui valide la valeur juridique des attestations annuelles de dons, déjà posée en US3 ?

## Intégration au dépôt

Ce fichier est prévu pour `docs/user-stories-v2-propositions.md`. Selon les règles du dépôt, il doit être ajouté par une branche dédiée rebasée sur `main`, puis une PR, sans push direct sur `main`. Mettre à jour l'issue #1 lors de l'ajout.
