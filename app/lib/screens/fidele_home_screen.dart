import 'package:flutter/material.dart';

import '../widgets/fidele_home_sections.dart';

/// Accueil fidèle (tranche P1, tranche 3 E-FI1) : l'écran
/// « fidele-accueil » de la projection, onglet Accueil de la
/// coquille fidèle. Contenu seul, sans Scaffold ni barre : la
/// coquille fidèle (FideleShell) fournit l'écran et la barre du
/// bas. Section « Mes accès » avec les 5 outils, dont Prendre
/// rendez-vous, puis Mon Parcours, chiffres réels, Mes camps,
/// Mes attestations, Prière du jour, Sujet de prière privé,
/// devise. Toute la logique vit dans [FideleHomeContenu],
/// partagée avec l'écran « membre » (EspaceMembreScreen).
class FideleHomeScreen extends StatelessWidget {
  const FideleHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FideleHomeContenu(
      titreOutils: 'Mes accès',
      avecRendezVous: true,
      priereAvantCamps: false,
    );
  }
}
