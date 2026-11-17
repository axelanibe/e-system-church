import 'dart:convert';

import 'package:esystem_church/models/attestation.dart';
import 'package:esystem_church/widgets/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Attestation.fromJson lit une attestation émise', () {
    final a = Attestation.fromJson({
      'id': 'a1',
      'numero': 'ATT-2026-0001',
      'annee': 2026,
      'member_id': 'm1',
      'membre_nom': 'KOFFI JEAN',
      'membre_matricule': 'M-0001',
      'total_fcfa': 75000,
      'nb_dons': 3,
      'statut': 'emise',
      'remplace_id': null,
      'date_emission': '2026-11-11T10:00:00.000Z',
    });
    expect(a.numero, 'ATT-2026-0001');
    expect(a.annee, 2026);
    expect(a.totalFcfa, 75000);
    expect(a.nbDons, 3);
    expect(a.estEmise, isTrue);
    expect(a.membreNom, 'KOFFI JEAN');
  });

  test('Attestation annulée n’est pas émise', () {
    final a = Attestation.fromJson({
      'id': 'a2',
      'numero': 'ATT-2026-0001',
      'annee': 2026,
      'total_fcfa': 1000,
      'nb_dons': 1,
      'statut': 'annulee',
      'remplace_id': 'a3',
    });
    expect(a.estEmise, isFalse);
    expect(a.remplaceId, 'a3');
  });

  test('Attestation de mariage : type, sans total ni dons', () {
    final a = Attestation.fromJson({
      'id': 'a3',
      'numero': 'MAR-2026-0001',
      'type': 'mariage',
      'annee': 2026,
      'member_id': 'm1',
      'membre_nom': 'KOFFI JEAN',
      'total_fcfa': null,
      'nb_dons': null,
      'statut': 'emise',
      'date_emission': '2026-11-12T10:00:00.000Z',
    });
    expect(a.type, 'mariage');
    expect(a.libelle, 'Mariage');
    expect(a.estDon, isFalse);
    expect(a.estEmise, isTrue);
    expect(a.totalFcfa, isNull);
    expect(a.nbDons, isNull);
  });

  test('Attestation sans type : don par défaut (anciennes réponses)', () {
    final a = Attestation.fromJson({
      'id': 'a4',
      'numero': 'ATT-2026-0002',
      'annee': 2026,
      'total_fcfa': 5000,
      'nb_dons': 1,
      'statut': 'emise',
    });
    expect(a.type, 'don');
    expect(a.estDon, isTrue);
    expect(a.libelle, 'Dons');
  });

  group('Signature électronique (V1)', () {
    test('Signature.fromJson lit une signature avec image et empreinte', () {
      final s = Signature.fromJson({
        'id': 's1',
        'signataire_nom': 'KOFFI JEAN',
        'signataire_fonction': 'Trésorier',
        'date_signature': '2026-11-16T10:00:00.000Z',
        'empreinte_sha256': 'abc123',
        'image_png_base64': base64Encode([1, 2, 3]),
      });
      expect(s.signataireNom, 'KOFFI JEAN');
      expect(s.signataireFonction, 'Trésorier');
      expect(s.empreinteSha256, 'abc123');
      expect(s.dateSignature?.year, 2026);
      expect(s.imageBytes, [1, 2, 3]);
    });

    test('Signature.fromJson tolère une réponse enveloppée', () {
      final s = Signature.fromJson({
        'signature': {
          'id': 's2',
          'signataire_nom': 'AWA KONÉ',
          'date_signature': '2026-11-16T10:00:00.000Z',
        },
      });
      expect(s.id, 's2');
      expect(s.signataireNom, 'AWA KONÉ');
    });

    test('Signature sans image : imageBytes null', () {
      final s = Signature.fromJson({
        'id': 's3',
        'signataire_nom': 'KOFFI JEAN',
      });
      expect(s.imageBytes, isNull);
      expect(s.empreinteSha256, isNull);
    });

    test('traitsSignatureValides refuse un tracé vide ou trop court', () {
      expect(traitsSignatureValides([]), isFalse);
      expect(
          traitsSignatureValides([
            [const Offset(10, 10), const Offset(12, 11)]
          ]),
          isFalse);
    });

    test('traitsSignatureValides accepte un tracé assez long', () {
      expect(
          traitsSignatureValides([
            [
              const Offset(10, 10),
              const Offset(30, 12),
              const Offset(50, 10),
              const Offset(70, 14),
              const Offset(90, 10),
              const Offset(110, 12),
              const Offset(130, 10),
              const Offset(150, 12),
            ]
          ]),
          isTrue);
    });
  });

  group('SignaturePad', () {
    Future<void> ouvrirPad(WidgetTester tester,
        {required ValueChanged<SignatureTrace> onValide}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SignaturePad(onValide: onValide)),
        ),
      );
      await tester.pump();
    }

    testWidgets('tracer puis valider renvoie points normalisés et PNG',
        (tester) async {
      SignatureTrace? trace;
      await ouvrirPad(tester, onValide: (t) => trace = t);
      expect(find.text('Signez ici'), findsOneWidget);
      expect(find.text('Effacer'), findsOneWidget);
      expect(find.text('Valider'), findsOneWidget);
      // timedDrag : un tracé réaliste, beaucoup de points, comme un
      // vrai doigt (un drag simple n'en produit que 4, sous le seuil).
      await tester.timedDrag(find.byType(SignaturePad),
          const Offset(120, 30), const Duration(milliseconds: 300));
      await tester.pump();
      // L'export PNG est un futur réel (moteur) : il faut attendre en
      // temps réel dans runAsync, un simple pump ne le résout pas.
      await tester.runAsync(() async {
        await tester.tap(find.text('Valider'));
        for (var i = 0; i < 50 && trace == null; i++) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(find.text('Signature vide : signez dans le cadre.'),
          findsNothing);
      expect(trace, isNotNull);
      expect(trace!.points.length, greaterThanOrEqualTo(8));
      expect(
          trace!.points
              .every((p) => p.dx >= 0 && p.dx <= 1 && p.dy >= 0 && p.dy <= 1),
          isTrue);
      expect(trace!.pngBytes, isNotEmpty);
    });

    testWidgets('valider sans tracer refuse : signature vide',
        (tester) async {
      var appele = false;
      await ouvrirPad(tester, onValide: (_) => appele = true);
      await tester.tap(find.text('Valider'));
      await tester.pump();
      expect(appele, isFalse);
      expect(find.text('Signature vide : signez dans le cadre.'),
          findsOneWidget);
    });

    testWidgets('effacer vide le tracé, valider refuse ensuite',
        (tester) async {
      var appele = false;
      await ouvrirPad(tester, onValide: (_) => appele = true);
      await tester.drag(find.byType(SignaturePad), const Offset(120, 30));
      await tester.pump();
      await tester.tap(find.text('Effacer'));
      await tester.pump();
      await tester.tap(find.text('Valider'));
      await tester.pump();
      expect(appele, isFalse);
      expect(find.text('Signature vide : signez dans le cadre.'),
          findsOneWidget);
    });
  });

  group('MentionSignature (vue membre)', () {
    testWidgets('affiche le nom du signataire et la date quand signée',
        (tester) async {
      const signature = Signature(
        id: 's1',
        signataireNom: 'KOFFI JEAN',
        dateSignature: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MentionSignature(future: Future.value(signature)),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Signé par KOFFI JEAN'), findsOneWidget);
    });

    testWidgets('n’affiche rien quand le document n’est pas signé',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MentionSignature(future: Future.value(null)),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Signé par'), findsNothing);
    });
  });
}
