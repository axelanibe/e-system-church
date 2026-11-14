import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/state/app_state.dart';
import 'package:esystem_church/widgets/church_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Logo d'église (tranche logo église) : l'en-tête de Mon église affiche
/// déjà le logo via ChurchAvatar (NetworkImage quand logoUrl est renseigné,
/// initiales sinon, repli sur erreur de chargement). Ces tests figent ce
/// comportement : avec logo, l'avatar porte l'image réseau ; sans logo,
/// il porte les initiales ; l'URL relative est résolue sur l'API.

Church _eglise({String? logoUrl}) => Church.fromJson({
      'id': 'eglise-1',
      'code': 'ESC-AAAAAA',
      'name': 'Ministère Évangélique Charismatique',
      'parent_church_id': null,
      'city': 'Abidjan',
      'status': 'active',
      'logo_url': logoUrl,
    });

Widget _arbre(Widget enfant) => ChangeNotifierProvider<AppState>.value(
      value: AppState(),
      child: MaterialApp(home: Scaffold(body: Center(child: enfant))),
    );

void main() {
  test('Church.fromJson lit logo_url', () {
    expect(_eglise(logoUrl: '/logos/abc.png').logoUrl, '/logos/abc.png');
    expect(_eglise().logoUrl, isNull);
  });

  testWidgets('ChurchAvatar sans logo : initiales affichées', (tester) async {
    await tester.pumpWidget(_arbre(ChurchAvatar(church: _eglise())));
    expect(find.text('MÉ'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isNull);
  });

  testWidgets('ChurchAvatar avec logo : NetworkImage avec la bonne URL',
      (tester) async {
    // Le chargement réseau échoue en test (pas de réseau) : on ignore
    // l'erreur d'image, l'assertion porte sur l'image demandée.
    final ancienneOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = ancienneOnError);
    await tester.pumpWidget(
        _arbre(ChurchAvatar(church: _eglise(logoUrl: '/logos/abc.png'))));
    await tester.pump();
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final image = avatar.backgroundImage;
    expect(image, isA<NetworkImage>());
    expect((image as NetworkImage).url, endsWith('/logos/abc.png'));
  });

  testWidgets('ChurchAvatar avec logo externe : URL inchangée',
      (tester) async {
    final ancienneOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = ancienneOnError);
    await tester.pumpWidget(_arbre(ChurchAvatar(
        church: _eglise(logoUrl: 'https://exemple.ci/logo.png'))));
    await tester.pump();
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect((avatar.backgroundImage as NetworkImage).url,
        'https://exemple.ci/logo.png');
  });
}
