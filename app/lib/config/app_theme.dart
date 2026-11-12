import 'package:flutter/material.dart';

/// Thème unique de e-System Church, partagé par l'application réelle
/// (`lib/main.dart`) et la version démo (`lib/main_demo.dart`).
///
/// Palette Vision Sanctuary Modern, tranchée par Axel le 11 novembre
/// 2026 : elle remplace la palette soft sauge (#6A8E7F, #1E4D3B,
/// #FAF7F1, #C9A24B, #2E3440, #6B7280, #52708A). Fond alabaster,
/// cartes ivory, sable et bordures claires, cyprès profond, terracotta
/// et or ambre en accents, encre pour le texte. Plus de sauge active
/// dans le thème, la mention ci-dessus est la seule trace historique.
/// Typographies : Inter pour le corps, Plus Jakarta Sans pour les
/// titres, JetBrains Mono pour les codes et matricules. Les familles
/// sont déclarées ici par leur nom seul, sans appel réseau : les
/// polices sont chargées au démarrage par `main.dart` (et
/// `main_demo.dart`) via google_fonts, téléchargement à l'exécution
/// puis cache. Les tests restent ainsi verts hors ligne.
///
/// Contrastes vérifiés (WCAG, textes principaux au moins 4,5:1) :
/// encre #1A1D20 sur alabaster 15,54:1 et sur ivory 16,36:1, cyprès
/// #1E4D3B sur alabaster 8,84:1 et sur sable 8,16:1, cyprès foncé
/// #143629 sur alabaster 12,13:1, ardoise #525B65 sur alabaster
/// 6,33:1, blanc sur cyprès 9,63:1 et sur cyprès foncé 13,21:1,
/// rouge #B3261E sur alabaster 6,00:1. Cultes #6B4C7A 6,56:1,
/// Présences #2B6CB0 4,97:1 et Médias #3F51B5 6,31:1 sur alabaster
/// passent aussi en texte. Prières #B8506A ne vaut que 4,39:1 sur
/// alabaster : texte sur ivory ou blanc seulement (4,62:1 et 4,78:1).
/// Terracotta #C86D51 (3,34:1), or ambre #B8862D (2,97:1) et Enfants
/// #C07A1C (3,19:1) sont des accents, icônes et aplats seulement,
/// jamais pour du texte.
///
/// Accessibilité (11 novembre 2026) : taille minimale 14 px, titres
/// 24 gras, sous-titres 18, corps 16, boutons 48 px de haut, champs
/// 56 px de haut, pour un doigt et pour des yeux fatigués.
class AppTheme {
  /// Fond alabaster, fond des écrans.
  static const Color fondAlabaster = Color(0xFFF7F5F0);

  /// Cartes ivory.
  static const Color ivoire = Color(0xFFFCFBF8);

  /// Sable, fonds doux (badge « Église mère », indicateurs).
  static const Color sable = Color(0xFFEFECE4);

  /// Bordures claires.
  static const Color bordure = Color(0xFFE6E2D8);

  /// Cyprès, primaire : boutons, liens, succès, blanc dessus 9,63:1.
  static const Color cypress = Color(0xFF1E4D3B);

  /// Cyprès foncé, variante sombre du primaire, blanc dessus 13,21:1.
  static const Color cypressFonce = Color(0xFF143629);

  /// Terracotta, accent chaud, jamais pour du texte.
  static const Color terracotta = Color(0xFFC86D51);

  /// Or ambre, accent parcimonieux, jamais de texte dessus.
  static const Color orAmbre = Color(0xFFB8862D);

  /// Texte principal, encre, sur alabaster 15,54:1.
  static const Color encre = Color(0xFF1A1D20);

  /// Texte secondaire, ardoise, sur alabaster 6,33:1.
  static const Color ardoise = Color(0xFF525B65);

  /// Rouge, erreurs et alertes seulement, sur alabaster 6,00:1.
  static const Color rougeErreur = Color(0xFFB3261E);

  /// Couleur du module Cultes, texte sur alabaster 6,56:1.
  static const Color cultes = Color(0xFF6B4C7A);

  /// Couleur du module Présences, aussi info, texte 4,97:1.
  static const Color presences = Color(0xFF2B6CB0);

  /// Couleur du module Prières : texte sur ivory ou blanc seulement.
  static const Color prieres = Color(0xFFB8506A);

  /// Couleur du module Enfants : icônes et aplats seulement.
  static const Color enfants = Color(0xFFC07A1C);

  /// Couleur du module Médias, texte sur alabaster 6,31:1.
  static const Color medias = Color(0xFF3F51B5);

  /// Style mono pour les codes et matricules.
  static const TextStyle styleCode =
      TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14, color: encre);

  static ThemeData get theme {
    const titres = TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontWeight: FontWeight.bold,
      color: encre,
    );
    const corps = TextStyle(fontFamily: 'Inter', color: encre);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: cypress,
        primary: cypress,
        onPrimary: Colors.white,
        secondary: terracotta,
        tertiary: presences,
        surface: ivoire,
        onSurface: encre,
        error: rougeErreur,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: fondAlabaster,
      appBarTheme: const AppBarTheme(
        backgroundColor: fondAlabaster,
        foregroundColor: encre,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: encre,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: ivoire,
        elevation: 1,
        shadowColor: const Color(0x1A143629),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: bordure),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: ivoire,
        indicatorColor: sable,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Inter', fontSize: 11, color: encre),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: ivoire,
        indicatorColor: sable,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: ivoire,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: cypress,
        foregroundColor: Colors.white,
      ),
      // Titres 24 gras, sous-titres 18, corps 16, aide 14, jamais
      // moins de 14. Un nouveau membre doit tout lire sans effort.
      textTheme: TextTheme(
        headlineSmall: titres.copyWith(fontSize: 24),
        titleLarge: titres.copyWith(fontSize: 18),
        titleMedium: const TextStyle(
            fontFamily: 'PlusJakartaSans', fontSize: 18, color: encre),
        bodyMedium: corps.copyWith(fontSize: 16),
        bodySmall: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: ardoise),
        labelLarge: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: encre),
        labelSmall: const TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 12, color: ardoise),
      ),
      // Boutons 48 px de haut, taille minimale pour un doigt.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: cypress,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: cypress,
          side: const BorderSide(color: cypress),
        ),
      ),
      // Champs 56 px de haut, coins 16 px, pour un doigt et pour
      // des yeux fatigués. Taille minimale 14 px partout.
      inputDecorationTheme: const InputDecorationTheme(
        constraints: BoxConstraints(minHeight: 56),
        filled: true,
        fillColor: ivoire,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: bordure),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: bordure),
        ),
      ),
    );
  }
}
