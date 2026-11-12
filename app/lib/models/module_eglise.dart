/// Module d'une église, tel que renvoyé par le détail d'une annexe.
///
/// Tous les modules sont actifs pour toutes les églises (règle du
/// 11/11/2026) : il n'y a plus de choix d'activation, `actif` vaut
/// toujours vrai. Le champ reste pour compatibilité avec la réponse
/// du serveur.
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
