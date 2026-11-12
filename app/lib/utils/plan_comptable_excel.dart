import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/finances.dart';

/// Classeur Excel du rapport des dépenses : mêmes chiffres que l'écran
/// de suivi et que le PDF serveur, une feuille par section.
/// Librairie `excel` déjà utilisée pour l'import des membres.
Uint8List construireClasseurPlanComptable(RapportPlanComptable rapport) {
  final classeur = Excel.createExcel();
  classeur.rename('Sheet1', 'Par catégorie');
  final parCategorie = classeur['Par catégorie'];
  parCategorie.appendRow([
    TextCellValue('Catégorie'),
    TextCellValue('Prévu (FCFA)'),
    TextCellValue('Réel (FCFA)'),
  ]);
  for (final ligne in rapport.parCategories) {
    parCategorie.appendRow([
      TextCellValue(ligne.libelle),
      IntCellValue(ligne.prevuFcfa),
      IntCellValue(ligne.reelFcfa),
    ]);
  }
  parCategorie.appendRow([
    TextCellValue('Total'),
    IntCellValue(rapport.totalPrevuFcfa),
    IntCellValue(rapport.totalReelFcfa),
  ]);

  final parPoste = classeur['Par poste'];
  parPoste.appendRow([
    TextCellValue('Poste'),
    TextCellValue('Catégorie'),
    TextCellValue('Récurrente'),
    TextCellValue('Prévu (FCFA)'),
    TextCellValue('Réel (FCFA)'),
  ]);
  for (final ligne in rapport.parPostes) {
    parPoste.appendRow([
      TextCellValue(ligne.poste ?? '—'),
      TextCellValue(ligne.categorieCode ?? '—'),
      TextCellValue(
          ligne.recurrente == null ? '—' : ligne.recurrente! ? 'Oui' : 'Non'),
      IntCellValue(ligne.prevuFcfa),
      IntCellValue(ligne.reelFcfa),
    ]);
  }
  parPoste.appendRow([
    TextCellValue('Total'),
    TextCellValue(''),
    TextCellValue(''),
    IntCellValue(rapport.totalPrevuFcfa),
    IntCellValue(rapport.totalReelFcfa),
  ]);

  final depenses = classeur['Dépenses'];
  depenses.appendRow([
    TextCellValue('Référence'),
    TextCellValue('Date'),
    TextCellValue('Poste'),
    TextCellValue('Catégorie'),
    TextCellValue('Département'),
    TextCellValue('Mode de paiement'),
    TextCellValue('Fournisseur ou bénéficiaire'),
    TextCellValue('Motif'),
    TextCellValue('Montant (FCFA)'),
  ]);
  for (final d in rapport.depenses) {
    depenses.appendRow([
      TextCellValue(d['reference'] as String? ?? '—'),
      TextCellValue(_dateCourte(d['date_depense'])),
      TextCellValue(d['poste'] as String? ?? 'Sans poste'),
      TextCellValue(d['categorie_nom'] as String? ?? '—'),
      TextCellValue(d['departement_nom'] as String? ?? '—'),
      TextCellValue(
          Depense.labelForModePaiement(d['mode_paiement'] as String?)),
      TextCellValue(d['fournisseur_beneficiaire'] as String? ?? '—'),
      TextCellValue(d['motif'] as String? ?? ''),
      IntCellValue((d['montant_fcfa'] as num?)?.toInt() ?? 0),
    ]);
  }
  return Uint8List.fromList(classeur.encode()!);
}

/// « 2026-11-12 » ou « 2026-11-12T00:00:00.000Z » → « 12/11/2026 ».
String _dateCourte(Object? valeur) {
  if (valeur == null) return '—';
  final texte = valeur.toString();
  if (texte.length < 10) return texte;
  final partie = texte.substring(0, 10);
  final morceaux = partie.split('-');
  if (morceaux.length != 3) return partie;
  return '${morceaux[2]}/${morceaux[1]}/${morceaux[0]}';
}
