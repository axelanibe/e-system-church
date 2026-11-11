import 'package:flutter/material.dart';

/// Thème unique de e-System Church, partagé par l'application réelle
/// (`lib/main.dart`) et la version démo (`lib/main_demo.dart`).
///
/// Palette officielle, tranchée par Axel le 10 novembre 2026 :
/// bleu nuit #0B1F3A, or #D4A72C, or foncé #8A6A12, fond papier #F5F6FA.
/// Le rouge ne sert qu'aux erreurs et aux alertes.
///
/// Accessibilité (11 novembre 2026) : les couleurs vives de Material
/// (vert #4CAF50, bleu #2196F3, rouge #F44336) sont illisibles en
/// texte ou en icône sur fond clair, elles sont remplacées partout par
/// les foncées ci-dessous. Taille minimale 14 px, corps 16 px, boutons
/// 48 px de haut, pour un doigt et pour des yeux fatigués.
class AppTheme {
  static const Color bleuNuit = Color(0xFF0B1F3A);
  static const Color or = Color(0xFFD4A72C);
  static const Color orFonce = Color(0xFF8A6A12);
  static const Color fondPapier = Color(0xFFF5F6FA);
  static const Color rougeErreur = Color(0xFFB3261E);

  /// Vert foncé lisible sur fond clair (remplace AppTheme.vertFonce).
  static const Color vertFonce = Color(0xFF0C5B40);

  /// Bleu foncé lisible sur fond clair (remplace AppTheme.bleuFonce).
  static const Color bleuFonce = Color(0xFF1B4F72);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: bleuNuit,
          primary: bleuNuit,
          secondary: or,
          tertiary: orFonce,
          surface: const Color(0xFFFFFFFF),
          error: rougeErreur,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: fondPapier,
        appBarTheme: const AppBarTheme(
          backgroundColor: bleuNuit,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: or,
          foregroundColor: bleuNuit,
        ),
        // Taille minimale 14 px, corps de texte 16 px.
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16),
          bodySmall: TextStyle(fontSize: 14),
        ),
        // Boutons 48 px de haut, taille minimale pour un doigt.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          contentPadding:
              EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
      );
}
