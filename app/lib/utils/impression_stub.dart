/// Hors web (APK) : l'impression des cartes n'existe pas, l'appel
/// ne fait rien. L'écran d'impression l'indique avant d'appeler.
void imprimerPage() {}

/// Faux hors web.
bool get impressionWebDisponible => false;
