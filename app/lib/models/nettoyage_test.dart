/// Nettoyage des données TEST (audit fonctionnel du 11 novembre 2026).
///
/// Un élément = une donnée marquée TEST trouvée par l'aperçu
/// (`POST /admin/nettoyage-test`) ou supprimée par la confirmation :
/// transfert, membre, contribution, campagne, attestation ou sous-église.
class NettoyageTestElement {
  final String type; // transfert | membre | contribution | campagne | attestation | eglise
  final String id;
  final String label;

  const NettoyageTestElement({
    required this.type,
    required this.id,
    required this.label,
  });

  factory NettoyageTestElement.fromJson(Map<String, dynamic> json) =>
      NettoyageTestElement(
        type: json['type'] as String,
        id: json['id'] as String,
        label: json['label'] as String,
      );
}

/// Aperçu du nettoyage : ce qui serait supprimé, sans rien supprimer.
class NettoyageTestApercu {
  final List<NettoyageTestElement> elements;

  const NettoyageTestApercu({required this.elements});

  int get total => elements.length;

  factory NettoyageTestApercu.fromJson(Map<String, dynamic> json) =>
      NettoyageTestApercu(
        elements: (json['elements'] as List<dynamic>)
            .map((e) => NettoyageTestElement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Résultat de la suppression confirmée.
class NettoyageTestResultat {
  final List<NettoyageTestElement> supprimes;

  const NettoyageTestResultat({required this.supprimes});

  int get total => supprimes.length;

  factory NettoyageTestResultat.fromJson(Map<String, dynamic> json) =>
      NettoyageTestResultat(
        supprimes: (json['supprimes'] as List<dynamic>)
            .map((e) => NettoyageTestElement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
