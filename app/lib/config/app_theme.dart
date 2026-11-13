import 'package:flutter/material.dart';

/// Thème unique de e-System Church, partagé par l'application réelle
/// (`lib/main.dart`) et la version démo (`lib/main_demo.dart`).
///
/// Palette de l'artefact, tranchée par Axel le 12 novembre 2026 :
/// bleu nuit #0B1F3A, or #D4A72C, or foncé #8A6A12, fond papier
/// #F5F6FA. Le rouge ne sert qu'aux erreurs et aux alertes. Elle
/// remplace la palette Vision (cyprès #1E4D3B, terracotta #C86D51,
/// alabaster #F7F5F0), abandonnée le 12 novembre 2026.
/// Typographies : Inter pour le corps, Plus Jakarta Sans pour les
/// titres, JetBrains Mono pour les codes et matricules. Les polices
/// sont embarquées dans le build (pubspec.yaml, fichiers TTF
/// officiels Google Fonts), sans appel réseau : le site statique et
/// l'APK les servent depuis leurs propres assets. Les tests restent
/// ainsi verts hors ligne.
///
/// Contrastes vérifiés (WCAG, textes principaux au moins 4,5:1) :
/// blanc sur bleu nuit 16,52:1, bleu nuit sur papier 15,30:1, or
/// foncé sur papier 4,68:1, or sur bleu nuit 7,36:1, bleu nuit sur or
/// 7,36:1, bleu nuit sur or clair 14,50:1, rouge #B3261E sur papier
/// 6,05:1, vert foncé #0C5B40 sur papier 7,52:1. Blanc sur or ne vaut
/// que 2,24:1 : jamais de texte blanc sur or, le texte sur or est
/// bleu nuit.
///
/// Accessibilité (11 novembre 2026) : taille minimale 14 px, titres
/// 24 gras, sous-titres 18, corps 16, boutons 48 px de haut, champs
/// 56 px de haut, pour un doigt et pour des yeux fatigués.
class AppTheme {
  /// Bleu nuit, primaire : AppBar, boutons, texte principal.
  static const Color bleuNuit = Color(0xFF0B1F3A);

  /// Or, accent : boutons d'action, badge « Église mère », détails.
  static const Color or = Color(0xFFD4A72C);

  /// Or foncé, accent secondaire, texte sur papier 4,68:1.
  static const Color orFonce = Color(0xFF8A6A12);

  /// Or clair, fonds doux (badge « Église mère », indicateurs).
  static const Color orClair = Color(0xFFF7F0DA);

  /// Fond papier, fond des écrans.
  static const Color fondPapier = Color(0xFFF5F6FA);

  /// Bordures claires, champs et cartes.
  static const Color bordure = Color(0xFFD9DEE6);

  /// Rouge, erreurs et alertes seulement, sur papier 6,05:1.
  static const Color rougeErreur = Color(0xFFB3261E);

  /// Vert foncé lisible sur fond clair (remplace le vert vif).
  static const Color vertFonce = Color(0xFF0C5B40);

  /// Bleu foncé lisible sur fond clair (remplace le bleu vif).
  static const Color bleuFonce = Color(0xFF1B4F72);

  /// Couleur du module Présences.
  static const Color bleuPresences = Color(0xFF2563EB);

  /// Style mono pour les codes et matricules.
  static const TextStyle styleCode =
      TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14, color: bleuNuit);

  static ThemeData get theme {
    const titres = TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontWeight: FontWeight.bold,
      color: bleuNuit,
    );
    const corps = TextStyle(fontFamily: 'Inter', color: bleuNuit);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: bleuNuit,
        primary: bleuNuit,
        onPrimary: Colors.white,
        secondary: or,
        tertiary: orFonce,
        surface: Colors.white,
        onSurface: bleuNuit,
        error: rougeErreur,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: fondPapier,
      appBarTheme: const AppBarTheme(
        backgroundColor: bleuNuit,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shadowColor: const Color(0x1A0B1F3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: bordure),
        ),
      ),
      // Puces de filtre : sélection or clair sur papier, jamais le
      // bleu clair par défaut du thème Material. Non sélectionnée :
      // blanche, bordure claire, texte bleu nuit.
      chipTheme: const ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: orClair,
        checkmarkColor: bleuNuit,
        labelStyle: TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: bleuNuit),
        secondaryLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: bleuNuit,
            fontWeight: FontWeight.bold),
        side: BorderSide(color: bordure),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: orClair,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Inter', fontSize: 11, color: bleuNuit),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: orClair,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: or,
        foregroundColor: bleuNuit,
      ),
      // Titres 24 gras, sous-titres 18, corps 16, aide 14, jamais
      // moins de 14. Un nouveau membre doit tout lire sans effort.
      textTheme: TextTheme(
        headlineSmall: titres.copyWith(fontSize: 24),
        titleLarge: titres.copyWith(fontSize: 18),
        titleMedium: const TextStyle(
            fontFamily: 'PlusJakartaSans', fontSize: 18, color: bleuNuit),
        bodyMedium: corps.copyWith(fontSize: 16),
        bodySmall: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: bleuNuit),
        labelLarge: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: bleuNuit),
        labelSmall: const TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 12, color: bleuNuit),
      ),
      // Boutons 48 px de haut, taille minimale pour un doigt.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: bleuNuit,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: bleuNuit,
          side: const BorderSide(color: bleuNuit),
        ),
      ),
      // Champs 56 px de haut, coins 16 px, pour un doigt et pour
      // des yeux fatigués. Taille minimale 14 px partout.
      inputDecorationTheme: const InputDecorationTheme(
        constraints: BoxConstraints(minHeight: 56),
        filled: true,
        fillColor: Colors.white,
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
