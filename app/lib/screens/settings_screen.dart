import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/suppression_eglise.dart';
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
  bool _suppressionEnCours = false;

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

  /// Suppression de sa propre église TEST : aperçu, puis confirmation
  /// nommant ce qui sera supprimé, puis suppression. Admin d'église
  /// seulement, église dont le nom commence par TEST seulement. Après
  /// la suppression, la session quitte l'église supprimée.
  Future<void> _supprimerEglise() async {
    final api = context.read<AppState>().api;
    setState(() => _suppressionEnCours = true);
    SuppressionEgliseApercu apercu;
    try {
      apercu = await api.getSuppressionEgliseApercu();
    } catch (e) {
      if (!mounted) return;
      setState(() => _suppressionEnCours = false);
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _suppressionEnCours = false);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette église ?'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${apercu.eglise.nom} (${apercu.eglise.code}) sera supprimée définitivement, avec tout ce qu\u2019elle contient :',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in apercu.annexes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• Annexe ${a.nom} (${a.code})',
                            style: const TextStyle(fontSize: 14)),
                      ),
                    for (final ligne in apercu.lignesComptes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $ligne',
                            style: const TextStyle(fontSize: 14)),
                      ),
                    if (apercu.utilisateursSupprimes > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            '• Comptes utilisateurs TEST supprimés : ${apercu.utilisateursSupprimes}',
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Membres, contributions, campagnes, attestations et transferts partent avec elle. Cette action est définitive.',
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
              'Supprimer définitivement',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _suppressionEnCours = true);
    try {
      await api.executerSuppressionEglise();
      if (!mounted) return;
      setState(() => _suppressionEnCours = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _suppressionEnCours = false);
      showApiError(context, e);
      return;
    }
    // L'église n'existe plus : la session la quitte.
    final partir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Église supprimée'),
        content: Text(
            '${apercu.eglise.nom} n\u2019existe plus. Vous allez être déconnecté(e).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (partir == true && mounted) {
      await context.read<AppState>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    // En démo, l'URL d'API est 'demo' et DemoAppState.setApiBaseUrl est
    // sans effet (aucun serveur) : le champ et le bouton sont désactivés.
    final isDemo = context.watch<AppState>().apiBaseUrl == 'demo';
    final state = context.watch<AppState>();
    final estEgliseTest =
        state.isAdmin && (state.church?.name.startsWith('TEST') ?? false);
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
                if (estEgliseTest) ...[
                  const SectionTitle(title: 'Supprimer cette église'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_forever_outlined,
                                color: Theme.of(context).colorScheme.error),
                            title: Text(
                              'Supprimer cette église',
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error),
                            ),
                            subtitle: const Text(
                                'Supprime définitivement votre église TEST, ses annexes et tout ce qu\u2019elles contiennent (membres, contributions, campagnes, attestations, transferts). L\u2019aperçu s\u2019affiche avant toute suppression.'),
                            trailing: _suppressionEnCours
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap:
                                _suppressionEnCours ? null : _supprimerEglise,
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
                        const Text(
                          'Changer l’URL déconnecte la session en cours : reconnectez-vous ensuite avec votre compte réel.',
                          style: TextStyle(fontSize: 14),
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
                              'Version ${AppConfig.appVersion}'),
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
