import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/mock_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parcours de l'écran Plateforme, en mode démo (données « Grâce Divine »
/// en mémoire) : chiffres globaux seulement, sans détail nominatif, sans
/// gestion des membres. Aucun serveur, aucune base réelle.
void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
  });

  test('super_admin : chiffres globaux du réseau, sans détail nominatif',
      () async {
    await api.login(email: 'admin@esystem.ci', password: 'demo1234');
    final chiffres = await api.getPlateforme();
    // Une église mère, 5 branches (Yopougon, Bouaké, Bouaké Centre,
    // Yamoussoukro, San Pedro), 6 églises au total. La pseudo-église de
    // session de la plateforme n'est pas comptée.
    expect(chiffres.eglisesMeres, 1);
    expect(chiffres.branches, 5);
    expect(chiffres.eglisesTotal, 6);
    // 14 membres actifs (12 du réseau direct + 2 de Bouaké Centre).
    expect(chiffres.membresActifs, 14);
    // 7 contributions confirmées pour 113 000 FCFA, 20 000 de dépenses.
    expect(chiffres.nombreContributions, 7);
    expect(chiffres.totalContributionsFcfa, 113000);
    expect(chiffres.depensesFcfa, 20000);
  });

  test('admin d\'église : pas d\'accès aux chiffres de la plateforme',
      () async {
    await api.login(email: 'admin@gracedivine.ci', password: 'demo1234');
    await expectLater(
      api.getPlateforme(),
      throwsA(isA<ApiException>()),
    );
  });

  test('trésorier : pas d\'accès aux chiffres de la plateforme', () async {
    await api.login(
        email: 'tresorier@gracedivine.ci', password: 'demo1234');
    await expectLater(
      api.getPlateforme(),
      throwsA(isA<ApiException>()),
    );
  });

  test('membre simple : pas d\'accès aux chiffres de la plateforme',
      () async {
    await api.login(email: 'membre@gracedivine.ci', password: 'demo1234');
    await expectLater(
      api.getPlateforme(),
      throwsA(isA<ApiException>()),
    );
  });
}
