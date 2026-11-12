import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/fidele_home_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Polices : téléchargées à l'exécution et mises en cache par
  // google_fonts. Le thème ne déclare que les noms de familles, le
  // chargement démarre ici, avant le premier écran.
  GoogleFonts.inter();
  GoogleFonts.plusJakartaSans();
  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold);
  GoogleFonts.jetBrainsMono();
  runApp(const EsystemApp());
}

/// Racine de l'application : charge l'état (session + réglages), puis
/// affiche l'écran de connexion ou l'accueil selon la session.
class EsystemApp extends StatelessWidget {
  const EsystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          if (!state.initialized) {
            return const MaterialApp(
              home: Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          // Écran d'accueil selon la session : fidèle (rôle `membre`) ou
          // administration. Sur le web, un lien `?token=` (réinitialisation
          // ou invitation) ouvre directement l'écran de mot de passe.
          Widget home;
          if (!state.isLoggedIn) {
            final token =
                kIsWeb ? Uri.base.queryParameters['token'] : null;
            if (token != null && token.isNotEmpty) {
              final mode = Uri.base.path.contains('initialiser')
                  ? ResetMode.initialisation
                  : ResetMode.reinitialisation;
              home = ResetPasswordScreen(initialToken: token, mode: mode);
            } else {
              home = const LoginScreen();
            }
          } else {
            home = state.isMembre
                ? const FideleHomeScreen()
                : const HomeScreen();
          }
          return MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.theme,
            locale: const Locale('fr'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('fr')],
            home: home,
          );
        },
      ),
    );
  }
}
