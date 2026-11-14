import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'action_sociale_screen.dart';
import 'attestations_screen.dart';
import 'documents_screen.dart';
import 'mandats_screen.dart';
import 'patrimoine_screen.dart';
import 'reunions_conseil_screen.dart';

/// T10 — Gouvernance (modèle projection, écran « Gouvernance ») :
/// Mandats, Nominations, Procès-verbaux et Documents, puis Réunions et
/// décisions, Certificats, Action sociale et Patrimoine. Chaque carte
/// ouvre son écran, avec retour partout (AppBar).
class GouvernanceScreen extends StatelessWidget {
  const GouvernanceScreen({super.key});

  void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  Widget _carte({
    required BuildContext context,
    required IconData icone,
    required String titre,
    required String sousTitre,
    required Widget ecran,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.orClair,
          child: Icon(icone, color: AppTheme.orFonce),
        ),
        title: Text(
          titre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          sousTitre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _ouvrir(context, ecran),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gouvernance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _carte(
            context: context,
            icone: Icons.verified_outlined,
            titre: 'Mandats',
            sousTitre: 'Mandats des responsables, avec leurs dates.',
            ecran: const MandatsScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.how_to_reg_outlined,
            titre: 'Nominations',
            sousTitre: 'Chaque nomination garde sa décision et sa date d’effet.',
            ecran: const MandatsScreen(ongletInitial: 1),
          ),
          _carte(
            context: context,
            icone: Icons.event_available_outlined,
            titre: 'Réunions et décisions',
            sousTitre: 'Réunions du conseil, décisions et procès-verbaux.',
            ecran: const ReunionsConseilScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.description_outlined,
            titre: 'Procès-verbaux',
            sousTitre: 'Les réunions du bureau produisent leur procès-verbal.',
            ecran: const ReunionsConseilScreen(ongletInitial: 2),
          ),
          _carte(
            context: context,
            icone: Icons.folder_outlined,
            titre: 'Documents',
            sousTitre: 'Statuts, règlements, modèles et courriers.',
            ecran: const DocumentsScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.workspace_premium_outlined,
            titre: 'Certificats',
            sousTitre: 'Baptême, mariage et membre, en PDF.',
            ecran: const AttestationsScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.volunteer_activism_outlined,
            titre: 'Action sociale',
            sousTitre: 'Bénéficiaires et suivi des aides.',
            ecran: const ActionSocialeScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.domain_outlined,
            titre: 'Patrimoine',
            sousTitre: 'Bâtiments, valeur, assurance et inventaire.',
            ecran: const PatrimoineScreen(),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
