import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
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
          return MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              // Palette d'Axel (10 novembre 2026, tranche Plateforme) :
              // bleu nuit et or, fond papier. Remplace le vert de
              // Phoenix (0xFF0E7C5B), sans changer la structure des écrans.
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF0B1F3A),
                primary: const Color(0xFF0B1F3A),
                secondary: const Color(0xFFD4A72C),
                tertiary: const Color(0xFF8A6A12),
                surface: const Color(0xFFF5F6FA),
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: const Color(0xFFF5F6FA),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF0B1F3A),
                foregroundColor: Colors.white,
              ),
              floatingActionButtonTheme:
                  const FloatingActionButtonThemeData(
                backgroundColor: Color(0xFFD4A72C),
                foregroundColor: Color(0xFF0B1F3A),
              ),
            ),
            locale: const Locale('fr'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('fr')],
            home: state.isLoggedIn
                ? const HomeScreen()
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
