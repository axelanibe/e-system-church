import 'package:esystem_church/services/api_service.dart';
import 'package:esystem_church/services/bible_hors_ligne_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tranche T9 (fin) — Bible hors ligne : le service réel lit les JSON
/// bundlés (LSG 1910, KJV, Strong, dictionnaire), sans aucun appel
/// réseau. Mêmes valeurs attendues que le service faux (test T9).
void main() {
  // Les lectures d'assets (rootBundle) exigent le binding, même dans
  // les tests unitaires.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BibleHorsLigneService — versions et canon', () {
    test('2 versions : lsg1910 66 livres / 31 170 versets, kjv 66 / 31 102',
        () async {
      final service = BibleHorsLigneService();
      final versions = await service.getVersionsBible();
      expect(versions.length, 2);
      final lsg = versions.firstWhere((v) => v.id == 'lsg1910');
      final kjv = versions.firstWhere((v) => v.id == 'kjv');
      expect(lsg.livres, 66);
      expect(lsg.versets, 31170);
      expect(kjv.livres, 66);
      expect(kjv.versets, 31102);
      expect(kjv.langue, 'en');
    });

    test('canon LSG : 66 livres, GEN 50, PSA 150, JHN 21, REV 22', () async {
      final service = BibleHorsLigneService();
      final livres = await service.getLivresBible();
      expect(livres.length, 66);
      expect(livres.firstWhere((l) => l.code == 'GEN').chapitres, 50);
      expect(livres.firstWhere((l) => l.code == 'PSA').chapitres, 150);
      expect(livres.firstWhere((l) => l.code == 'JHN').chapitres, 21);
      expect(livres.firstWhere((l) => l.code == 'REV').chapitres, 22);
    });

    test('canon KJV : GEN = Genesis', () async {
      final service = BibleHorsLigneService();
      final livres = await service.getLivresBible(version: 'kjv');
      expect(livres.length, 66);
      expect(livres.firstWhere((l) => l.code == 'GEN').nom, 'Genesis');
      expect(livres.firstWhere((l) => l.code == 'PSA').nom, 'Psalms');
    });
  });

  group('BibleHorsLigneService — lecture et recherche', () {
    test('GEN 1 : 31 versets, verset 1 exact', () async {
      final service = BibleHorsLigneService();
      final chapitre =
          await service.getChapitreBible(code: 'GEN', chapitre: 1);
      expect(chapitre.versets.length, 31);
      expect(chapitre.versets[0].texte,
          'Au commencement, Dieu créa les cieux et la terre.');
    });

    test('KJV GEN 1 : 31 versets, verset 1 exact', () async {
      final service = BibleHorsLigneService();
      final chapitre = await service.getChapitreBible(
          code: 'GEN', chapitre: 1, version: 'kjv');
      expect(chapitre.versets.length, 31);
      expect(chapitre.versets[0].texte,
          'In the beginning God created the heaven and the earth.');
    });

    test('recherche « berger » : PSA 23:1 dans les résultats', () async {
      final service = BibleHorsLigneService();
      final resultats = await service.rechercherBible('berger');
      expect(
        resultats.any(
            (r) => r.code == 'PSA' && r.chapitre == 23 && r.verset == 1),
        isTrue,
      );
    });

    test('recherche KJV « shepherd » : PSA 23:1', () async {
      final service = BibleHorsLigneService();
      final resultats =
          await service.rechercherBible('shepherd', version: 'kjv');
      expect(
        resultats.any(
            (r) => r.code == 'PSA' && r.chapitre == 23 && r.verset == 1),
        isTrue,
      );
    });

    test('recherche trop courte : erreur', () async {
      final service = BibleHorsLigneService();
      expect(() => service.rechercherBible('a'),
          throwsA(isA<ApiException>()));
    });

    test('chapitre inexistant : erreur', () async {
      final service = BibleHorsLigneService();
      expect(() => service.getChapitreBible(code: 'GEN', chapitre: 999),
          throwsA(isA<ApiException>()));
    });
  });

  group('BibleHorsLigneService — concordance Strong', () {
    test('H1 : lemme אָב, définition « father »', () async {
      final service = BibleHorsLigneService();
      final entree = await service.getEntreeStrong('H1');
      expect(entree.numero, 'H1');
      expect(entree.lemma, 'אָב');
      expect(entree.definition, contains('father'));
    });

    test('g1 (minuscule) normalisé en G1', () async {
      final service = BibleHorsLigneService();
      final entree = await service.getEntreeStrong('g1');
      expect(entree.numero, 'G1');
      expect(entree.lemma, 'Α');
    });

    test('numéro invalide : erreur', () async {
      final service = BibleHorsLigneService();
      expect(() => service.getEntreeStrong('XYZ'),
          throwsA(isA<ApiException>()));
      expect(() => service.getEntreeStrong('G9999'),
          throwsA(isA<ApiException>()));
    });

    test('recherche « father » : H1 dans les résultats', () async {
      final service = BibleHorsLigneService();
      final resultats = await service.rechercherStrong('father');
      expect(resultats.any((e) => e.numero == 'H1'), isTrue);
    });
  });

  group('BibleHorsLigneService — dictionnaire biblique', () {
    test('recherche « Moïse » (fra) : article « Moïse » trouvé', () async {
      final service = BibleHorsLigneService();
      final resultats = await service.rechercherDictionnaire('Moïse');
      expect(resultats.any((a) => a.titre == 'Moïse'), isTrue);
    });

    test('article « Moïse » : texte long, parle de l’Égypte', () async {
      final service = BibleHorsLigneService();
      final article = await service.getArticleDictionnaire('Moïse');
      expect(article.texte.length, greaterThan(1000));
      expect(article.texte, contains('Égypte'));
    });

    test('recherche « Moses » (eng) : article « Moses » trouvé', () async {
      final service = BibleHorsLigneService();
      final resultats =
          await service.rechercherDictionnaire('Moses', langue: 'eng');
      expect(resultats.any((a) => a.titre == 'Moses'), isTrue);
      final article =
          await service.getArticleDictionnaire('Jesus', langue: 'eng');
      expect(article.texte.length, greaterThan(100));
    });

    test('article introuvable : erreur', () async {
      final service = BibleHorsLigneService();
      expect(() => service.getArticleDictionnaire('ZzzzzIntrouvable'),
          throwsA(isA<ApiException>()));
    });
  });
}
