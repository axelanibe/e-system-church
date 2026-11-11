import 'module_eglise.dart';

int _asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Une église sous tutelle, vue par sa mère (`GET /annexes`) : nom, code,
/// ville, statut, niveau dans le réseau, et agrégats seulement, jamais
/// de données nominatives.
class Annexe {
  final String egliseId;
  final String egliseNom;
  final String egliseCode;
  final String? egliseVille;
  final String egliseStatut;
  final int niveau; // 1 = annexe directe, 2 = annexe d'une annexe, …
  final int membresActifs;
  final int nombreContributions;
  final int totalFcfa;

  const Annexe({
    required this.egliseId,
    required this.egliseNom,
    required this.egliseCode,
    this.egliseVille,
    required this.egliseStatut,
    this.niveau = 1,
    required this.membresActifs,
    required this.nombreContributions,
    required this.totalFcfa,
  });

  factory Annexe.fromJson(Map<String, dynamic> json) => Annexe(
        egliseId: json['eglise_id'] as String,
        egliseNom: json['eglise_nom'] as String,
        egliseCode: json['eglise_code'] as String,
        egliseVille: json['eglise_ville'] as String?,
        egliseStatut: json['eglise_statut'] as String? ?? 'active',
        niveau: _asInt(json['niveau'], 1),
        membresActifs: _asInt(json['membres_actifs']),
        nombreContributions: _asInt(json['nombre_contributions']),
        totalFcfa: _asInt(json['total_fcfa']),
      );
}

/// Détail d'une annexe (`GET /annexes/:id`) : chiffres, compteurs et
/// état de ses modules, pour que la mère voie directement ce qui s'y passe.
class AnnexeDetail {
  final String id;
  final String code;
  final String name;
  final String? city;
  final String status;
  final int membresActifs;
  final int nombreContributions;
  final int totalFcfa;
  final int depensesFcfa;
  final int cultes;
  final int presences;
  final int annonces;
  final List<ModuleEglise> modules;

  const AnnexeDetail({
    required this.id,
    required this.code,
    required this.name,
    this.city,
    required this.status,
    required this.membresActifs,
    required this.nombreContributions,
    required this.totalFcfa,
    required this.depensesFcfa,
    required this.cultes,
    required this.presences,
    required this.annonces,
    required this.modules,
  });

  factory AnnexeDetail.fromJson(Map<String, dynamic> json) {
    final eglise = json['eglise'] as Map<String, dynamic>;
    return AnnexeDetail(
      id: eglise['id'] as String,
      code: eglise['code'] as String,
      name: eglise['name'] as String,
      city: eglise['city'] as String?,
      status: eglise['status'] as String? ?? 'active',
      membresActifs: _asInt(json['membres_actifs']),
      nombreContributions: _asInt(json['nombre_contributions']),
      totalFcfa: _asInt(json['total_fcfa']),
      depensesFcfa: _asInt(json['depenses_fcfa']),
      cultes: _asInt(json['cultes']),
      presences: _asInt(json['presences']),
      annonces: _asInt(json['annonces']),
      modules: (json['modules'] as List<dynamic>? ?? [])
          .map((e) => ModuleEglise.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  int get modulesActifs => modules.where((m) => m.actif).length;
}
