import 'dart:convert';
import 'dart:io';

import 'package:esystem_church/services/session_store.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Faille basse n° 11 (audit 14/11, re-vérifiée le 22/11) — démarrage hors
/// ligne : `init()` effaçait les jetons stockés sur n'importe quel échec,
/// y compris une erreur de transport. Le correctif ne les efface que sur
/// révocation prouvée (401) ; un échec de transport les conserve et met
/// l'état hors ligne ([AppState.horsLigne]), avec réessai
/// ([AppState.reessayerConnexion]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('init() hors ligne — faille basse n° 11', () {
    test('API injoignable : les jetons survivent, état hors ligne', () async {
      final store = FauxSessionStore()
        ..token = 'jwt-stocke'
        ..refreshToken = 'refresh-stocke';
      final state = AppState(
        store: store,
        client: MockClient((_) async => throw const SocketException(
              'Impossible de joindre le serveur.',
            )),
      );

      await state.init();

      expect(state.initialized, isTrue);
      expect(state.isLoggedIn, isFalse);
      expect(state.horsLigne, isTrue);
      // La session longue durée n'est pas détruite : les jetons stockés
      // sont intacts et serviront au prochain démarrage (ou au réessai).
      expect(store.token, 'jwt-stocke');
      expect(store.refreshToken, 'refresh-stocke');
    });

    test('401 confirmé : les jetons sont effacés (déconnexion propre)',
        () async {
      final store = FauxSessionStore()
        ..token = 'jwt-stocke'
        ..refreshToken = 'refresh-stocke';
      final state = AppState(
        store: store,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Non autorisé'}),
            401,
          ),
        ),
      );

      await state.init();

      expect(state.initialized, isTrue);
      expect(state.isLoggedIn, isFalse);
      expect(state.horsLigne, isFalse);
      expect(store.token, isNull);
      expect(store.refreshToken, isNull);
    });

    test('erreur 500 : pas de preuve de révocation, jetons conservés',
        () async {
      final store = FauxSessionStore()
        ..token = 'jwt-stocke'
        ..refreshToken = 'refresh-stocke';
      final state = AppState(
        store: store,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Erreur interne'}),
            500,
          ),
        ),
      );

      await state.init();

      expect(state.isLoggedIn, isFalse);
      expect(state.horsLigne, isTrue);
      expect(store.token, 'jwt-stocke');
      expect(store.refreshToken, 'refresh-stocke');
    });

    test('JWT expiré puis rotation réussie : session restaurée', () async {
      final store = FauxSessionStore()
        ..token = 'jwt-expire'
        ..refreshToken = 'refresh-stocke';
      var appelsMoi = 0;
      final state = AppState(
        store: store,
        client: MockClient((request) async {
          if (request.url.path == '/auth/refresh') {
            return http.Response(
              jsonEncode({
                'token': 'jwt-neuf',
                'refresh_token': 'refresh-neuf',
                'user': _utilisateurJson,
                'church': _egliseJson,
                'eglises': [],
              }),
              200,
            );
          }
          if (request.url.path == '/moi/eglise') {
            // Premier appel : JWT expiré (401) ; l'appel est rejoué après
            // rotation et aboutit.
            appelsMoi++;
            if (appelsMoi == 1) {
              return http.Response(
                jsonEncode({'message': 'Non autorisé'}),
                401,
              );
            }
            return http.Response(jsonEncode(_moiJson()), 200);
          }
          return http.Response(
            jsonEncode({'message': 'Non trouvé'}),
            404,
          );
        }),
      );

      await state.init();
      // La rotation persiste les jetons via `onTokensRefreshed`, sans
      // attendre : on laisse un tour de boucle d'événements passer.
      await Future<void>.delayed(Duration.zero);

      expect(state.isLoggedIn, isTrue);
      expect(state.horsLigne, isFalse);
      expect(store.token, 'jwt-neuf');
      expect(store.refreshToken, 'refresh-neuf');
    });

    test('réessai après panne : la session est restaurée sans reconnexion',
        () async {
      final store = FauxSessionStore()
        ..token = 'jwt-stocke'
        ..refreshToken = 'refresh-stocke';
      var enLigne = false;
      final state = AppState(
        store: store,
        client: MockClient((request) async {
          if (!enLigne) {
            throw const SocketException('Impossible de joindre le serveur.');
          }
          if (request.url.path == '/moi/eglise') {
            return http.Response(jsonEncode(_moiJson()), 200);
          }
          return http.Response(
            jsonEncode({'message': 'Non trouvé'}),
            404,
          );
        }),
      );

      await state.init();
      expect(state.horsLigne, isTrue);
      expect(state.isLoggedIn, isFalse);
      expect(store.token, 'jwt-stocke');

      enLigne = true;
      final restauree = await state.reessayerConnexion();

      expect(restauree, isTrue);
      expect(state.isLoggedIn, isTrue);
      expect(state.horsLigne, isFalse);
      expect(state.user?.fullName, 'Katia Camara');
      expect(state.church?.code, 'ESC-4240');
    });

    test('réessai sans panne préalable : sans effet', () async {
      final store = FauxSessionStore()
        ..token = 'jwt-stocke'
        ..refreshToken = 'refresh-stocke';
      final state = AppState(
        store: store,
        client: MockClient((request) async {
          if (request.url.path == '/moi/eglise') {
            return http.Response(jsonEncode(_moiJson()), 200);
          }
          return http.Response(
            jsonEncode({'message': 'Non trouvé'}),
            404,
          );
        }),
      );

      await state.init();
      expect(state.isLoggedIn, isTrue);
      expect(await state.reessayerConnexion(), isTrue);
    });
  });
}

/// Stockage simulé en mémoire : surcharge chaque accès au stockage
/// sécurisé réel, inutilisable dans un test unitaire.
class FauxSessionStore extends SessionStore {
  String? token;
  String? refreshToken;
  String urlApi = 'https://api.test';

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async {
    token = value;
  }

  @override
  Future<void> clearToken() async {
    token = null;
  }

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveRefreshToken(String value) async {
    refreshToken = value;
  }

  @override
  Future<void> clearRefreshToken() async {
    refreshToken = null;
  }

  @override
  Future<String> readApiUrl() async => urlApi;

  @override
  Future<void> saveApiUrl(String url) async {
    urlApi = url;
  }
}

const Map<String, dynamic> _utilisateurJson = {
  'id': 'u1',
  'full_name': 'Katia Camara',
  'email': 'test@example.com',
};

const Map<String, dynamic> _egliseJson = {
  'id': 'e1',
  'code': 'ESC-4240',
  'name': 'TEST',
};

Map<String, dynamic> _moiJson() => {
      'user': _utilisateurJson,
      'church': _egliseJson,
      'role': 'admin_eglise',
      'eglises': [],
    };
