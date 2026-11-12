import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/rapport_annexe.dart';

/// Tranche P5 : Rapports à mon église mère.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('Types de rapport', () {
    test('les trois types, dans l’ordre de la projection', () {
      expect(typesRapportAnnexe.keys.toList(), [
        'bilan_annuel',
        'bilan_activite',
        'rapport_financier',
      ]);
      expect(typesRapportAnnexe['bilan_annuel'], 'Bilan annuel');
      expect(typesRapportAnnexe['bilan_activite'], 'Bilan d’activité');
      expect(typesRapportAnnexe['rapport_financier'], 'Rapport financier');
    });
  });

  group('EgliseMereContact', () {
    test('parse la mère avec adresse e-mail', () {
      final mere = EgliseMereContact.fromJson(const {
        'id': 'mere-1',
        'nom': 'Église mère EXEMPLE',
        'email': 'mere@exemple.ci',
      });
      expect(mere.id, 'mere-1');
      expect(mere.nom, 'Église mère EXEMPLE');
      expect(mere.email, 'mere@exemple.ci');
    });

    test('parse la mère sans adresse e-mail : À compléter', () {
      final mere = EgliseMereContact.fromJson(const {
        'id': 'mere-1',
        'nom': 'Église mère EXEMPLE',
        'email': null,
      });
      expect(mere.email, isNull);
    });
  });

  group('RapportAnnexe', () {
    test('parse un rapport en attente d’envoi', () {
      final rapport = RapportAnnexe.fromJson(const {
        'id': 'rapport-1',
        'type': 'bilan_annuel',
        'message': 'Message EXEMPLE',
        'membres': 0,
        'recettes_fcfa': 0,
        'depenses_fcfa': 0,
        'solde_fcfa': 0,
        'statut': 'en_attente_envoi',
        'cree_le': '2026-11-12T10:00:00.000Z',
        'eglise_nom': 'Annexe EXEMPLE',
      });
      expect(rapport.type, 'bilan_annuel');
      expect(rapport.typeLibelle, 'Bilan annuel');
      expect(rapport.message, 'Message EXEMPLE');
      expect(rapport.membres, 0);
      expect(rapport.recettesFcfa, 0);
      expect(rapport.depensesFcfa, 0);
      expect(rapport.soldeFcfa, 0);
      expect(rapport.statut, 'en_attente_envoi');
      expect(rapport.enAttenteEnvoi, isTrue);
      expect(rapport.egliseNom, 'Annexe EXEMPLE');
    });

    test('libellés des trois types', () {
      RapportAnnexe rapport(String type) => RapportAnnexe(
            id: 'r',
            type: type,
            membres: 0,
            recettesFcfa: 0,
            depensesFcfa: 0,
            soldeFcfa: 0,
            statut: 'en_attente_envoi',
          );
      expect(rapport('bilan_annuel').typeLibelle, 'Bilan annuel');
      expect(rapport('bilan_activite').typeLibelle, 'Bilan d’activité');
      expect(
        rapport('rapport_financier').typeLibelle,
        'Rapport financier',
      );
    });

    test('un rapport envoyé n’est plus en attente', () {
      const rapport = RapportAnnexe(
        id: 'r',
        type: 'bilan_annuel',
        membres: 0,
        recettesFcfa: 0,
        depensesFcfa: 0,
        soldeFcfa: 0,
        statut: 'envoye',
      );
      expect(rapport.enAttenteEnvoi, isFalse);
    });

    test('les chiffres d’exemple du bilan annuel sont cohérents', () {
      const recettes = 2450000;
      const depenses = 1980000;
      expect(recettes - depenses, 470000);
    });
  });
}
