import 'package:flutter/services.dart';

/// Formateur de saisie des codes d'église (`ESC-…`, `ESC-F-…`, `ESC-T-…`).
///
/// L'utilisateur ne tape jamais le tiret « - » : il tape seulement les
/// caractères, le champ insère le préfixe et les tirets tout seul, en
/// majuscules. Coller un code complet (avec ou sans tirets, minuscules
/// incluses) fonctionne aussi.
///
/// Accepte les NOUVEAUX codes (`ESC-` + 4 chiffres, ex. ESC-0411) et les
/// ANCIENS codes (suffixe alphanumérique jusqu'à 6 caractères,
/// ex. ESC-XZ2SCA) : le préfixe tapé (ESC / ESCF / ESCT) est détecté,
/// sinon c'est le préfixe attendu par l'écran qui est appliqué.
///
/// Limite connue : un suffixe uniquement composé de chiffres est plafonné
/// à 4 chiffres (nouveau modèle). Un ancien code dont le suffixe serait
/// 6 chiffres serait tronqué à 4 et refusé par le serveur — cas quasi
/// impossible (1 chance sur ~4000 par code, aucun connu) : le membre
/// devra alors recopier le code complet, qui sera refusé de la même façon.
class CodeInputFormatter extends TextInputFormatter {
  CodeInputFormatter({required this.expectedPrefix});

  /// Préfixe attendu par l'écran, ex. 'ESC-F-' ou 'ESC-'.
  final String expectedPrefix;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Normalise : majuscules, sans espaces ni tirets.
    final raw =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (raw.isEmpty) return const TextEditingValue();

    // 2. Détecte le préfixe tapé (ESCF / ESCT / ESC), sinon celui de l'écran.
    String prefix;
    String rest;
    if (raw.startsWith('ESCF')) {
      prefix = 'ESC-F-';
      rest = raw.substring(4);
    } else if (raw.startsWith('ESCT')) {
      prefix = 'ESC-T-';
      rest = raw.substring(4);
    } else if (raw.startsWith('ESC')) {
      prefix = expectedPrefix;
      rest = raw.substring(3);
    } else if (raw == 'E' || raw == 'ES') {
      // Préfixe en cours de frappe : on le laisse tel quel.
      return TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      );
    } else {
      prefix = expectedPrefix;
      rest = raw;
    }

    // 3. Suffixe : lettres et chiffres seulement.
    rest = rest.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    // 4. Plafond : 4 chiffres pour les nouveaux codes, 6 caractères
    // pour les anciens codes alphanumériques.
    if (rest.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(rest)) {
      if (rest.length > 4) rest = rest.substring(0, 4);
    } else if (rest.length > 6) {
      rest = rest.substring(0, 6);
    }

    // 5. Préfixe nu : on l'affiche (le tiret apparaît tout seul). Si
    // l'utilisateur efface ce préfixe nu, le champ se vide — sinon le
    // préfixe resterait collé et ne pourrait plus être effacé.
    if (rest.isEmpty) {
      if (newValue.text.length < oldValue.text.length &&
          oldValue.text == prefix) {
        return const TextEditingValue();
      }
      return TextEditingValue(
        text: prefix,
        selection: TextSelection.collapsed(offset: prefix.length),
      );
    }

    final formatted = '$prefix$rest';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
