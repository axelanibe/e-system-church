import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/mock_data.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Réglages : bascule **mode démo / mode API réelle**, URL de l'API,
/// informations de version et déconnexion.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
        text: context.read<AppState>().apiBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      showApiError(
          context, 'URL invalide (doit commencer par http:// ou https://).');
      return;
    }
    setState(() => _saving = true);
    await context.read<AppState>().setApiBaseUrl(url);
    if (!mounted) return;
    setState(() => _saving = false);
    showSuccess(context,
        'URL de l’API enregistrée. Vous avez été déconnecté(e) : reconnectez-vous.');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(title: 'Mode de fonctionnement'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: const Text('Mode démo'),
                          subtitle: const Text(
                              'Données fictives « Grâce Divine » en mémoire. Aucun serveur requis — idéal pour tester l’application.'),
                          value: state.demoMode,
                          onChanged: (value) async {
                            await context
                                .read<AppState>()
                                .setDemoMode(value);
                            if (context.mounted) {
                              showSuccess(
                                context,
                                value
                                    ? 'Mode démo activé. Reconnectez-vous avec un compte de démonstration.'
                                    : 'Mode API réelle activé. Reconnectez-vous.',
                              );
                            }
                          },
                        ),
                        if (state.demoMode) ...[
                          const Divider(),
                          Text('Comptes de démonstration (mot de passe : demo1234)',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          for (final account in demoAccounts)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.person_outline, size: 20),
                              title: Text(account['email']!),
                              subtitle: Text(account['label']!),
                              dense: true,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'API réelle'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _urlController,
                          enabled: !state.demoMode,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'URL de l’API',
                            hintText: 'Ex. http://localhost:3000',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: (state.demoMode || _saving)
                              ? null
                              : _saveUrl,
                          child: const Text('Enregistrer l’URL'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'L’URL s’applique au mode API réelle. Changer de mode ou d’URL déconnecte la session en cours.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Application'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.info_outline),
                          title: Text(AppConfig.appName),
                          subtitle: Text(
                              'Version ${AppConfig.appVersion} — MVP'),
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.logout),
                          title: const Text('Se déconnecter'),
                          onTap: () async {
                            await context.read<AppState>().logout();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
