import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/mock_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parcours complet des finances de la mère en détail, en mode démo
/// (données « Grâce Divine » en mémoire) : total consolidé et détail par
/// branche, par mois, trimestre et année, par type, avec chaque transaction
/// confirmée. Aucun serveur, aucune base réelle.
void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
  });

  Future<void> loginPlateau() => api.login(
        email: 'admin@gracedivine.ci',
        password: 'demo1234',
      );

  test('mois de novembre 2026 : détail par branche, soldes et transactions',
      () async {
    await loginPlateau();
    final rapport = await api.getRapportDetail(
      periode: 'mois',
      mois: '2026-11',
    );
    expect(rapport.periode.label, 'Novembre 2026');
    expect(rapport.periode.debut, '2026-11-01');
    expect(rapport.periode.fin, '2026-12-01');
    // Mon église + ses 4 sous-églises directes. Bouaké Centre, petite-fille,
    // n'est pas listée ici : elle est vue par sa propre mère, Bouaké.
    expect(
      rapport.branches.map((b) => b.egliseNom),
      [
        'Grâce Divine — Plateau',
        'Grâce Divine — Bouaké',
        'Grâce Divine — San Pedro',
        'Grâce Divine — Yamoussoukro',
        'Grâce Divine — Yopougon',
      ],
    );

    final plateau = rapport.branches.first;
    expect(plateau.totaux['dime']?.totalFcfa, 10000);
    expect(plateau.totaux['offrande']?.totalFcfa, 5000);
    expect(plateau.totaux['don']?.totalFcfa, 25000);
    expect(plateau.totaux['depense']?.totalFcfa, 20000);
    expect(plateau.entreesFcfa, 40000);
    expect(plateau.soldeFcfa, 20000);
    // La dîme en attente de Koffi Yao ne compte pas.
    expect(plateau.transactions.length, 4);
    expect(
      plateau.transactions.map((t) => t.id),
      containsAll(['demo-c-p1', 'demo-c-p2', 'demo-c-p3', 'demo-c-p5']),
    );

    final yopougon =
        rapport.branches.firstWhere((b) => b.egliseNom.contains('Yopougon'));
    expect(yopougon.entreesFcfa, 11000);
    expect(yopougon.soldeFcfa, 11000);
    expect(yopougon.transactions.length, 2);

    final yakro = rapport.branches
        .firstWhere((b) => b.egliseNom.contains('Yamoussoukro'));
    expect(yakro.entreesFcfa, 0);
    expect(yakro.transactions, isEmpty);

    // Réseau : 40 000 + 11 000 + 12 000 + 0 + 50 000 = 113 000 entrées,
    // 20 000 de dépenses, solde 93 000, 12 membres actifs.
    expect(rapport.entreesFcfa, 113000);
    expect(rapport.depensesFcfa, 20000);
    expect(rapport.soldeFcfa, 93000);
    expect(rapport.membresActifs, 12);
  });

  test('trimestre et année : mêmes chiffres, autres bornes', () async {
    await loginPlateau();
    final trimestre = await api.getRapportDetail(
      periode: 'trimestre',
      mois: '2026-11',
    );
    expect(trimestre.periode.label, '4e trimestre 2026');
    expect(trimestre.periode.debut, '2026-10-01');
    expect(trimestre.periode.fin, '2027-01-01');
    expect(trimestre.entreesFcfa, 113000);
    expect(trimestre.soldeFcfa, 93000);

    final annee = await api.getRapportDetail(
      periode: 'annee',
      mois: '2026-11',
    );
    expect(annee.periode.label, 'Année 2026');
    expect(annee.periode.debut, '2026-01-01');
    expect(annee.periode.fin, '2027-01-01');
    expect(annee.entreesFcfa, 113000);
  });

  test('octobre 2026 : aucune transaction, solde nul', () async {
    await loginPlateau();
    final rapport = await api.getRapportDetail(
      periode: 'mois',
      mois: '2026-10',
    );
    expect(rapport.entreesFcfa, 0);
    expect(rapport.soldeFcfa, 0);
    expect(
      rapport.branches.expand((b) => b.transactions),
      isEmpty,
    );
  });

  test('une sous-église ne voit que son propre périmètre', () async {
    await api.login(email: 'admin@yopougon.ci', password: 'demo1234');
    final rapport = await api.getRapportDetail(
      periode: 'mois',
      mois: '2026-11',
    );
    expect(
      rapport.branches.map((b) => b.egliseNom),
      ['Grâce Divine — Yopougon'],
    );
    expect(rapport.entreesFcfa, 11000);
  });

  test('le trésorier ne peut pas voir le détail consolidé', () async {
    await api.login(
        email: 'tresorier@gracedivine.ci', password: 'demo1234');
    await expectLater(
      api.getRapportDetail(periode: 'mois', mois: '2026-11'),
      throwsA(isA<ApiException>()),
    );
  });
}
