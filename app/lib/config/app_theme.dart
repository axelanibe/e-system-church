import 'package:flutter/material.dart';

/// Thème unique de e-System Church, partagé par l'application réelle
/// (`lib/main.dart`) et la version démo (`lib/main_demo.dart`).
///
/// Palette soft, tranchée par Axel le 11 novembre 2026 (photos du
/// tableau de bord et des Modules à l'appui) : elle remplace la palette
/// bleu nuit et or (#0B1F3A, #D4A72C, #8A6A12, #F5F6FA).
/// Fond papier chaud et doux, cartes blanches, ombres douces, coins
/// arrondis 16 px. AppBar et tiroir en fond papier, plus de bleu nuit
/// plein écran, plus d'en-tête sombre.
///
/// Contrastes vérifiés (WCAG, textes principaux au moins 4,5:1) :
/// ardoise #2E3440 sur papier 11,68:1, sauge foncé #3F5A50 sur papier
/// 7,04:1 et sur blanc 7,53:1, blanc sur sauge foncé 7,53:1, gris doux
/// #6B7280 sur papier 4,52:1, bleu doux #52708A sur blanc 5,19:1,
/// rouge doux #B3261E sur blanc 6,54:1. Le bleu doux demandé #5B7A99
/// ne valait que 4,48:1 sur blanc, il est foncé en #52708A.
/// La sauge #6A8E7F ne vaut que 3,63:1 sur blanc : icônes et aplats
/// seulement, jamais pour du texte. L'or doux #C9A24B n'est qu'un
/// accent parcimonieux : du texte vert foncé dessus ne vaut que
/// 3,14:1, donc jamais de texte sur or, le badge « Église mère »
/// est sauge clair sur fond clair, texte vert foncé 6,30:1.
///
/// Accessibilité (11 novembre 2026) : taille minimale 14 px, corps
/// 16 px, boutons 48 px de haut, pour un doigt et pour des yeux
/// fatigués.
class AppTheme {
  /// Sauge douce, primaire (aplats et icônes, jamais pour du texte).
  static const Color sauge = Color(0xFF6A8E7F);

  /// Sauge foncé, texte et boutons sur fond clair, blanc dessus 7,53:1.
  static const Color saugeFonce = Color(0xFF3F5A50);

  /// Sauge très clair, fond du badge « Église mère », texte sauge
  /// foncé dessus 6,30:1.
  static const Color saugeClair = Color(0xFFE4EDE8);

  /// Or doux et mat, accent parcimonieux, jamais de texte dessus.
  static const Color orDoux = Color(0xFFC9A24B);

  /// Fond papier chaud et doux.
  static const Color fondPapier = Color(0xFFFAF7F1);

  /// Texte principal, ardoise douce, sur papier 11,68:1.
  static const Color ardoise = Color(0xFF2E3440);

  /// Texte secondaire, gris doux, sur papier 4,52:1.
  static const Color grisDoux = Color(0xFF6B7280);

  /// Bleu doux, info, sur blanc 5,19:1.
  static const Color bleuDoux = Color(0xFF52708A);

  /// Rouge doux, erreurs et alertes seulement, sur blanc 6,54:1.
  static const Color rougeErreur = Color(0xFFB3261E);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: sauge,
          primary: saugeFonce,
          onPrimary: Colors.white,
          secondary: orDoux,
          tertiary: bleuDoux,
          surface: const Color(0xFFFFFFFF),
          onSurface: ardoise,
          error: rougeErreur,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: fondPapier,
        appBarTheme: const AppBarTheme(
          backgroundColor: fondPapier,
          foregroundColor: ardoise,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: ardoise,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shadowColor: const Color(0x1A3F5A50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: saugeClair,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11),
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Colors.white,
          indicatorColor: saugeClair,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: saugeFonce,
          foregroundColor: Colors.white,
        ),
        // Taille minimale 14 px, corps de texte 16 px.
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: ardoise),
          bodySmall: TextStyle(fontSize: 14, color: grisDoux),
          titleMedium: TextStyle(color: ardoise),
          titleLarge: TextStyle(color: ardoise),
          headlineSmall: TextStyle(color: ardoise),
        ),
        // Boutons 48 px de haut, taille minimale pour un doigt.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: saugeFonce,
            foregroundColor: Colors.white,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: saugeFonce,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          contentPadding:
              EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
      );
}
