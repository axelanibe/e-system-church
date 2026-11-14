import 'dart:js_interop';

/// Sur le web, ouvre la fenêtre d'impression du navigateur.
@JS('print')
external void imprimerPage();

/// Vrai sur le web seulement.
bool get impressionWebDisponible => true;
