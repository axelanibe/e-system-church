/// Configuration de l'application.
class AppConfig {
  /// Nom affiché de l'application.
  static const String appName = 'e-System Church';

  /// Slogan officiel de la plateforme.
  static const String appSlogan = 'L’église sans frontière';

  /// Version affichée dans Réglages.
  static const String appVersion = '0.1.0';

  /// URL de l'API par défaut (mode API réelle, serveur Render en production).
  /// L'URL reste modifiable dans Réglages pour les tests locaux.
  static const String defaultApiBaseUrl = 'https://e-system-church.onrender.com';
}
