/// Module d'une église, US1 : noyau toujours actif ou module activable.
///
/// Le serveur renvoie le noyau (membres, finances, rapports, `noyau: true`,
/// toujours actifs) et les modules activables avec leur état. Une église
/// décide seule pour elle-même ; la mère ne force pas ses antennes.
class ModuleEglise {
  final String code;
  final String label;
  final bool noyau;
  final bool actif;

  const ModuleEglise({
    required this.code,
    required this.label,
    required this.noyau,
    required this.actif,
  });

  factory ModuleEglise.fromJson(Map<String, dynamic> json) => ModuleEglise(
        code: json['code'] as String,
        label: json['label'] as String,
        noyau: json['noyau'] as bool? ?? false,
        actif: json['actif'] as bool? ?? false,
      );

  ModuleEglise copyWith({bool? actif}) => ModuleEglise(
        code: code,
        label: label,
        noyau: noyau,
        actif: actif ?? this.actif,
      );
}

/// Codes des modules activables, mêmes que côté serveur (`server/src/modules.ts`).
class CodesModules {
  static const String annonces = 'annonces';
  static const String familles = 'familles';
  static const String cultes = 'cultes';
  static const String presences = 'presences';
  static const String budget = 'budget';
  static const String prieres = 'prieres';
  static const String pastoral = 'pastoral';
  static const String serviteurs = 'serviteurs';
  static const String enfants = 'enfants';
  static const String medias = 'medias';
  static const String biens = 'biens';
  static const String parametres = 'parametres';
  static const String monEglise = 'mon_eglise';

  /// Codes du noyau, toujours actifs.
  static const List<String> noyau = ['membres', 'finances', 'rapports'];
}
