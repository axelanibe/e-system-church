# Notifications push FCM : ce qu'Axel doit fournir

Branche `notifications-push-fcm`, base main `50445da7` (T-Msg-0 fusionnée).
Le code est prêt à brancher. Aucun secret n'est dans le dépôt.

## Ce qui est déjà fait

- Projet Firebase séparé `e-system-church`, créé dans le même compte Google que
  CONNEXION PROPHÉTIQUE (compte cile0225@gmail.com), sans Google Analytics.
  Les deux applications ne partagent pas le même projet, leurs notifications
  ne se mélangent pas.
- Application Android enregistrée, paquet `ci.esystemchurch.esystem_church`.
  Le fichier `google-services.json` est téléchargé, vérifié et déposé dans
  `app/android/app/google-services.json`. Le plugin `google-services` 4.4.2
  est appliqué dans les fichiers Gradle.
- Application web « e-System Church Web » enregistrée. Sa configuration est
  intégrée dans `app/lib/firebase_options.dart` et dans le service worker
  `app/web/firebase-messaging-sw.js` (arrière-plan web).
- Serveur : migration 035 (table `device_tokens`), routes
  `POST /messagerie/jetons`, `GET /messagerie/jetons`,
  `DELETE /messagerie/jetons`, envoi FCM aux participants d'une conversation
  sauf l'expéditeur, avec le titre de la conversation et un aperçu tronqué.
  Le compte de service est lu uniquement depuis la variable d'environnement
  `FIREBASE_SERVICE_ACCOUNT_JSON`. Sans lui, l'envoi est désactivé
  proprement et journalisé, sans casser la création du message.
- Application : paquets `firebase_core` et `firebase_messaging`, demande
  d'autorisation, enregistrement et retrait du jeton, gestion des
  notifications en avant-plan, en arrière-plan et application fermée
  (ouverture de la messagerie au toucher). Sans configuration Firebase,
  le service se désactive proprement, sans planter.

## Ce qu'Axel doit encore fournir

### 1. Compte de service pour le serveur (obligatoire pour envoyer)

Dans la console Firebase, projet `e-system-church` :
- Paramètres du projet, Comptes de service, Générer une nouvelle clé privée.
- Copier le contenu complet du fichier JSON généré, et le saisir dans Render,
  service API e-System Church, comme variable d'environnement
  `FIREBASE_SERVICE_ACCOUNT_JSON` (le JSON complet, en une seule variable).
- Redéployer le service API pour que la variable soit prise en compte.

Tant que cette variable est absente, le serveur n'envoie aucune notification
(comportement voulu et testé). La création du message n'est jamais bloquée.

### 2. Clé VAPID pour la push web (obligatoire pour le web)

Dans la console Firebase, projet `e-system-church` :
- Paramètres du projet, Cloud Messaging, certificat Web Push, Générer une
  paire de clés.
- Communiquer la clé publique VAPID à Muse, qui l'ajoutera à la configuration
  web de l'application.

Sans cette clé, la push sur le web reste inactive (sans plantage). Android
n'est pas concerné.

### 3. Saveur `demo` : à trancher

Le fichier `google-services.json` ne contient que le paquet de production
`ci.esystemchurch.esystem_church`. Un build `--flavor demo` échouera
(« No matching client found ») tant que l'application demo n'est pas
enregistrée dans le projet Firebase.

Choix : enregistrer l'application Android `ci.esystemchurch.esystem_church.demo`
dans le projet `e-system-church`, puis re-télécharger `google-services.json`
et le redéposer, ou accepter que les builds demo restent impossibles.

## Étapes de branchement, une fois les éléments fournis

1. Saisir `FIREBASE_SERVICE_ACCOUNT_JSON` dans Render, redéployer l'API.
2. Ajouter la clé VAPID à la configuration web, pousser et redéployer le site.
3. Vérifier de bout en bout : un membre envoie un message, le destinataire
   reçoit la notification sur son téléphone et sur le web, le toucher ouvre
   la conversation. Un jeton révoqué doit passer inactif côté serveur.
4. Confirmer le run CI APK (`--flavor prod`) : il validera définitivement
   l'intégration Android (Gradle ne peut pas être exécuté localement sur
   cette machine).

## Limites connues

- Le serveur exige une fiche membre liée pour enregistrer un jeton. Un admin
  sans fiche membre aura la push inactive, sans plantage côté client.
- Les plateformes acceptées côté serveur sont `web` et `android` seulement.
  Il n'y a pas d'application iOS dans ce dépôt.
- La push web exige la clé VAPID (point 2). La push Android fonctionne dès
  que le compte de service est en place (point 1).
