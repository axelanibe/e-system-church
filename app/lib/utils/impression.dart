// Impression des cartes sur le web : `window.print()` du navigateur.
// Import conditionnel : sur mobile, l'impression n'existe pas et
// l'appel ne fait rien (`impressionWebDisponible` vaut faux).
export 'impression_stub.dart'
    if (dart.library.js_interop) 'impression_web.dart';
