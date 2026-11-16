import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Configuration Firebase de l'application e-System Church, projet
/// `e-system-church` (projet Firebase séparé, même compte Google que
/// CONNEXION PROPHÉTIQUE, jamais le projet `connexion-prophetique`).
/// Application web « e-System Church Web », enregistrée le 16 nov. 2026.
///
/// Ce fichier ne porte que la configuration cliente du web (clé API
/// publique de l'application web, sans droit côté serveur) : aucune
/// clé de serveur, aucun compte de service. L'envoi des notifications
/// côté serveur passe par un compte de service, saisi dans Render,
/// jamais dans le dépôt.
///
/// Sur Android, la configuration vient de `android/app/google-services.json`
/// (même projet, paquet `ci.esystemchurch.esystem_church`), lue par le
/// plugin google-services : [currentPlatform] ne sert donc que pour le web.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Android lit google-services.json, pas ce fichier.
        throw UnsupportedError(
          'DefaultFirebaseOptions ne sert pas à Android : la '
          'configuration vient de google-services.json.',
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions n’est pas configuré pour cette plateforme.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDLMbSRL5HzVLsFC3nDOhEw_PR1uKSKxEM',
    authDomain: 'e-system-church.firebaseapp.com',
    projectId: 'e-system-church',
    storageBucket: 'e-system-church.firebasestorage.app',
    messagingSenderId: '487372952475',
    appId: '1:487372952475:web:3ddcf8fe363362dc4e873e',
  );
}
