import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/app_state.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/common_widgets.dart';
import 'mon_eglise_screen.dart';
import 'parametres_screen.dart';

/// Réglages : URL de l'API réelle, paramètres de l'église, informations
/// de version et déconnexion. L'application n'affiche que les données
/// réelles du serveur : aucun mode démo.
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
    // En démo, l'URL d'API est 'demo' et DemoAppState.setApiBaseUrl est
    // sans effet (aucun serveur) : le champ et le bouton sont désactivés.
    final isDemo = context.watch<AppState>().apiBaseUrl == 'demo';
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
                const SectionTitle(title: 'Église'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.tune_outlined),
                          title: const Text('Paramètres de l’église'),
                          subtitle: const Text(
                              'Coordonnées, paiements mobiles, devise, fuseau horaire, rôles et journal d’audit.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ParametresScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.church_outlined),
                          title: const Text('Mon église'),
                          subtitle: const Text(
                              'Logo, présentation, horaires des cultes, pasteur et antennes.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MonEgliseScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Compte'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Changer mon mot de passe'),
                          subtitle: const Text(
                              'Vérifie l’ancien mot de passe. Les autres sessions sont déconnectées.'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showChangePasswordDialog(context),
                        ),
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
                          enabled: !isDemo,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'URL de l’API',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: (isDemo || _saving) ? null : _saveUrl,
                          child: const Text('Enregistrer l’URL'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isDemo
                              ? 'Sans effet en démo : la démo n’utilise pas de serveur, les données sont fictives et locales.'
                              : 'Changer l’URL déconnecte la session en cours : reconnectez-vous ensuite avec votre compte réel.',
                          style: const TextStyle(fontSize: 14),
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
