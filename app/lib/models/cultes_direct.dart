// Aides pures de l'écran Cultes en direct (tranche T5).
// Textes repris mot pour mot de la projection, application vierge.

import 'presences.dart';

/// Affiche une durée en secondes au format MM:SS (00:00 au départ).
String formatDureeChrono(int secondes) {
  final total = secondes < 0 ? 0 : secondes;
  final minutes = total ~/ 60;
  final reste = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${reste.toString().padLeft(2, '0')}';
}

/// Transposition suivante, bornée à une octave, de -11 à +11 demi-tons.
int transpositionSuivante(int actuelle, int delta) {
  return (actuelle + delta).clamp(-11, 11);
}

/// Compteur de portes suivant, jamais en dessous de zéro.
int compteurSuivant(int actuel, int delta) {
  final suivant = actuel + delta;
  return suivant < 0 ? 0 : suivant;
}

/// Vrai quand le moment en cours a atteint sa durée prévue en minutes.
/// Une durée nulle ou absente ne fait jamais avancer le conducteur.
bool momentTermine(int ecouleSecondes, int? dureeMinutes) {
  if (dureeMinutes == null || dureeMinutes <= 0) return false;
  return ecouleSecondes >= dureeMinutes * 60;
}

/// Nombre de présences pointées, statut present, pour le culte en direct.
int compterPresents(List<Presence> presences) {
  return presences.where((p) => p.statut == 'present').length;
}
