import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'action_sociale_screen.dart';
import 'documents_screen.dart';
import 'mandats_screen.dart';
import 'patrimoine_screen.dart';
import 'reunions_conseil_screen.dart';

/// T10 — Gouvernance (modèle projection, écran « Gouvernance ») :
/// Mandats, Nominations, Procès-verbaux et Documents, comme dans la
/// projection, plus Action sociale et Patrimoine, gardés comme acquis
/// par décision d'Axel (divergence volontaire sur E-G1). Chaque carte
/// ouvre son écran, avec retour partout (AppBar). Les écrans Réunions
/// et décisions et Certificats restent joignables ailleurs
/// (Procès-verbaux, Attestations annuelles) ; leurs fichiers sont
/// conservés.
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
    String? sousTitre,
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
        subtitle: sousTitre == null
            ? null
            : Text(
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
            ecran: const MandatsScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.how_to_reg_outlined,
            titre: 'Nominations',
            ecran: const MandatsScreen(ongletInitial: 1),
          ),
          _carte(
            context: context,
            icone: Icons.description_outlined,
            titre: 'Procès-verbaux',
            ecran: const ReunionsConseilScreen(ongletInitial: 2),
          ),
          _carte(
            context: context,
            icone: Icons.folder_outlined,
            titre: 'Documents',
            ecran: const DocumentsScreen(),
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
        ],
      ),
    );
  }
}
