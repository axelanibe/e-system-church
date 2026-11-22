/// Validations partagées des formulaires (Tranche Formulaires P0,
/// 21/11/2026) : messages d'erreur précis, pas génériques — « Entrez
/// un numéro de téléphone à 10 chiffres », pas « Ce champ est requis ».
///
/// Règle téléphone : les numéros ivoiriens comptent 10 chiffres
/// (mobiles 01/05/07, fixes 27…), avec ou sans indicatif +225.
/// Les espaces, points et tirets sont ignorés à la saisie.
String? validerTelephoneCI(String? valeur, {bool obligatoire = true}) {
  final v = (valeur ?? '').trim();
  if (v.isEmpty) {
    return obligatoire ? 'Entrez un numéro de téléphone.' : null;
  }
  final chiffres = v.replaceAll(RegExp(r'[\s.\-]'), '');
  final sansIndicatif = chiffres.startsWith('+225')
      ? chiffres.substring(4)
      : chiffres.startsWith('225') && chiffres.length == 13
          ? chiffres.substring(3)
          : chiffres;
  if (!RegExp(r'^\d{10}$').hasMatch(sansIndicatif)) {
    return 'Entrez un numéro de téléphone à 10 chiffres '
        '(ex. 07 07 07 07 07).';
  }
  return null;
}

/// E-mail facultatif : vide accepté, sinon forme « a@b.c » exigée.
String? validerEmailSimple(String? valeur) {
  final v = (valeur ?? '').trim();
  if (v.isEmpty) return null;
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
    return 'Entrez une adresse e-mail valide (ex. prenom@mail.com).';
  }
  return null;
}
