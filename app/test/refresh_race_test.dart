import 'dart:convert';

import 'package:esystem_church/services/http_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Refresh-race (audit sécurité, moyenne) : deux appels concurrents sur
/// JWT expiré ne doivent émettre qu'un seul POST `/auth/refresh` (vol
/// unique partagé) ; la rotation réussie ne doit pas être annulée par un
/// 401 portant sur l'ancien jeton, et une expiration confirmée doit
/// prévenir l'appelant au lieu de laisser une session zombie.
/// Données EXEMPLE uniquement, jamais de données réelles.

const _meJson = {
  'user': {'id': 'u-1', 'full_name': 'Test Exemple', 'email': 't@example.ci'},
  'church': {'id': 'e-1', 'code': 'ESC-TEST', 'name': 'Église Test'},
  'role': 'membre',
  'eglises': [],
};

const _refreshJson = {
  'token': 'jwt-nouveau',
  'refresh_token': 'rt-nouveau',
  'user': {'id': 'u-1', 'full_name': 'Test Exemple', 'email': 't@example.ci'},
  'church': {'id': 'e-1', 'code': 'ESC-TEST', 'name': 'Église Test'},
  'eglises': [],
};

http.Response _json(Object corps, int statut) => http.Response(
      jsonEncode(corps),
      statut,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('deux me() concurrents sur JWT expiré : un seul refresh, deux succès',
      () async {
    var nbRefresh = 0;
    var nbRefresh401 = 0;
    final jetonsRafraichis = <List<String?>>[];
    var nbExpirations = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        nbRefresh++;
        // Sérialisation côté serveur : le premier refresh prend du temps,
        // un second avec le même ancien jeton serait rejeté en 401 (rejeu).
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (nbRefresh == 1) return _json(_refreshJson, 200);
        nbRefresh401++;
        return _json(
            {'message': 'Session expirée.', 'error': 'session_expiree'}, 401);
      }
      if (request.url.path == '/moi/eglise') {
        if (request.headers['authorization'] == 'Bearer jwt-nouveau') {
          return _json(_meJson, 200);
        }
        return _json(
            {'message': 'Non autorisé.', 'error': 'unauthorized'}, 401);
      }
      return _json({}, 404);
    });
    final api = HttpApiService(
      baseUrl: 'http://test',
      token: 'jwt-ancien',
      refreshToken: 'rt-ancien',
      client: client,
    );
    api.onTokensRefreshed = (token, refreshToken) {
      jetonsRafraichis.add([token, refreshToken]);
    };
    api.onSessionExpiree = () async {
      nbExpirations++;
    };

    final resultats = await Future.wait([api.me(), api.me()]);

    expect(resultats, hasLength(2));
    expect(resultats[0].user.id, 'u-1');
    expect(resultats[1].user.id, 'u-1');
    // Vol unique : un seul POST /auth/refresh, jamais le second en 401.
    expect(nbRefresh, 1);
    expect(nbRefresh401, 0);
    // Rotation livrée une seule fois, avec les jetons frais.
    expect(jetonsRafraichis, [
      ['jwt-nouveau', 'rt-nouveau']
    ]);
    // Pas d'expiration signalée : la session est saine après rotation.
    expect(nbExpirations, 0);
    // Le troisième appel réutilise les jetons frais, sans nouveau refresh.
    await api.me();
    expect(nbRefresh, 1);
  });

  test('refresh en 401 pour le jeton courant : jetons annulés, expiration signalée',
      () async {
    var nbExpirations = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return _json(
            {'message': 'Session expirée.', 'error': 'session_expiree'}, 401);
      }
      if (request.url.path == '/moi/eglise') {
        return _json(
            {'message': 'Non autorisé.', 'error': 'unauthorized'}, 401);
      }
      return _json({}, 404);
    });
    final api = HttpApiService(
      baseUrl: 'http://test',
      token: 'jwt-ancien',
      refreshToken: 'rt-revoque',
      client: client,
    );
    api.onSessionExpiree = () async {
      nbExpirations++;
    };

    await expectLater(api.me(), throwsA(isA<ApiException>()));
    expect(nbExpirations, 1);
    expect(api.token, isNull);
    // Un nouvel appel n'essaie plus de rafraîchir (plus de jeton).
    await expectLater(api.me(), throwsA(isA<ApiException>()));
    expect(nbExpirations, 1);
  });
}
