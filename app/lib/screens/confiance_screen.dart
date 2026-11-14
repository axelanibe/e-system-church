import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'audit_screen.dart';
import 'deux_fa_screen.dart';
import 'file_hors_ligne_screen.dart';
import 'notifications_screen.dart';
import 'sauvegarde_screen.dart';

/// T11 — Confiance (modèle projection) : Sauvegardes, File hors ligne,
/// Double authentification, Journal d'audit et Notifications. Chaque
/// carte ouvre son écran, avec retour partout (AppBar).
class ConfianceScreen extends StatelessWidget {
  const ConfianceScreen({super.key});

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
      appBar: AppBar(title: const Text('Confiance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _carte(
            context: context,
            icone: Icons.backup_outlined,
            titre: 'Sauvegardes',
            sousTitre: 'Sauvegarde chiffrée de l’église, restauration testée.',
            ecran: const SauvegardeScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.cloud_off_outlined,
            titre: 'File hors ligne',
            sousTitre: 'Pointages et saisies en attente, rejoués à la reconnexion.',
            ecran: const FileHorsLigneScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.phonelink_lock_outlined,
            titre: 'Double authentification',
            sousTitre: 'Code à 6 chiffres pour Pasteur, Trésorier et Admin.',
            ecran: const DeuxFaScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.fact_check_outlined,
            titre: 'Journal d’audit',
            sousTitre: 'Historique immuable, chaîne vérifiée, lectures sensibles.',
            ecran: const AuditScreen(),
          ),
          _carte(
            context: context,
            icone: Icons.notifications_outlined,
            titre: 'Notifications',
            sousTitre: 'Push et SMS, boîte d’envoi et paramètres.',
            ecran: const NotificationsScreen(),
          ),
        ],
      ),
    );
  }
}
