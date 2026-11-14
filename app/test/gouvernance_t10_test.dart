import 'package:flutter_test/flutter_test.dart';

import 'package:esystem_church/models/attestation.dart';
import 'package:esystem_church/models/gouvernance.dart';
import 'package:esystem_church/models/parametres.dart';

/// Tranche T10 : gouvernance, secrétariat, documents, action sociale.
/// Données EXEMPLE uniquement, jamais de données réelles.
void main() {
  group('Mandat', () {
    test('parse un mandat en cours lié à sa décision', () {
      final m = Mandat.fromJson(const {
        'id': 'EXEMPLE-MANDAT-1',
        'member_id': 'EXEMPLE-M1',
        'fonction': 'Trésorier',
        'date_debut': '2026-01-15',
        'date_fin': '2027-01-14',
        'statut': 'en_cours',
        'decision_id': 'EXEMPLE-DEC-1',
      });
      expect(m.fonction, 'Trésorier');
      expect(m.enCours, isTrue);
      expect(m.statutLabel, 'En cours');
      expect(m.decisionId, 'EXEMPLE-DEC-1');
    });

    test('parse un mandat terminé sans date de fin', () {
      final m = Mandat.fromJson(const {
        'id': 'EXEMPLE-MANDAT-2',
        'member_id': 'EXEMPLE-M1',
        'fonction': 'Diacre',
        'date_debut': '2025-01-01',
        'statut': 'termine',
      });
      expect(m.enCours, isFalse);
      expect(m.statutLabel, 'Terminé');
      expect(m.dateFin, isNull);
    });
  });

  group('ReunionConseil et Decision', () {
    test('parse une réunion prévue', () {
      final r = ReunionConseil.fromJson(const {
        'id': 'EXEMPLE-REU-1',
        'titre': 'Conseil de janvier',
        'date_reunion': '2026-01-15T18:00:00Z',
        'lieu': 'Salle principale',
        'statut': 'prevue',
      });
      expect(r.titre, 'Conseil de janvier');
      expect(r.statutLabel, 'Prévue');
    });

    test('parse une décision adoptée liée à sa réunion', () {
      final d = Decision.fromJson(const {
        'id': 'EXEMPLE-DEC-1',
        'reunion_id': 'EXEMPLE-REU-1',
        'titre': 'Nomination du trésorier',
        'date_decision': '2026-01-15',
        'statut': 'adoptee',
      });
      expect(d.reunionId, 'EXEMPLE-REU-1');
      expect(d.statutLabel, 'Adoptée');
    });
  });

  group('ProcesVerbal', () {
    test('parse un procès-verbal brouillon sans signataire', () {
      final pv = ProcesVerbal.fromJson(const {
        'id': 'EXEMPLE-PV-1',
        'numero': 'PV-2026-001',
        'contenu': 'Le conseil a adopté la nomination.',
        'date_pv': '2026-01-15',
        'statut': 'brouillon',
      });
      expect(pv.statutLabel, 'Brouillon');
      expect(pv.signataire, isNull);
    });
  });

  group('GouvernanceDocument', () {
    test('parse un courrier entrant', () {
      final d = GouvernanceDocument.fromJson(const {
        'id': 'EXEMPLE-DOC-1',
        'titre': 'Courrier de la mairie',
        'categorie': 'courrier',
        'sens': 'entrant',
        'reference': 'M-2026-014',
      });
      expect(d.categorieLabel, 'Courrier');
      expect(d.sensLabel, 'Entrant');
    });

    test('parse un modèle de document', () {
      final d = GouvernanceDocument.fromJson(const {
        'id': 'EXEMPLE-DOC-2',
        'titre': 'Modèle de lettre officielle',
        'categorie': 'modele',
      });
      expect(d.categorieLabel, 'Modèle');
      expect(d.sensLabel, '—');
    });
  });

  group('Beneficiaire et Aide', () {
    test('parse un bénéficiaire actif', () {
      final b = Beneficiaire.fromJson(const {
        'id': 'EXEMPLE-BEN-1',
        'nom': 'Famille EXEMPLE',
        'besoin': 'Vivres pour le mois.',
        'statut': 'actif',
      });
      expect(b.statutLabel, 'Actif');
    });

    test('parse une aide financière versée', () {
      final a = Aide.fromJson(const {
        'id': 'EXEMPLE-AIDE-1',
        'beneficiaire_id': 'EXEMPLE-BEN-1',
        'type_aide': 'financier',
        'montant_fcfa': 25000,
        'date_aide': '2026-01-20',
        'statut': 'versee',
      });
      expect(a.typeLabel, 'Financière');
      expect(a.statutLabel, 'Versée');
      expect(a.montantFcfa, 25000);
    });
  });

  group('BienPatrimoine et MaintenancePatrimoine', () {
    test('parse un bâtiment avec code inventaire', () {
      final b = BienPatrimoine.fromJson(const {
        'id': 'EXEMPLE-BIEN-1',
        'nom': 'Temple principal',
        'categorie': 'batiment',
        'valeur_fcfa': 25000000,
        'code_inventaire': 'INV-001',
      });
      expect(b.categorieLabel, 'Bâtiment');
      expect(b.codeInventaire, 'INV-001');
    });

    test('parse une maintenance reliée à une dépense', () {
      final m = MaintenancePatrimoine.fromJson(const {
        'id': 'EXEMPLE-MAINT-1',
        'bien_id': 'EXEMPLE-BIEN-1',
        'description': 'Réparation de la toiture.',
        'cout_fcfa': 150000,
        'depense_id': 'EXEMPLE-DEP-1',
      });
      expect(m.depenseId, 'EXEMPLE-DEP-1');
      expect(m.coutFcfa, 150000);
    });
  });

  group('Certificat de membre et signataires', () {
    test('le type membre a son libellé', () {
      expect(Attestation.libelleType('membre'), 'Membre');
    });

    test('parse des paramètres avec signataires configurables', () {
      final p = EgliseParametres.fromJson(const {
        'signataire_nominations': 'Président du conseil',
        'signataire_proces_verbaux': 'Secrétaire du conseil',
      });
      expect(p.signataireNominations, 'Président du conseil');
      expect(p.signataireProcesVerbaux, 'Secrétaire du conseil');
    });

    test('parse des paramètres sans signataire', () {
      const p = EgliseParametres();
      expect(p.signataireNominations, isNull);
      expect(p.signataireProcesVerbaux, isNull);
    });
  });
}
