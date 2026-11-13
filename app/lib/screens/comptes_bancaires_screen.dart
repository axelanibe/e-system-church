import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Comptes bancaires de l'église (tranche T7) : banque ou Mobile Money,
/// avec titulaire et numéro de compte. Les numéros Wave, Orange et MTN
/// restent dans les paramètres de l'église. Saisie admin et trésorier.
class ComptesBancairesScreen extends StatefulWidget {
  const ComptesBancairesScreen({super.key});

  @override
  State<ComptesBancairesScreen> createState() =>
      _ComptesBancairesScreenState();
}

class _ComptesBancairesScreenState extends State<ComptesBancairesScreen> {
  late Future<List<CompteBancaire>> _future;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<List<CompteBancaire>> _charger() =>
      context.read<AppState>().api.getComptesBancaires();

  void _refresh() => setState(() => _future = _charger());

  Future<void> _editer([CompteBancaire? compte]) async {
    final banqueController = TextEditingController(text: compte?.banque);
    final titulaireController =
        TextEditingController(text: compte?.titulaire);
    final numeroController =
        TextEditingController(text: compte?.numeroCompte);
    final deviseController =
        TextEditingController(text: compte?.devise ?? 'FCFA');
    var type = compte?.type ?? 'banque';
    var actif = compte?.actif ?? true;
    final formKey = GlobalKey<FormState>();
    final enregistre = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(compte == null
              ? 'Nouveau compte'
              : 'Modifier le compte'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: banqueController,
                    decoration: const InputDecoration(
                      labelText: 'Banque *',
                      hintText: 'Ex. Banque Atlantique',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? 'Nom de la banque requis.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'banque', child: Text('Banque')),
                      DropdownMenuItem(
                          value: 'mobile_money',
                          child: Text('Mobile Money')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => type = v ?? 'banque'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: titulaireController,
                    decoration: const InputDecoration(
                      labelText: 'Titulaire',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: numeroController,
                    decoration: const InputDecoration(
                      labelText: 'Numéro de compte',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: deviseController,
                    decoration: const InputDecoration(
                      labelText: 'Devise',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (compte != null)
                    SwitchListTile(
                      title: const Text('Compte actif'),
                      value: actif,
                      onChanged: (v) => setDialogState(() => actif = v),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final api = context.read<AppState>().api;
                try {
                  if (compte == null) {
                    await api.createCompteBancaire(
                      banque: banqueController.text.trim(),
                      titulaire: titulaireController.text.trim().isEmpty
                          ? null
                          : titulaireController.text.trim(),
                      numeroCompte: numeroController.text.trim().isEmpty
                          ? null
                          : numeroController.text.trim(),
                      type: type,
                      devise: deviseController.text.trim().isEmpty
                          ? 'FCFA'
                          : deviseController.text.trim(),
                    );
                  } else {
                    await api.updateCompteBancaire(
                      compte.id,
                      banque: banqueController.text.trim(),
                      titulaire: titulaireController.text.trim().isEmpty
                          ? null
                          : titulaireController.text.trim(),
                      numeroCompte: numeroController.text.trim().isEmpty
                          ? null
                          : numeroController.text.trim(),
                      type: type,
                      devise: deviseController.text.trim().isEmpty
                          ? 'FCFA'
                          : deviseController.text.trim(),
                      actif: actif,
                    );
                  }
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (e) {
                  if (context.mounted) showApiError(context, e);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    banqueController.dispose();
    titulaireController.dispose();
    numeroController.dispose();
    deviseController.dispose();
    if (enregistre == true && mounted) {
      _refresh();
      showSuccess(context, 'Compte enregistré.');
    }
  }

  Future<void> _supprimer(CompteBancaire compte) async {
    final confirme = await confirmDelete(
      context,
      'Supprimer le compte « ${compte.banque} » ?',
    );
    if (!confirme || !mounted) return;
    try {
      await context.read<AppState>().api.deleteCompteBancaire(compte.id);
      if (mounted) {
        _refresh();
        showSuccess(context, 'Compte supprimé.');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.canReadFinances) {
      return const EmptyState(
        icon: Icons.lock_outline,
        message: 'Votre rôle ne donne pas accès aux finances de l’église.',
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes bancaires')),
      body: FutureBuilder<List<CompteBancaire>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final comptes = snapshot.data!;
          if (comptes.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_outlined,
              message: 'Aucun compte enregistré. Les comptes de la '
                  'structure s’ajouteront ici pour le rapprochement.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: comptes.length,
              itemBuilder: (context, index) {
                final compte = comptes[index];
                return Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.account_balance_outlined),
                    title: Text(compte.banque),
                    subtitle: Text(
                      [
                        compte.typeLabel,
                        if ((compte.titulaire ?? '').isNotEmpty)
                          compte.titulaire!,
                        if ((compte.numeroCompte ?? '').isNotEmpty)
                          compte.numeroCompte!,
                        compte.devise,
                        if (!compte.actif) 'Inactif',
                      ].join(' · '),
                    ),
                    trailing: state.canManageFinances
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _supprimer(compte),
                            tooltip: 'Supprimer',
                          )
                        : null,
                    onTap: state.canManageFinances
                        ? () => _editer(compte)
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: state.canManageFinances
          ? FloatingActionButton.extended(
              onPressed: () => _editer(),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau compte'),
            )
          : null,
    );
  }
}
