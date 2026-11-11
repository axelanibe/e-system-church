import 'package:esystem_church/models/church.dart';
import 'package:esystem_church/models/membres_complement.dart';
import 'package:esystem_church/models/member.dart';
import 'package:esystem_church/widgets/church_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Église mère : sans mère, isMere est vrai', () {
    const eglise = Church(
      id: 'e1',
      code: 'ESC-AAAAAA',
      name: 'Grâce Divine',
      status: 'active',
    );
    expect(eglise.isMere, isTrue);
  });

  test('Sous-église : avec mère, isMere est faux', () {
    const eglise = Church(
      id: 'e2',
      code: 'ESC-BBBBBB',
      name: 'Grâce Divine Plateau',
      parentChurchId: 'e1',
      status: 'active',
    );
    expect(eglise.isMere, isFalse);
  });

  test('Avatar : texte blanc sur fond sombre, sauge foncé sur fond clair', () {
    expect(
      ChurchAvatar.texteSur(const Color(0xFF3F5A50)),
      Colors.white,
    );
    expect(
      ChurchAvatar.texteSur(const Color(0xFFC9A24B)),
      const Color(0xFF3F5A50),
    );
  });

  test('Catalogue de départ : 16 départements', () {
    expect(departementsParDefaut.length, 16);
    expect(departementsParDefaut.first, 'Prière et intercession');
    expect(departementsParDefaut.last, 'Action sociale et solidarité');
    expect(departementsParDefaut.toSet().length, 16);
  });

  test('Catalogue de départ : 12 fonctions, dont Aucun', () {
    expect(fonctionsParDefaut.length, 12);
    expect(fonctionsParDefaut.first, 'Pasteur');
    expect(fonctionsParDefaut.last, 'Aucun');
    expect(fonctionsParDefaut.toSet().length, 12);
  });

  test('Catalogue de départ : 5 postes', () {
    expect(postesParDefaut.length, 5);
    expect(postesParDefaut.first, 'Directeur de département');
    expect(postesParDefaut.last, 'Collaborateur ou bénévole');
  });

  test('Membre sans fonction : la carte montre Membre', () {
    final membre = Member.fromJson({
      'id': 'm1',
      'matricule': 'M-0001',
      'full_name': 'Awa Koné',
      'status': 'actif',
    });
    expect(membre.fonction, isNull);
    expect(membre.fonctionAffichee, 'Membre');
  });

  test('Membre avec fonction Aucun : la carte montre Membre', () {
    final membre = Member.fromJson({
      'id': 'm1',
      'matricule': 'M-0001',
      'full_name': 'Awa Koné',
      'fonction': 'Aucun',
      'poste': 'Collaborateur ou bénévole',
      'status': 'actif',
    });
    expect(membre.fonctionAffichee, 'Membre');
    expect(membre.poste, 'Collaborateur ou bénévole');
  });

  test('Membre avec fonction : la carte montre la fonction', () {
    final membre = Member.fromJson({
      'id': 'm1',
      'matricule': 'M-0001',
      'full_name': 'Awa Koné',
      'department': 'Louange et adoration',
      'fonction': 'Chantre',
      'poste': 'Chef de service ou d’équipe',
      'status': 'actif',
    });
    expect(membre.fonctionAffichee, 'Chantre');
    expect(membre.department, 'Louange et adoration');
    expect(membre.poste, 'Chef de service ou d’équipe');
  });

  test('Fonction.fromJson et Poste.fromJson lisent id et nom', () {
    final fonction = Fonction.fromJson({'id': 'f1', 'nom': 'Pasteur'});
    expect(fonction.nom, 'Pasteur');
    final poste = Poste.fromJson({'id': 'p1', 'nom': 'Directeur adjoint'});
    expect(poste.nom, 'Directeur adjoint');
  });
}
