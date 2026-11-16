// Service worker des notifications push FCM sur le web (tranche push FCM).
// Il reçoit les messages quand l'application est en arrière-plan ou
// fermée et affiche la notification. Même projet Firebase `e-system-church`
// et même application web « e-System Church Web » que `lib/firebase_options.dart`
// (configuration cliente publique, aucune clé de serveur).
// Les messages en avant-plan sont affichés par l'application elle-même
// (bannière avec bouton Ouvrir) et ne passent pas par ce fichier.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDLMbSRL5HzVLsFC3nDOhEw_PR1uKSKxEM',
  authDomain: 'e-system-church.firebaseapp.com',
  projectId: 'e-system-church',
  storageBucket: 'e-system-church.firebasestorage.app',
  messagingSenderId: '487372952475',
  appId: '1:487372952475:web:3ddcf8fe363362dc4e873e',
});

const messaging = firebase.messaging();
