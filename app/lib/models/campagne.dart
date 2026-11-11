import '../utils/format.dart';

/// Campagne de collecte, US2 : objectif FCFA strictement positif, période,
/// statut brouillon, active ou clôturée. Le total collecté est la somme
/// des contributions confirmées affectées ; au-delà de 100 % de l'objectif,
/// l'écran l'indique explicitement (`depasse`), le pourcentage n'est jamais
/// plafonné ni masqué.
class Campagne {
  final String id;
  final String nom;
  final int objectifFcfa;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final String statut; // brouillon | active | cloturee
  final bool visibleMembres;
  final int totalCollecte;
  final int pourcentage;
  final bool depasse;
  final int nombreContributions;

  const Campagne({
    required this.id,
    required this.nom,
    required this.objectifFcfa,
    this.dateDebut,
    this.dateFin,
    required this.statut,
    required this.visibleMembres,
    required this.totalCollecte,
    required this.pourcentage,
    required this.depasse,
    required this.nombreContributions,
  });

  factory Campagne.fromJson(Map<String, dynamic> json) {
    final objectif = (json['objectif_fcfa'] as num).toInt();
    final total = (json['total_collecte'] as num?)?.toInt() ?? 0;
    final pourcentage = (json['pourcentage'] as num?)?.toInt() ??
        (objectif > 0 ? (total * 100 / objectif).round() : 0);
    return Campagne(
      id: json['id'] as String,
      nom: json['nom'] as String,
      objectifFcfa: objectif,
      dateDebut: parseDate(json['date_debut'] as String?),
      dateFin: parseDate(json['date_fin'] as String?),
      statut: json['statut'] as String? ?? 'brouillon',
      visibleMembres: json['visible_membres'] as bool? ?? false,
      totalCollecte: total,
      pourcentage: pourcentage,
      depasse: json['depasse'] as bool? ?? pourcentage > 100,
      nombreContributions:
          (json['nombre_contributions'] as num?)?.toInt() ?? 0,
    );
  }

  static String labelForStatut(String statut) {
    switch (statut) {
      case 'brouillon':
        return 'Brouillon';
      case 'active':
        return 'Active';
      case 'cloturee':
        return 'Clôturée';
      default:
        return statut;
    }
  }

  String get statutLabel => labelForStatut(statut);
}
