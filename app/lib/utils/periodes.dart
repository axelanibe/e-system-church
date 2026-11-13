// Périodes comptables (AAAA-MM et AAAA) : navigation par mois et par
// année pour les écrans Finances (cotisations, rapprochement,
// clôture, budgets par département).

/// Mois en français, index 1 à 12.
const nomsMoisFr = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

/// « novembre 2026 » pour une période AAAA-MM.
String libellePeriodeMois(String periode) {
  final annee = int.tryParse(periode.substring(0, 4)) ?? 0;
  final mois = int.tryParse(periode.substring(5, 7)) ?? 0;
  if (annee == 0 || mois < 1 || mois > 12) return periode;
  return '${nomsMoisFr[mois - 1].toLowerCase()} $annee';
}

/// Période AAAA-MM d'une date.
String periodeMois(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// Mois précédent d'une période AAAA-MM.
String moisPrecedent(String periode) {
  final annee = int.parse(periode.substring(0, 4));
  final mois = int.parse(periode.substring(5, 7));
  if (mois == 1) return '${annee - 1}-12';
  return '$annee-${(mois - 1).toString().padLeft(2, '0')}';
}

/// Mois suivant d'une période AAAA-MM.
String moisSuivant(String periode) {
  final annee = int.parse(periode.substring(0, 4));
  final mois = int.parse(periode.substring(5, 7));
  if (mois == 12) return '${annee + 1}-01';
  return '$annee-${(mois + 1).toString().padLeft(2, '0')}';
}

/// Dernier mois terminé : le mois précédent le mois en cours.
/// On ne clôture qu'un mois terminé, jamais le mois en cours.
String dernierMoisTermine([DateTime? maintenant]) {
  final ref = maintenant ?? DateTime.now();
  return moisPrecedent(periodeMois(ref));
}

/// Année précédente d'une période AAAA.
String anneePrecedente(String periode) =>
    '${(int.parse(periode) - 1)}';

/// Année suivante d'une période AAAA.
String anneeSuivante(String periode) => '${(int.parse(periode) + 1)}';
