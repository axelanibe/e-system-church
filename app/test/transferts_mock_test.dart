import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/mock_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parcours complet du transfert de membre en mode démo (données
/// « Grâce Divine » en mémoire) : demande par matricule, double validation
/// (départ puis arrivée), déplacement avec nouveau matricule, historique.
/// Aucun serveur, aucune base réelle.
void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
  });

  Future<void> loginPlateau() => api.login(
        email: 'admin@gracedivine.ci',
        password: 'demo1234',
      );

  Future<void> loginYopougon() => api.login(
        email: 'admin@yopougon.ci',
        password: 'demo1234',
      );

  test('la demande de démo est à traiter par le Plateau', () async {
    await loginPlateau();
    final result = await api.getTransferts();
    expect(result.aTraiter.map((t) => t.id), contains('demo-tr-1'));
    expect(result.aTraiter.first.membreNom, 'Aminata Traoré');
  });

  test('double validation déplace le membre avec un nouveau matricule',
      () async {
    await loginPlateau();
    // Demande : Koffi Yao (M-0002, Plateau) vers Yopougon.
    final demande = await api.requestTransfert(
      matricule: 'M-0002',
      destinationCode: 'ESC-YOP001',
      motif: 'Déménagement à Yopougon',
    );
    expect(demande.status, 'en_attente');
    expect(demande.decisionDepart, 'en_attente');

    // Une deuxième demande pour le même membre est refusée.
    await expectLater(
      api.requestTransfert(
          matricule: 'M-0002', destinationCode: 'ESC-YOP001'),
      throwsA(isA<ApiException>()),
    );

    // L'arrivée ne peut pas décider avant le départ.
    await loginYopougon();
    await expectLater(
      api.decideTransfert(demande.id, accept: true),
      throwsA(isA<ApiException>()),
    );

    // Le départ accepte, le transfert reste en attente.
    await loginPlateau();
    await api.decideTransfert(demande.id, accept: true);
    var result = await api.getTransferts();
    final enAttente = result.emises.firstWhere((t) => t.id == demande.id);
    expect(enAttente.status, 'en_attente');
    expect(enAttente.decisionDepart, 'accepte');

    // Le départ ne peut pas décider deux fois.
    await expectLater(
      api.decideTransfert(demande.id, accept: true),
      throwsA(isA<ApiException>()),
    );

    // L'arrivée accepte : le membre déménage (Yopougon a 4 membres, M-0005).
    await loginYopougon();
    result = await api.getTransferts();
    expect(result.aTraiter.map((t) => t.id), contains(demande.id));
    await api.decideTransfert(demande.id, accept: true);
    result = await api.getTransferts();
    final fait =
        result.historique.firstWhere((t) => t.id == demande.id);
    expect(fait.status, 'accepte');
    expect(fait.nouveauMatricule, 'M-0005');

    final membresYopougon = await api.getMembers();
    expect(
      membresYopougon.membres
          .where((m) => m.fullName == 'Koffi Yao')
          .map((m) => m.matricule),
      ['M-0005'],
    );

    // L'ancienne branche ne voit plus le membre comme actif.
    await loginPlateau();
    final membresPlateau = await api.getMembers();
    expect(
      membresPlateau.membres.map((m) => m.fullName),
      isNot(contains('Koffi Yao')),
    );
  });

  test('un refus du départ clôt la demande sans déplacement', () async {
    await loginPlateau();
    final demande = await api.requestTransfert(
      matricule: 'M-0004',
      destinationCode: 'ESC-YOP001',
    );
    await api.decideTransfert(demande.id, accept: false);
    final result = await api.getTransferts();
    expect(
      result.historique
          .firstWhere((t) => t.id == demande.id)
          .status,
      'refuse',
    );
    final membres = await api.getMembers();
    expect(membres.membres.map((m) => m.matricule), contains('M-0004'));
  });

  test('le trésorier ne peut pas demander de transfert', () async {
    await api.login(
        email: 'tresorier@gracedivine.ci', password: 'demo1234');
    await expectLater(
      api.requestTransfert(
          matricule: 'M-0002', destinationCode: 'ESC-YOP001'),
      throwsA(isA<ApiException>()),
    );
  });
}
