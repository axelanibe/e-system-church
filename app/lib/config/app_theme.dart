import 'package:flutter/material.dart';

/// Thème unique de e-System Church, partagé par toute l'application
/// (`lib/main.dart`). Le mode démo a été supprimé (T12) : il n'y a plus
/// de version démo.
///
/// Palette du logo, tranchée par Axel le 14 novembre 2026
/// (projection couleurs du logo validée pour le web et l'APK) :
/// violet profond #2A0059, violet secondaire #3D0073, violet
/// très foncé #1A003F, violet vif #5A00A8, or du logo #E8B820,
/// or clair #F2C230, or foncé #8A6A12, fond papier teinté violet
/// #F6F2FB. Le rouge ne sert qu'aux erreurs et aux alertes. Elle
/// remplace la palette bleu nuit et or de l'artefact (#0B1F3A,
/// #D4A72C), elle-même décidée le 12 novembre 2026. Exception
/// gardée de la maquette de refonte : l'or d'attention #B8860B
/// sert aux états actifs et aux éléments d'attention, car l'or
/// ne capte pas l'attention sur fond clair. Il ne remplace pas
/// l'or foncé, qui garde les textes courants sur papier.
/// Typographies : Inter pour le corps, Plus Jakarta Sans pour les
/// titres, JetBrains Mono pour les codes et matricules. Les polices
/// sont embarquées dans le build (pubspec.yaml, fichiers TTF
/// officiels Google Fonts), sans appel réseau : le site statique et
/// l'APK les servent depuis leurs propres assets. Les tests restent
/// ainsi verts hors ligne.
///
/// Contrastes vérifiés (WCAG, textes principaux au moins 4,5:1) :
/// blanc sur violet profond 16,9:1, violet profond sur papier
/// 15,3:1, or foncé sur papier 4,58:1, or sur violet profond
/// 9,1:1, violet profond sur or 9,1:1, violet profond sur or
/// clair 10,1:1, rouge #B3261E sur papier 6,05:1, vert foncé
/// #0C5B40 sur papier 7,52:1. Blanc sur or ne vaut que 1,86:1 :
/// jamais de texte blanc sur or, le texte sur or est violet
/// profond.
///
/// Accessibilité (11 novembre 2026) : taille minimale 14 px, titres
/// 24 gras, sous-titres 18, corps 16, boutons 48 px de haut, champs
/// 56 px de haut, pour un doigt et pour des yeux fatigués.
class AppTheme {
  /// Violet profond, primaire : AppBar, boutons, texte principal.
  static const Color violetProfond = Color(0xFF2A0059);

  /// Ancien nom de [violetProfond], gardé pour compatibilité : la
  /// tranche « logo église » (autre branche) utilise encore ce nom
  /// dans mon_eglise_screen.dart et sycebnl_screen.dart, qu'elle
  /// renommera à son rebase.
  static const Color bleuNuit = violetProfond;

  /// Violet secondaire, second arrêt des dégradés (carte membre,
  /// carte « Aujourd'hui », aperçu fidèle).
  static const Color violetSecondaire = Color(0xFF3D0073);

  /// Or du logo, accent : boutons d'action, badge « Église mère »,
  /// détails.
  static const Color or = Color(0xFFE8B820);

  /// Or foncé, accent secondaire, texte sur papier 4,68:1.
  static const Color orFonce = Color(0xFF8A6A12);

  /// Or d'attention, états actifs et éléments d'attention sur fond
  /// clair (maquette de refonte, 13 novembre 2026). Contraste
  /// 3,03:1 sur papier : icônes et bordures seulement, jamais le
  /// corps de texte ni les libellés de navigation (T13, D03 : les
  /// libellés actifs utilisent l'or foncé, 5,06:1 sur blanc).
  static const Color orAttention = Color(0xFFB8860B);

  /// Or clair, fonds doux (badge « Église mère », indicateurs).
  static const Color orClair = Color(0xFFF7ECC8);

