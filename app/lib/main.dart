import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/fidele_shell.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/messages_admin_screen.dart';
import 'screens/plateforme_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/api_service.dart';
import 'services/notifications_push_service.dart';
import 'services/preferences_locales.dart';
import 'state/app_state.dart';

/// Navigateur global : les notifications push ouvrent la messagerie
/// depuis le service, hors de tout `BuildContext` d'écran.
final _cleNavigateur = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Notifications push FCM : le gestionnaire d'arrière-plan se
  // branche avant `runApp()`. Sans configuration Firebase (projet
  // `e-system-church` non fourni), il ne fait rien et le démarrage
  // continue normalement.
  await NotificationsPushService.initialiserArrierePlan();
  // Polices : embarquées dans le build (pubspec.yaml), aucun
  // téléchargement à l'exécution, le thème ne déclare que les noms.
  runApp(const EsystemApp());
}

/// Écran de messagerie à ouvrir depuis une notification push, selon le
/// rôle : la coquille fidèle sur l'onglet Messages, ou l'écran Messages
/// de l'administration. Le fil fidèle n'est pas un écran poussable seul
/// (colonne intégrée à la coquille), d'où la coquille avec l'onglet 3.
/// La T-Msg-1 (liste des conversations et écran de conversation, non
/// fusionnée) n'est pas dans cette base : quand elle atterrira, cet
/// endroit poussera l'écran de conversation avec
/// `message.conversationId` au lieu de l'écran des messages.
Widget ecranMessagesPourRole(String? role) => role == 'membre'
    ? const FideleShell(ongletInitial: 3)
    : const MessagesAdminScreen();

/// Racine de l'application : charge l'état (session + réglages), puis
/// affiche l'écran de connexion ou l'accueil selon la session.
class EsystemApp extends StatelessWidget {
  const EsystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..init()),
        // T12 (US15, US16) : langue des nouveaux écrans et mode économique.
        ChangeNotifierProvider(
            create: (_) => PreferencesLocales()..init()),
      ],
      child: Consumer2<AppState, PreferencesLocales>(
        builder: (context, state, prefs, _) {
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
            // P1) : le fidèle a sa propre navigation, sans passer par
            // l'espace admin. Les périmètres sont étanches : l'espace
            // fidèle ne s'ouvre pas depuis l'admin.
            home = state.isPlateforme
                ? const PlateformeScreen()
                : state.isMembre
                    ? const FideleShell()
                    : const HomeScreen();
          }
          return PontNotificationsPush(
            child: MaterialApp(
              title: AppConfig.appName,
              debugShowCheckedModeBanner: false,
              navigatorKey: _cleNavigateur,
              theme: AppTheme.themePourFacteur(prefs.facteurTailleTexte),
              // Taille du texte : le facteur choisi multiplie toutes les
              // tailles de texte, y compris celles écrites en dur dans
              // les écrans. Il multiplie l'échelle du système (réglage
              // d'accessibilité du téléphone), il ne la remplace pas.
              // L'échelle du système est lue sans son API dépréciée :
              // scale(16) / 16 donne son facteur effectif.
              builder: (context, child) {
                final echelleSysteme =
                    MediaQuery.textScalerOf(context).scale(16) / 16;
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(
                        echelleSysteme * prefs.facteurTailleTexte),
                  ),
                  child: child!,
                );
              },
              // T12 (US15) : la langue choisie s'applique aux nouveaux
              // écrans ; le reste de l'application reste en français.
              locale: Locale(prefs.langue),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('fr'), Locale('en')],
              home: home,
            ),
          );
        },
      ),
    );
  }
}

/// Branchement des notifications push FCM (tranche push FCM) : quand une
/// session de messagerie est ouverte, le service est initialisé (demande
/// d'autorisation, jeton FCM, écoutes) ; à la déconnexion, le jeton est
/// retiré avant la révocation de session (crochet
/// [AppState.onAvantDeconnexion]).
///
/// En avant-plan, le message reçu affiche une bannière avec un bouton
/// Ouvrir ; au toucher (arrière-plan ou application fermée), la
/// messagerie s'ouvre. Sans configuration Firebase, le service est
/// désactivé et ce pont ne fait rien. Les comptes Plateforme ne sont
/// pas branchés : ils n'ont pas accès à la messagerie (403, T-Msg-0).
///
/// [creerService] et [cleNavigateur] ne servent qu'aux tests.
class PontNotificationsPush extends StatefulWidget {
  const PontNotificationsPush({
    super.key,
    required this.child,
    this.creerService = NotificationsPushService.initialiser,
    this.cleNavigateur,
  });

  final Widget child;
  final Future<NotificationsPushService> Function(ApiService api)
      creerService;
  final GlobalKey<NavigatorState>? cleNavigateur;

  @override
  State<PontNotificationsPush> createState() => _PontNotificationsPushState();
}

class _PontNotificationsPushState extends State<PontNotificationsPush> {
  late final AppState _etat;
  NotificationsPushService? _service;
  StreamSubscription? _abonnementAvantPlan;
  StreamSubscription? _abonnementAOuvrir;
  String? _derniereConversationOuverte;
  DateTime? _derniereOuverture;

  GlobalKey<NavigatorState> get _cle =>
      widget.cleNavigateur ?? _cleNavigateur;

  @override
  void initState() {
    super.initState();
    _etat = context.read<AppState>();
    _etat.onAvantDeconnexion =
        () => _service?.desactiver() ?? Future<void>.value();
    _etat.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _etat.removeListener(_sync);
    _abonnementAvantPlan?.cancel();
    _abonnementAOuvrir?.cancel();
    _service?.dispose();
    super.dispose();
  }

  void _sync() {
    if (!_etat.initialized ||
        !_etat.isLoggedIn ||
        _etat.isPlateforme) {
      if (_service != null) {
        final service = _service;
        _service = null;
        _abonnementAvantPlan?.cancel();
        _abonnementAOuvrir?.cancel();
        _abonnementAvantPlan = null;
        _abonnementAOuvrir = null;
        unawaited(service?.desactiver());
      }
      return;
    }
    if (_service != null) return;
    unawaited(_initialiser());
  }

  Future<void> _initialiser() async {
    final service = await widget.creerService(_etat.api);
    if (!mounted || !_etat.isLoggedIn || _etat.isPlateforme) {
      await service.dispose();
      return;
    }
    _service = service;
    _abonnementAvantPlan =
        service.enAvantPlan.listen(_afficherBanniere);
    _abonnementAOuvrir = service.aOuvrir.listen(_ouvrirMessage);
    final initial = service.prendreMessageInitial();
    if (initial != null) _ouvrirMessage(initial);
  }

  void _afficherBanniere(PushMessageRecue message) {
    final context = _cle.currentContext;
    if (context == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.titre ?? 'Nouveau message',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (message.corps != null && message.corps!.isNotEmpty)
              Text(message.corps!),
          ],
        ),
        action: SnackBarAction(
          label: 'Ouvrir',
          onPressed: () => _ouvrirMessage(message),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _ouvrirMessage(PushMessageRecue message) {
    final navigateur = _cle.currentState;
    if (navigateur == null || !mounted) return;
    final maintenant = DateTime.now();
    final id = message.conversationId;
    if (id != null &&
        id == _derniereConversationOuverte &&
        _derniereOuverture != null &&
        maintenant.difference(_derniereOuverture!).inSeconds < 5) {
      return;
    }
    _derniereConversationOuverte = id;
    _derniereOuverture = maintenant;
    navigateur.push(
      MaterialPageRoute(
        builder: (_) => ecranMessagesPourRole(_etat.role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
