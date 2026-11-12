import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fidele.dart';
import '../state/app_state.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/common_widgets.dart';

/// Paramètres du fidèle (tranche P1) : Mon profil, Notifications,
/// Langue, Aide. Rien d'administratif ici : les paramètres de
/// l'église restent dans l'écran admin (ParametresScreen).
class ParametresFideleScreen extends StatefulWidget {
  const ParametresFideleScreen({super.key});

  @override
  State<ParametresFideleScreen> createState() =>
      _ParametresFideleScreenState();
}

class _ParametresFideleScreenState extends State<ParametresFideleScreen> {
  late Future<FideleProfil> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getMoi();
  }

  Future<void> _changerMotDePasse() async {
    await showChangePasswordDialog(context);
  }

  void _aide(FideleProfil profil) {
    final eglise = profil.church;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aide'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Besoin d’aide ? Votre église peut vous aider : carte de '
              'membre, cotisations, cultes, messagerie.',
            ),
            const SizedBox(height: 12),
            Text('Votre église : ${eglise.name}'),
            if (eglise.city != null && eglise.city!.isNotEmpty)
              Text('Ville : ${eglise.city}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: FutureBuilder<FideleProfil>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: () => setState(
                () => _future = context.read<AppState>().api.getMoi(),
              ),
            );
          }
          final profil = snapshot.data!;
          final eglise = profil.church;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionTitle(title: 'Mon profil'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(profil.user.fullName),
                      subtitle: Text(profil.user.email),
                    ),
                    if (profil.user.phone != null)
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(profil.user.phone!),
                      ),
                    if (profil.matricule != null)
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text('Matricule : ${profil.matricule}'),
                        subtitle: const Text('Votre carte de membre'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.church_outlined),
                      title: Text(eglise.name),
                      subtitle: eglise.city == null || eglise.city!.isEmpty
                          ? null
                          : Text(eglise.city!),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Changer mon mot de passe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changerMotDePasse,
                    ),
                  ],
                ),
              ),
              const SectionTitle(title: 'Notifications'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('Notifications'),
                  subtitle: const Text(
                    'Aucun réglage de notification pour l’instant.',
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Aucun réglage de notification pour l’instant.',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SectionTitle(title: 'Langue'),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.language_outlined),
                  title: Text('Langue'),
                  subtitle: Text('Français'),
                ),
              ),
              const SectionTitle(title: 'Aide'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Aide'),
                  subtitle: const Text(
                    'Comment utiliser votre espace fidèle.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _aide(profil),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
