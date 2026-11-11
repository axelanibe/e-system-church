// Point d'entrée de la version DÉMO — `flutter run -t lib/main_demo.dart`
// ou `flutter build apk --flavor demo -t lib/main_demo.dart`.
//
// Même application que `lib/main.dart`, mais avec [DemoAppState] (données
// fictives en mémoire, aucune connexion serveur, rien de persisté) et le
// bandeau « DÉMO — données fictives » en haut de chaque écran.
// Le fichier `lib/main.dart` n'est pas modifié.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'demo/demo_app_state.dart';
import 'demo/demo_banner.dart';
import 'demo/demo_login_screen.dart';
import 'screens/fidele_home_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
}

/// Racine de la démo : même thème et même navigation que l'application
/// réelle, mais l'état est [DemoAppState] (mock en mémoire).
class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => DemoAppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          if (!state.initialized) {
            return const MaterialApp(
              home: Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          // Même logique que l'application réelle : connexion, accueil
          // fidèle (rôle `membre`) ou administration. Le `?token=` web
          // ouvre l'écran de mot de passe (simulé en démo).
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
              home = const DemoLoginScreen();
            }
          } else {
            // Bandeau DÉMO au-dessus de l'accueil (l'écran lui-même
            // n'est pas modifié : il est simplement enveloppé ici).
            final ecran = state.isMembre
                ? const FideleHomeScreen()
                : const HomeScreen();
            home = Scaffold(
              body: Column(
                children: [
                  const DemoBanner(),
                  Expanded(child: ecran),
                ],
              ),
            );
          }
          return MaterialApp(
            title: '${AppConfig.appName} — Démo',
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
