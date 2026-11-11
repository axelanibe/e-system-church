import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'screens/fidele_home_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
            theme: ThemeData(
              useMaterial3: true,
              // Palette e-System Church (10 novembre 2026, décision de Bouf) :
              // vert, or, rouge — couleurs de la maquette. Remplace le bleu
              // nuit / or de la tranche Plateforme.
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF0C5B40),
                primary: const Color(0xFF0C5B40),
                secondary: const Color(0xFFC9971C),
                tertiary: const Color(0xFFB3261E),
                surface: const Color(0xFFFFFFFF),
                error: const Color(0xFFB3261E),
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: const Color(0xFFF2F4F1),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF0C5B40),
                foregroundColor: Colors.white,
              ),
              floatingActionButtonTheme:
                  const FloatingActionButtonThemeData(
                backgroundColor: Color(0xFFC9971C),
                foregroundColor: Color(0xFF083D2B),
              ),
            ),
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
