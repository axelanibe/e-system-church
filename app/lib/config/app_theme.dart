import 'package:flutter/material.dart';

/// Thème unique de e-System Church, partagé par l'application réelle
/// (`lib/main.dart`) et la version démo (`lib/main_demo.dart`).
///
/// Palette officielle, tranchée par Axel le 10 novembre 2026 :
/// bleu nuit #0B1F3A, or #D4A72C, or foncé #8A6A12, fond papier #F5F6FA.
/// Le rouge ne sert qu'aux erreurs et aux alertes.
class AppTheme {
  static const Color bleuNuit = Color(0xFF0B1F3A);
  static const Color or = Color(0xFFD4A72C);
  static const Color orFonce = Color(0xFF8A6A12);
  static const Color fondPapier = Color(0xFFF5F6FA);
  static const Color rougeErreur = Color(0xFFB3261E);

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
      );
}
