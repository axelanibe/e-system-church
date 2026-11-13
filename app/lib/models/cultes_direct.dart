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

// -- Compléments T5 r3 : jauge du compteur de portes, statistiques. --------

/// Capacité saisie par l'utilisateur, entier strictement positif.
/// Vide, texte non numérique ou zéro et moins : null (aucune capacité).
int? capaciteValide(String texte) {
  final valeur = int.tryParse(texte.trim());
  if (valeur == null || valeur <= 0) return null;
  return valeur;
}

/// Pourcentage d'entrées sur la capacité, arrondi. Null sans capacité.
int? pourcentageJauge(int entrees, int? capacite) {
  if (capacite == null || capacite <= 0) return null;
  return ((entrees / capacite) * 100).round();
}

/// Progression de la jauge entre 0 et 1, bornée à 1. Zéro sans capacité.
double progressionJauge(int entrees, int? capacite) {
  if (capacite == null || capacite <= 0) return 0;
  return (entrees / capacite).clamp(0.0, 1.0);
}

/// Titre d'une entrée « par culte » de GET /presences/stats.
/// Le serveur renvoie `culte_titre`, la démo `titre`.
String titreStatCulte(Map<String, dynamic> entree) {
  final titre = entree['culte_titre'] as String? ?? entree['titre'] as String?;
  if (titre == null || titre.isEmpty) return 'Culte';
  return titre;
}

/// Nom d'une entrée « par membre » de GET /presences/stats.
String nomStatMembre(Map<String, dynamic> entree) {
  final nom =
      entree['membre_nom'] as String? ?? entree['membre_matricule'] as String?;
  if (nom == null || nom.isEmpty) return 'Membre';
  return nom;
}

/// Nombre de présents d'une entrée de GET /presences/stats, 0 par défaut.
int presentsStat(Map<String, dynamic> entree) {
  return (entree['presents'] as num?)?.toInt() ?? 0;
}
