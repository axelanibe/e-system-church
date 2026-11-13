import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/annexe.dart';
import '../models/suppression_eglise.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'annexes_screen.dart';

/// Détail d'une annexe, vu par sa mère : chiffres, compteurs et état
/// des modules. Que des agrégats, jamais de données nominatives.
class AnnexeDetailScreen extends StatefulWidget {
  final String annexeId;

  const AnnexeDetailScreen({super.key, required this.annexeId});

  @override
  State<AnnexeDetailScreen> createState() => _AnnexeDetailScreenState();
}

class _AnnexeDetailScreenState extends State<AnnexeDetailScreen> {
  late Future _future;
  bool _actionEnCours = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getAnnexeDetail(widget.annexeId);
  }

  void _refresh() {
    setState(() => _future =
        context.read<AppState>().api.getAnnexeDetail(widget.annexeId));
  }

  /// Modification d'une annexe par sa mère : nom, ville, téléphone,
  /// e-mail, adresse. Les champs vides ne sont pas modifiés. Même route
  /// PATCH que le profil de sa propre église.
  Future<void> _modifierAnnexe(AnnexeDetail d) async {
    final nomController = TextEditingController(text: d.name);
    final villeController = TextEditingController(text: d.city ?? '');
    final telephoneController = TextEditingController();
    final emailController = TextEditingController();
    final adresseController = TextEditingController();
    String? valeur(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    await showCreateDialog(
      context: context,
      title: 'Modifier l\u2019annexe',
      saveLabel: 'Enregistrer',
      fields: [
        dialogTextField(
          controller: nomController,
          label: 'Nom de l\u2019église',
        ),
        const Text(
          'Le code de l\u2019annexe ne change jamais.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        dialogTextField(
          controller: villeController,
          label: 'Ville',
        ),
        dialogTextField(
          controller: telephoneController,
          label: 'Téléphone',
          hintText: 'Laisser vide pour ne pas modifier',
          keyboardType: TextInputType.phone,
        ),
        dialogTextField(
          controller: emailController,
          label: 'E-mail',
          hintText: 'Laisser vide pour ne pas modifier',
          keyboardType: TextInputType.emailAddress,
        ),
        dialogTextField(
          controller: adresseController,
          label: 'Adresse',
          hintText: 'Laisser vide pour ne pas modifier',
        ),
      ],
      isValid: () => nomController.text.trim().length >= 2,
      onSave: () async {
        try {
          await context.read<AppState>().api.updateProfil(
                churchId: widget.annexeId,
                name: nomController.text.trim(),
                city: valeur(villeController),
                phone: valeur(telephoneController),
                email: valeur(emailController),
                address: valeur(adresseController),
              );
          if (mounted) showSuccess(context, 'Annexe mise à jour.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  /// Suppression d'une annexe par sa mère : aperçu, puis confirmation
  /// nommant ce qui sera supprimé. Une vraie annexe peut contenir de
  /// vrais membres : l'aperçu les montre. Retour à la liste ensuite.
  Future<void> _supprimerAnnexe(AnnexeDetail d) async {
    final api = context.read<AppState>().api;
    setState(() => _actionEnCours = true);
    SuppressionEgliseApercu apercu;
    try {
      apercu = await api.getSuppressionEgliseApercu(egliseId: widget.annexeId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionEnCours = false);
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _actionEnCours = false);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette annexe ?'),
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
                'Cette annexe peut contenir de vrais membres : vérifiez les chiffres ci-dessus. Cette action est définitive.',
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
    setState(() => _actionEnCours = true);
    try {
      await api.executerSuppressionEglise(egliseId: widget.annexeId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionEnCours = false);
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détail de l’annexe')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = context
                  .read<AppState>()
                  .api
                  .getAnnexeDetail(widget.annexeId)),
            );
          }
          final d = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = context
                  .read<AppState>()
                  .api
                  .getAnnexeDetail(widget.annexeId));
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('${d.code} · ${d.city ?? ''}'),
                        const SizedBox(height: 4),
                        Text(
                          'Modules : ${d.modules.length}, tous actifs',
                        ),
                      ],
                    ),
                  ),
                ),
                if (context.watch<AppState>().isAdmin) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed:
                        _actionEnCours ? null : () => _modifierAnnexe(d),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                ],
                const SectionTitle(title: 'Chiffres'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    StatMini(
                      label: 'Membres actifs',
                      value: '${d.membresActifs}',
                      icon: Icons.people_outline,
                    ),
                    StatMini(
                      label: 'Entrées confirmées',
                      value: formatFcfa(d.totalFcfa),
                      icon: Icons.trending_up,
                      color: AppTheme.bleuNuit,
                    ),
                    StatMini(
                      label: 'Dépenses confirmées',
                      value: formatFcfa(d.depensesFcfa),
                      icon: Icons.trending_down,
                      color: AppTheme.rougeErreur,
                    ),
                    StatMini(
                      label: 'Contributions',
                      value: '${d.nombreContributions}',
                      icon: Icons.volunteer_activism_outlined,
                    ),
                    StatMini(
                      label: 'Cultes',
                      value: '${d.cultes}',
                      icon: Icons.event_outlined,
                    ),
                    StatMini(
                      label: 'Présences',
                      value: '${d.presences}',
                      icon: Icons.how_to_reg_outlined,
                    ),
                    StatMini(
                      label: 'Annonces',
                      value: '${d.annonces}',
                      icon: Icons.campaign_outlined,
                    ),
                  ],
                ),
                const SectionTitle(title: 'Modules de l’annexe'),
                if (d.modules.isEmpty)
                  const EmptyState(
                    icon: Icons.extension_outlined,
                    message: 'Aucun module.',
                  )
                else
                  ...d.modules.map((m) => ListTile(
                        leading: const Icon(Icons.check_circle_outlined,
                            color: AppTheme.bleuNuit),
                        title: Text(m.label),
                        subtitle: m.noyau ? const Text('Noyau') : null,
                      )),
                if (context.watch<AppState>().isAdmin) ...[
                  const SectionTitle(title: 'Supprimer cette annexe'),
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.delete_forever_outlined,
                          color: Theme.of(context).colorScheme.error),
                      title: Text(
                        'Supprimer cette annexe',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                      subtitle: const Text(
                          'Supprime définitivement l\u2019annexe et tout ce qu\u2019elle contient (membres, contributions, campagnes, attestations, transferts). L\u2019aperçu s\u2019affiche avant toute suppression.'),
                      trailing: _actionEnCours
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _actionEnCours
                          ? null
                          : () => _supprimerAnnexe(d),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
