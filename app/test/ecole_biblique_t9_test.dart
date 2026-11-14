import 'package:esystem_church/demo/mock_api_service.dart';
import 'package:esystem_church/demo/mock_data.dart';
import 'package:esystem_church/models/bible.dart';
import 'package:esystem_church/models/ecole_biblique.dart';
import 'package:esystem_church/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tranche T9 — Bible (Louis Segond 1910, domaine public) et école
/// biblique : modèles et repli démo (assets bundlés + mémoire).
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  // Les lectures d'assets (rootBundle) exigent le binding, même dans
  // les tests unitaires.
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LivreBible', () {
    test('parse le canon (code, nom, testament, chapitres)', () {
      final l = LivreBible.fromJson(const {
        'code': 'PSA',
        'nom': 'Psaumes',
        'testament': 'ancien',
        'chapitres': 150,
      });
      expect(l.code, 'PSA');
      expect(l.nom, 'Psaumes');
      expect(l.testament, 'ancien');
      expect(l.chapitres, 150);
    });
  });

  group('ChapitreBible', () {
    test('parse un chapitre et ses versets numérotés', () {
      final c = ChapitreBible.fromJson(const {
        'livre': 'Genèse',
        'code': 'GEN',
        'chapitre': 1,
        'chapitres': 50,
        'versets': [
          {'numero': 1, 'texte': 'Au commencement, Dieu créa les cieux et la terre.'},
          {'numero': 2, 'texte': 'La terre était informe et vide.'},
        ],
      });
      expect(c.livre, 'Genèse');
      expect(c.versets.length, 2);
      expect(c.versets[0].numero, 1);
      expect(c.versets[0].texte, contains('Au commencement'));
    });
  });

  group('ResultatRechercheBible', () {
    test('parse un résultat et sa référence', () {
      final r = ResultatRechercheBible.fromJson(const {
        'livre': 'Psaumes',
        'code': 'PSA',
        'chapitre': 23,
        'verset': 1,
        'texte': 'L’Éternel est mon berger.',
      });
      expect(r.reference, 'Psaumes 23:1');
      expect(r.texte, contains('berger'));
    });
  });

  group('CoursEcole', () {
    test('parse un cours et ses libellés de niveau', () {
      final c = CoursEcole.fromJson(const {
        'id': 'c1',
        'titre': 'Fondements de la foi',
        'description': 'Les bases.',
        'niveau': 'debutant',
        'actif': true,
      });
      expect(c.titre, 'Fondements de la foi');
      expect(c.niveauLabel, 'Débutant');
      const sansNiveau = CoursEcole(id: 'c2', titre: 'Ouvert');
      expect(sansNiveau.niveauLabel, 'Tous niveaux');
      expect(sansNiveau.actif, isTrue);
    });
  });

  group('LeconEcole', () {
    test('parse une leçon avec référence biblique', () {
      final l = LeconEcole.fromJson(const {
        'id': 'l1',
        'cours_id': 'c1',
        'ordre': 2,
        'titre': 'La foi qui sauve',
        'contenu': 'Dieu a tant aimé le monde…',
        'reference_biblique': 'Jean 3:16',
      });
      expect(l.ordre, 2);
      expect(l.referenceBiblique, 'Jean 3:16');
    });
  });

  group('InscriptionEcole', () {
    test('parse une inscription et ses libellés de statut', () {
      final i = InscriptionEcole.fromJson(const {
        'id': 'i1',
        'cours_id': 'c1',
        'member_id': 'm1',
        'statut': 'inscrit',
        'date_inscription': '2026-11-10',
      });
      expect(i.statutLabel, 'Inscrit');
      expect(i.dateInscription, '2026-11-10');
    });
  });

  group('ProgressionCours', () {
    test('parse une progression 1/2, 50 %', () {
      final p = ProgressionCours.fromJson(const {
        'inscription': {
          'id': 'i1',
          'cours_id': 'c1',
          'member_id': 'm1',
          'statut': 'inscrit',
        },
        'lecons': [
          {
            'id': 'l1',
            'ordre': 1,
            'titre': 'Dieu créateur',
            'termine': true,
          },
          {
            'id': 'l2',
            'ordre': 2,
            'titre': 'La foi qui sauve',
            'termine': false,
          },
        ],
        'terminees': 1,
        'total': 2,
        'pourcentage': 50,
      });
      expect(p.terminees, 1);
      expect(p.total, 2);
      expect(p.pourcentage, 50);
      expect(p.lecons[0].termine, isTrue);
      expect(p.lecons[1].termine, isFalse);
    });
  });

  group('repli démo — Bible (assets bundlés)', () {
    test('canon complet : 66 livres', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final livres = await api.getLivresBible();
      expect(livres.length, 66);
      expect(livres.firstWhere((l) => l.code == 'GEN').chapitres, 50);
      expect(livres.firstWhere((l) => l.code == 'PSA').chapitres, 150);
      expect(livres.firstWhere((l) => l.code == 'JHN').chapitres, 21);
      expect(livres.firstWhere((l) => l.code == 'REV').chapitres, 22);
    });

    test('GEN 1 : 31 versets, verset 1 exact', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final chapitre = await api.getChapitreBible(code: 'GEN', chapitre: 1);
      expect(chapitre.versets.length, 31);
      expect(chapitre.versets[0].texte,
          'Au commencement, Dieu créa les cieux et la terre.');
    });

    test('recherche « berger » : PSA 23:1 dans les résultats', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final resultats = await api.rechercherBible('berger');
      expect(
        resultats.any(
            (r) => r.code == 'PSA' && r.chapitre == 23 && r.verset == 1),
        isTrue,
      );
    });

    test('recherche trop courte : erreur', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      expect(() => api.rechercherBible('a'), throwsA(isA<ApiException>()));
    });
  });

  group('repli démo — école biblique', () {
    test('seed : 2 cours, 3 leçons, 1 inscription (1/2)', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final cours = await api.getCoursEcole();
      expect(cours.length, 2);
      expect(cours.first.titre, 'Fondements de la foi');
      final lecons =
          await api.getLeconsEcole(coursId: 'demo-cours-1');
      expect(lecons.length, 2);
      expect(lecons[0].ordre, 1);
      expect(lecons[1].ordre, 2);
      final progression =
          await api.getProgressionEcole('demo-insc-1');
      expect(progression.terminees, 1);
      expect(progression.total, 2);
      expect(progression.pourcentage, 50);
    });

    test('création de cours et ordre de leçon en doublon refusé', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final cours = await api.createCoursEcole(
        titre: 'Cours de test',
        niveau: 'debutant',
      );
      expect(cours.titre, 'Cours de test');
      expect(cours.niveauLabel, 'Débutant');
      await api.createLeconEcole(
        coursId: cours.id,
        ordre: 1,
        titre: 'Première leçon',
      );
      expect(
        () => api.createLeconEcole(
          coursId: cours.id,
          ordre: 1,
          titre: 'Doublon',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('inscription membre puis progression jusqu’à terminé', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.membreEmail,
password: DemoAccounts.password
      );
      final inscription =
          await api.inscrireEcole(coursId: 'demo-cours-2');
      expect(inscription.memberId, 'demo-m-001');
      expect(inscription.statut, 'inscrit');
      expect(
        () => api.inscrireEcole(coursId: 'demo-cours-2'),
        throwsA(isA<ApiException>()),
      );
      await api.terminerLeconEcole(
          inscriptionId: inscription.id, leconId: 'demo-lecon-3');
      final progression =
          await api.getProgressionEcole(inscription.id);
      expect(progression.terminees, 1);
      expect(progression.total, 1);
      expect(progression.pourcentage, 100);
      final inscriptions =
          await api.getInscriptionsEcole(coursId: 'demo-cours-2');
      expect(inscriptions.first.statut, 'termine');
    });

    test('statut « terminé » refusé par PATCH (posé par le serveur)', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      expect(
        () => api.updateInscriptionEcole(
            id: 'demo-insc-1', statut: 'termine'),
        throwsA(isA<ApiException>()),
      );
      final reprise = await api.updateInscriptionEcole(
          id: 'demo-insc-1', statut: 'abandonne');
      expect(reprise.statut, 'abandonne');
      expect(reprise.statutLabel, 'Abandonné');
    });
  });

  group('VersionBible', () {
    test('parse une version (id, nom, langue, livres, versets)', () {
      final v = VersionBible.fromJson(const {
        'id': 'kjv',
        'nom': 'King James Version',
        'langue': 'en',
        'livres': 66,
        'versets': 31102,
      });
      expect(v.id, 'kjv');
      expect(v.langue, 'en');
      expect(v.versets, 31102);
    });
  });

  group('EntreeStrong', () {
    test('parse une entrée et sa définition Strong', () {
      final e = EntreeStrong.fromJson(const {
        'numero': 'H1',
        'langue': 'hebreu',
        'lemma': 'אָב',
        'translit': 'ʼâb',
        'pron': 'awb',
        'derivation': 'a primitive word;',
        'strongs_def': 'father, in a literal and immediate application',
        'kjv_def': 'chief, father.',
      });
      expect(e.numero, 'H1');
      expect(e.lemma, 'אָב');
      expect(e.definition, contains('father'));
    });

    test('définition de repli : kjv_def quand strongs_def est absente',
        () {
      const e = EntreeStrong(
        numero: 'G687',
        langue: 'grec',
        lemma: 'ἆρα',
        translit: 'ara',
        kjvDef: 'therefore.',
      );
      expect(e.definition, 'therefore.');
      const sansRien = EntreeStrong(
        numero: 'G1',
        langue: 'grec',
        lemma: 'Α',
        translit: 'A',
      );
      expect(sansRien.definition, 'Aucune définition disponible.');
    });
  });

  group('ArticleDictionnaire', () {
    test('parse un article (titre, texte)', () {
      final a = ArticleDictionnaire.fromJson(const {
        'titre': 'Moïse',
        'texte': 'Moïse\n\nL’une des plus importantes personnes…',
      });
      expect(a.titre, 'Moïse');
      expect(a.texte, contains('Moïse'));
    });
  });

  group('repli démo — versions Bible (LS1910 + KJV)', () {
    test('2 versions : lsg1910 66 livres / 31 170 versets, kjv 66 / 31 102',
        () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final versions = await api.getVersionsBible();
      expect(versions.length, 2);
      final lsg = versions.firstWhere((v) => v.id == 'lsg1910');
      final kjv = versions.firstWhere((v) => v.id == 'kjv');
      expect(lsg.livres, 66);
      expect(lsg.versets, 31170);
      expect(kjv.livres, 66);
      expect(kjv.versets, 31102);
      expect(kjv.langue, 'en');
    });

    test('canon KJV : GEN = Genesis', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final livres = await api.getLivresBible(version: 'kjv');
      expect(livres.length, 66);
      expect(livres.firstWhere((l) => l.code == 'GEN').nom, 'Genesis');
      expect(livres.firstWhere((l) => l.code == 'PSA').nom, 'Psalms');
    });

    test('KJV GEN 1 : 31 versets, verset 1 exact', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final chapitre = await api.getChapitreBible(
          code: 'GEN', chapitre: 1, version: 'kjv');
      expect(chapitre.versets.length, 31);
      expect(chapitre.versets[0].texte,
          'In the beginning God created the heaven and the earth.');
    });

    test('recherche KJV « shepherd » : PSA 23:1', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final resultats =
          await api.rechercherBible('shepherd', version: 'kjv');
      expect(
        resultats.any(
            (r) => r.code == 'PSA' && r.chapitre == 23 && r.verset == 1),
        isTrue,
      );
    });
  });

  group('repli démo — concordance Strong (assets bundlés)', () {
    test('H1 : lemme אָב, définition « father »', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final entree = await api.getEntreeStrong('H1');
      expect(entree.numero, 'H1');
      expect(entree.lemma, 'אָב');
      expect(entree.definition, contains('father'));
    });

    test('g1 (minuscule) normalisé en G1', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final entree = await api.getEntreeStrong('g1');
      expect(entree.numero, 'G1');
      expect(entree.lemma, 'Α');
    });

    test('numéro invalide : erreur', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      expect(() => api.getEntreeStrong('XYZ'), throwsA(isA<ApiException>()));
      expect(
          () => api.getEntreeStrong('G9999'), throwsA(isA<ApiException>()));
    });

    test('recherche « father » : H1 dans les résultats', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final resultats = await api.rechercherStrong('father');
      expect(resultats.any((e) => e.numero == 'H1'), isTrue);
    });
  });

  group('repli démo — dictionnaire biblique (assets bundlés)', () {
    test('recherche « Moïse » (fra) : article « Moïse » trouvé', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final resultats = await api.rechercherDictionnaire('Moïse');
      expect(resultats.any((a) => a.titre == 'Moïse'), isTrue);
    });

    test('article « Moïse » : texte long, parle de l’Égypte', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final article = await api.getArticleDictionnaire('Moïse');
      expect(article.texte.length, greaterThan(1000));
      expect(article.texte, contains('Égypte'));
    });

    test('recherche « Moses » (eng) : article « Moses » trouvé', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      final resultats =
          await api.rechercherDictionnaire('Moses', langue: 'eng');
      expect(resultats.any((a) => a.titre == 'Moses'), isTrue);
      final article =
          await api.getArticleDictionnaire('Jesus', langue: 'eng');
      expect(article.texte.length, greaterThan(100));
    });

    test('article introuvable : erreur', () async {
      final api = MockApiService();
      await api.login(
        identifiant: DemoAccounts.adminEmail,
password: DemoAccounts.password
      );
      expect(() => api.getArticleDictionnaire('ZzzzzIntrouvable'),
          throwsA(isA<ApiException>()));
    });
  });
}
