/// Lecture du QR de la carte de membre.
///
/// Format de la carte : `CODE_EGLISE:MATRICULE`, par exemple
/// `GD-PLAT:GD-002`. Les cartes anciennes ne contiennent que le matricule.
/// Le code de l'église est vérifié côté client pour refuser tout de suite
/// une carte d'une autre église ; le serveur reste l'autorité, il ne
/// retrouve le membre que dans l'église de la session.
class QrCarteResult {
  final String? matricule;
  final String? erreur;

  const QrCarteResult.ok(this.matricule) : erreur = null;
  const QrCarteResult.erreur(this.erreur) : matricule = null;

  bool get ok => matricule != null;
}

/// Lit le contenu brut d'un QR de carte et renvoie le matricule à pointer,
/// ou une erreur claire en français.
///
/// [codeEglise] est le code de l'église active de la session, par exemple
/// `GD-PLAT`. Si le QR porte un autre code, il est refusé ici.
QrCarteResult lireQrCarte(String brut, {String? codeEglise}) {
  final contenu = brut.trim();
  if (contenu.isEmpty) {
    return const QrCarteResult.erreur('QR vide ou illisible.');
  }
  final deuxPoints = contenu.indexOf(':');
  if (deuxPoints < 0) {
    return QrCarteResult.ok(contenu.toUpperCase());
  }
  final code = contenu.substring(0, deuxPoints).trim();
  final matricule = contenu.substring(deuxPoints + 1).trim();
  if (code.isEmpty || matricule.isEmpty) {
    return const QrCarteResult.erreur('QR de carte invalide.');
  }
  if (codeEglise != null &&
      code.toUpperCase() != codeEglise.toUpperCase()) {
    return QrCarteResult.erreur(
      'Cette carte appartient à une autre église (code $code). '
      'Elle ne peut pas être pointée ici.',
    );
  }
  return QrCarteResult.ok(matricule.toUpperCase());
}
