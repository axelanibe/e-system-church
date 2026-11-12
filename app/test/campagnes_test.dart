import 'package:esystem_church/models/campagne.dart';
import 'package:esystem_church/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Campagne.fromJson lit nom, objectif, période et statut', () {
    final c = Campagne.fromJson({
      'id': 'c1',
      'nom': 'Construction du temple',
      'objectif_fcfa': 1000000,
      'date_debut': '2026-11-01',
      'date_fin': '2027-03-31',
      'statut': 'active',
      'visible_membres': true,
      'total_collecte': 250000,
      'pourcentage': 25,
      'depasse': false,
      'nombre_contributions': 3,
    });
    expect(c.nom, 'Construction du temple');
    expect(c.objectifFcfa, 1000000);
    expect(c.statut, 'active');
    expect(c.statutLabel, 'Active');
    expect(c.visibleMembres, isTrue);
    expect(c.totalCollecte, 250000);
    expect(c.pourcentage, 25);
    expect(c.depasse, isFalse);
    expect(c.nombreContributions, 3);
    expect(c.dateDebut, DateTime(2026, 11, 1));
    expect(c.dateFin, DateTime(2027, 3, 31));
  });

  test('Campagne.fromJson : dépassement calculé quand le serveur ne le donne pas', () {
    final c = Campagne.fromJson({
      'id': 'c2',
      'nom': 'Toiture',
      'objectif_fcfa': 100000,
      'statut': 'active',
      'total_collecte': 125000,
    });
    expect(c.pourcentage, 125);
    expect(c.depasse, isTrue);
  });

  test('Campagne.fromJson : valeurs par défaut, brouillon et invisible', () {
    final c = Campagne.fromJson({
      'id': 'c3',
      'nom': 'Nouvelle campagne',
      'objectif_fcfa': 50000,
    });
    expect(c.statut, 'brouillon');
    expect(c.statutLabel, 'Brouillon');
    expect(c.visibleMembres, isFalse);
    expect(c.totalCollecte, 0);
    expect(c.pourcentage, 0);
    expect(c.depasse, isFalse);
  });

  test('Campagne.labelForStatut couvre les trois statuts', () {
    expect(Campagne.labelForStatut('brouillon'), 'Brouillon');
    expect(Campagne.labelForStatut('active'), 'Active');
    expect(Campagne.labelForStatut('cloturee'), 'Clôturée');
  });

  test('formatDateSeule : minuit UTC ne décale pas le jour (E9)', () {
    // Le serveur renvoie les dates DATE en minuit UTC ; en heure de
    // Montréal (UTC−5), `.toLocal()` les faisait tomber la veille.
    expect(formatDateSeule(DateTime.utc(2026, 11, 11)), '11/11/2026');
    expect(formatDateSeule(DateTime.utc(2026, 11, 30)), '30/11/2026');
    expect(formatDateSeule(DateTime(2026, 11, 11)), '11/11/2026');
    expect(formatDateSeule(null), '—');
  });

  test('Campagne.fromJson en ISO UTC minuit s\'affiche sans décalage', () {
    final c = Campagne.fromJson({
      'id': 'c4',
      'nom': 'Campagne test',
      'objectif_fcfa': 100000,
      'date_debut': '2026-11-11T00:00:00.000Z',
      'date_fin': '2026-11-30T00:00:00.000Z',
      'statut': 'active',
      'total_collecte': 0,
    });
    expect(formatDateSeule(c.dateDebut), '11/11/2026');
    expect(formatDateSeule(c.dateFin), '30/11/2026');
  });
}
