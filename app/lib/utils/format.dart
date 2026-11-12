/// 1 → « 1 membre », 0 ou 3 → « 0 membres », « 3 membres ».
/// Le pluriel se donne tel quel quand il ne se forme pas avec un simple
/// « s » (ex. « membre actif » / « membres actifs »).
String pluriel(int nombre, String singulier, [String? plurielForme]) {
  final forme =
      nombre == 1 ? singulier : (plurielForme ?? '${singulier}s');
  return '$nombre $forme';
}

// Formatage des montants (FCFA) et des dates — sans dépendance `intl`
// (dépendances minimales voulues pour le MVP).

/// 25000 → « 25 000 FCFA ».
String formatFcfa(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  final sign = amount < 0 ? '-' : '';
  return '$sign${buffer.toString()} FCFA';
}

/// 25000, « EUR » → « 25 000 EUR » (même formatage que [formatFcfa],
/// avec la devise de l'église).
String formatMontant(int amount, String devise) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  final sign = amount < 0 ? '-' : '';
  return '$sign${buffer.toString()} $devise';
}

/// 2026-11-10T14:00:00.000Z → « 10/11/2026 ».
/// Horodatage réel : le passage à l'heure locale est voulu ici.
String formatDate(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day/$month/${d.year}';
}

/// Date simple (jour calendaire, sans heure) : « 11/11/2026 ».
/// Contrairement à [formatDate], aucun décalage de fuseau n'est appliqué :
/// une date renvoyée par le serveur en minuit UTC (« 2026-11-11T00:00:00Z »)
/// reste le 11/11, même en heure de Montréal (UTC−5) où `.toLocal()`
/// la ferait tomber au 10/11. À utiliser pour les dates seules
/// (période de campagne, date de dépense, baptême…), pas pour les
/// horodatages.
String formatDateSeule(DateTime? date) {
  if (date == null) return '—';
  final d = date.isUtc ? date.toUtc() : date;
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day/$month/${d.year}';
}

/// 2026-11-10T14:00:00.000Z → « 10/11/2026 14:00 ».
String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
  final hour = d.hour.toString().padLeft(2, '0');
  final minute = d.minute.toString().padLeft(2, '0');
  return '${formatDate(d)} $hour:$minute';
}

/// Date ISO « 2026-11-10 » (ou ISO complet) → DateTime, ou null.
DateTime? parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Affiche une date qui peut être un DateTime ou une chaîne ISO
/// (les modèles gardent les dates simples en chaîne, les horodatages en
/// DateTime) : « 10/11/2026 », ou « — ».
String afficherDate(dynamic value) {
  if (value == null) return '—';
  if (value is DateTime) return formatDate(value);
  if (value is String) {
    final parsed = parseDate(value);
    return parsed == null ? value : formatDate(parsed);
  }
  return value.toString();
}

/// Affiche une date-heure (DateTime ou chaîne ISO) : « 10/11/2026 14:00 ».
String afficherDateTime(dynamic value) {
  if (value == null) return '—';
  if (value is DateTime) return formatDateTime(value);
  if (value is String) {
    final parsed = parseDate(value);
    return parsed == null ? value : formatDateTime(parsed);
  }
  return value.toString();
}
