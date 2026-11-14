import 'package:esystem_church/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logo officiel : les 5 parties base64 se réassemblent et décodent
/// en une image affichée (et non en repli sur l'icône église).
void main() {
  testWidgets('AppLogo affiche le logo officiel', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLogo())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.church), findsNothing);
  });
}
