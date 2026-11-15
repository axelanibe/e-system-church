import 'package:flutter/material.dart';

import '../widgets/fidele_home_sections.dart';

/// Espace membre (tranche 3, E-FI1) : l'écran « membre » de la
/// projection, ouvert depuis la carte « Espace membre » de
/// Modules. Section « Actions rapides » avec les 4 outils
/// (Ma Bible, Mes cotisations, Mon journal, Message à mon
/// église), sans Prendre rendez-vous, puis Mon Parcours,
/// chiffres réels, Prière du jour, Sujet de prière privé,
/// Mes camps, Mes attestations, devise. Toute la logique vit
/// dans [FideleHomeContenu], partagée avec l'accueil fidèle
/// (FideleHomeScreen). En aperçu admin, mêmes états vides que
/// l'accueil fidèle : pas de membre lié.
class EspaceMembreScreen extends StatelessWidget {
  const EspaceMembreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Espace membre')),
      body: const FideleHomeContenu(
        titreOutils: 'Actions rapides',
        avecRendezVous: false,
        priereAvantCamps: true,
      ),
    );
  }
}
