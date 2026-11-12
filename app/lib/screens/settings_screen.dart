import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/nettoyage_test.dart';
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
  bool _nettoyageEnCours = false;

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

  /// Nettoyage des données TEST : aperçu, puis confirmation nommant le
  /// nombre d'éléments, puis suppression. Admin d'église seulement.
  Future<void> _nettoyerTest() async {
    final api = context.read<AppState>().api;
    setState(() => _nettoyageEnCours = true);
    NettoyageTestApercu apercu;
    try {
      apercu = await api.getNettoyageTestApercu();
    } catch (e) {
      if (!mounted) return;
      setState(() => _nettoyageEnCours = false);
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _nettoyageEnCours = false);
    if (apercu.total == 0) {
      showSuccess(context, 'Aucune donnée TEST à supprimer.');
      return;
    }
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les données TEST ?'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${apercu.total} éléments marqués TEST seront supprimés définitivement :',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in apercu.elements)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• ${e.label}',
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Seules les données marquées TEST de votre église et de ses annexes sont concernées. Aucune vraie donnée n’est touchée.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Supprimer ${apercu.total} éléments',
              style:
                  TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _nettoyageEnCours = true);
    try {
      final resultat = await api.executerNettoyageTest();
      if (!mounted) return;
      setState(() => _nettoyageEnCours = false);
      showSuccess(context,
          '${resultat.total} éléments TEST supprimés.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _nettoyageEnCours = false);
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // En démo, l'URL d'API est 'demo' et DemoAppState.setApiBaseUrl est
    // sans effet (aucun serveur) : le champ et le bouton sont désactivés.
    final isDemo = context.watch<AppState>().apiBaseUrl == 'demo';
    final isAdmin = context.watch<AppState>().isAdmin;
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
                if (isAdmin) ...[
                  const SectionTitle(title: 'Données TEST'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.cleaning_services_outlined),
                            title: const Text('Nettoyer les données TEST'),
                            subtitle: const Text(
                                'Supprime les données marquées TEST de votre église et de ses annexes (membre, contributions, campagne, attestation, transfert, sous-église). L’aperçu s’affiche avant toute suppression.'),
                            trailing: _nettoyageEnCours
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: _nettoyageEnCours ? null : _nettoyerTest,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
