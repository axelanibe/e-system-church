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

/// 2026-11-10T14:00:00.000Z → « 10/11/2026 ».
String formatDate(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
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
