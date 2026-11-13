import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/fidele_shell.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/plateforme_screen.dart';
import 'screens/reset_password_screen.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Polices : embarquées dans le build (pubspec.yaml), aucun
  // téléchargement à l'exécution, le thème ne déclare que les noms.
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
            // Connexion Plateforme (admin ou aide) : l'écran Plateforme
            // directement, jamais une église. Coquille fidèle (tranche
            // P1) : le fidèle a sa propre navigation. L'admin peut aussi
            // la regarder en aperçu (« Voir l'espace fidèle »), sans
            // changer de session.
            home = state.isPlateforme
                ? const PlateformeScreen()
                : (state.isMembre || state.apercuFidele)
                    ? const FideleShell()
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
