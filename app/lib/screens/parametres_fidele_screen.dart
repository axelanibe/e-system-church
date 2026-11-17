import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fidele.dart';
import '../state/app_state.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/common_widgets.dart';
import 'consultations_screen.dart';
import 'langue_donnees_screen.dart';

/// Paramètres du fidèle (tranche P1) : Mon profil, Notifications,
/// Langue, Aide. Rien d'administratif ici : les paramètres de
/// l'église restent dans l'écran admin (SettingsScreen, Réglages et
/// confiance).
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
        title: const Text('Aide', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      title: Text(profil.user.fullName, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(profil.user.email, style: const TextStyle(fontSize: 11.5)),
                    ),
                    if (profil.user.phone != null)
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(profil.user.phone!, style: const TextStyle(fontSize: 13.5)),
                      ),
                    if (profil.matricule != null)
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text('Matricule : ${profil.matricule}', style: const TextStyle(fontSize: 13.5)),
                      ),
                    ListTile(
                      leading: const Icon(Icons.church_outlined),
                      title: Text(eglise.name, style: const TextStyle(fontSize: 13.5)),
                      subtitle: eglise.city == null || eglise.city!.isEmpty
                          ? null
                          : Text(eglise.city!, style: const TextStyle(fontSize: 11.5)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Changer mon mot de passe', style: TextStyle(fontSize: 13.5)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changerMotDePasse,
                    ),
                    ListTile(
                      leading: const Icon(Icons.visibility_outlined),
                      title: const Text('Qui a consulté ma fiche', style: TextStyle(fontSize: 13.5)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ConsultationsScreen(
                                vueMembre: true),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SectionTitle(title: 'Notifications'),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.notifications_outlined),
                  title: Text('Notifications', style: TextStyle(fontSize: 13.5)),
                ),
              ),
              const SectionTitle(title: 'Langue'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.language_outlined),
                      title: const Text('Langue de l’application', style: TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        context.watch<PreferencesLocales>().estAnglais
                            ? 'Anglais'
                            : 'Français',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LangueDonneesScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.text_fields_outlined),
                      title: const Text('Taille du texte', style: TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        T12Strings(context.watch<PreferencesLocales>().estAnglais)
                            .nomTailleTexte(context.watch<PreferencesLocales>().tailleTexte),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LangueDonneesScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SectionTitle(title: 'Aide'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Aide', style: TextStyle(fontSize: 13.5)),
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