  /// Fond papier teinté violet, fond des écrans.
  static const Color fondPapier = Color(0xFFF6F2FB);

  /// Bordures claires, champs et cartes.
  static const Color bordure = Color(0xFFDDD3EE);

  /// Texte secondaire atténué sur fond clair (tiroir clair, maquette
  /// d'Axel, 14 novembre 2026) : #5A4A72 mesuré sur le logo.
  static const Color texteSecondaire = Color(0xFF5A4A72);

  /// Rouge, erreurs et alertes seulement, sur papier 6,05:1.
  static const Color rougeErreur = Color(0xFFB3261E);

  /// Vert foncé lisible sur fond clair (remplace le vert vif).
  static const Color vertFonce = Color(0xFF0C5B40);

  /// Bleu foncé lisible sur fond clair (remplace le bleu vif).
  static const Color bleuFonce = Color(0xFF1B4F72);

  /// Style mono pour les codes et matricules.
  static const TextStyle styleCode =
      TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14, color: violetProfond);

  static ThemeData get theme {
    const titres = TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontWeight: FontWeight.bold,
      color: violetProfond,
    );
    const corps = TextStyle(fontFamily: 'Inter', color: violetProfond);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: violetProfond,
        primary: violetProfond,
        onPrimary: Colors.white,
        secondary: or,
        tertiary: orFonce,
        surface: Colors.white,
        onSurface: violetProfond,
        error: rougeErreur,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: fondPapier,
      appBarTheme: const AppBarTheme(
        backgroundColor: violetProfond,
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
        shadowColor: const Color(0x1A2A0059),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: bordure),
        ),
      ),
      // Puces de filtre : sélection violet profond, texte blanc, coche or,
      // pour que l'actif se voie au premier coup d'œil. Non
      // sélectionnée : blanche, bordure claire, texte violet profond.
      chipTheme: const ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: violetProfond,
        checkmarkColor: or,
        labelStyle: TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: violetProfond),
        secondaryLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.bold),
        side: BorderSide(color: bordure),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: or,
        unselectedLabelColor: Colors.white,
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: or, width: 3),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      // Barre du bas : l'onglet actif se voit au premier coup d'œil,
      // pastille or, icône violet profond, libellé or foncé gras.
      // Contrastes recalculés (T13, D03, WCAG 2.2 AA, fond blanc) :
      // actif or foncé #8A6A12 = 5,06:1 ; inactif violet profond à 75 % =
      // 7,37:1. L'or d'attention (3,25:1 à 11 px) et le violet profond à
      // 55 % (3,79:1) n'atteignent pas les 4,5:1 exigés pour du
      // texte de 11 px, qui n'est pas du « grand texte ».
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: or,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? violetProfond
                : violetProfond.withValues(alpha: 0.75),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
            color: selected
                ? orFonce
                : violetProfond.withValues(alpha: 0.75),
          );
        }),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: or,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: or,
        foregroundColor: violetProfond,
      ),
      // Titres 24 gras, sous-titres 18, corps 16, aide 14, jamais
      // moins de 14. Un nouveau membre doit tout lire sans effort.
      textTheme: TextTheme(
        headlineSmall: titres.copyWith(fontSize: 24),
        titleLarge: titres.copyWith(fontSize: 18),
        titleMedium: const TextStyle(
            fontFamily: 'PlusJakartaSans', fontSize: 18, color: violetProfond),
        bodyMedium: corps.copyWith(fontSize: 16),
        bodySmall: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: violetProfond),
        labelLarge: const TextStyle(
            fontFamily: 'Inter', fontSize: 14, color: violetProfond),
        labelSmall: const TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 12, color: violetProfond),
      ),
      // Boutons 48 px de haut, taille minimale pour un doigt.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: violetProfond,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: violetProfond,
          side: const BorderSide(color: violetProfond),
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
