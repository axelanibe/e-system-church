import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Fiche visiteur (US6) : nom et date de venue seuls obligatoires.
/// Un visiteur n'apparaît ni dans les membres ni dans les finances tant
/// qu'il n'est pas devenu membre. Seuls les responsables désignés par
/// l'admin voient les fiches (règle serveur : admin, trésorier,
/// responsable du culte).
class VisiteursScreen extends StatefulWidget {
  const VisiteursScreen({super.key});

  @override
  State<VisiteursScreen> createState() => _VisiteursScreenState();
}

class _VisiteursScreenState extends State<VisiteursScreen> {
  late Future<List<Visiteur>> _future;
  String? _filtreStatut;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Visiteur>> _load() => context
      .read<AppState>()
      .api
      .getVisiteurs(statut: _filtreStatut);

  void _refresh() => setState(() => _future = _load());

  Future<void> _creer() async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final api = context.read<AppState>().api;
    final nomController = TextEditingController();
    final telephoneController = TextEditingController();
    final emailController = TextEditingController();
    final moyenController = TextEditingController();
    final dateController = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
    await showCreateDialog(
      context: context,
      title: t.nouveauVisiteur,
      saveLabel: t.enregistrer,
      fields: [
        dialogTextField(controller: nomController, label: '${t.nom} *'),
        dialogTextField(
            controller: telephoneController, label: t.telephone),
        dialogTextField(
            controller: emailController,
            label: 'E-mail',
            keyboardType: TextInputType.emailAddress),
        dialogTextField(
            controller: moyenController, label: 'Comment nous a connus'),
        dialogDateField(
            context: context, controller: dateController, label: t.dateVenue),
      ],
      isValid: () => nomController.text.trim().length >= 2,
      onSave: () async {
        await api.createVisiteur(
          nom: nomController.text.trim(),
          dateVenue: dateController.text,
          telephone: telephoneController.text.isEmpty
              ? null
              : telephoneController.text,
          email:
              emailController.text.isEmpty ? null : emailController.text,
          moyenContact: moyenController.text.isEmpty
              ? null
              : moyenController.text,
        );
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t.enregistre)));
        }
      },
    );
  }

  Future<void> _devenirMembre(Visiteur v) async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final api = context.read<AppState>().api;
    final page = await api.getMembers();
    final membres = page.membres;
    if (!mounted || membres.isEmpty) return;
    var membreId = membres.first.id;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.devenirMembre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(v.nom),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setDialogState) =>
                  DropdownButtonFormField<String>(
                initialValue: membreId,
                decoration: InputDecoration(labelText: t.choisirMembre),
                items: membres
                    .map((m) => DropdownMenuItem(
                        value: m.id, child: Text(m.fullName)))
                    .toList(),
                onChanged: (v) => setDialogState(() => membreId = v!),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.confirmer),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await api.devenirMembre(v.id, membreId);
    if (mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.visiteurDevenuMembre)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.visiteurs),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() {
              _filtreStatut = v;
              _refresh();
            }),
            itemBuilder: (context) => [
              PopupMenuItem(value: null, child: Text(t.visiteurs)),
              const PopupMenuItem(value: 'nouveau', child: Text('Nouveau')),
              const PopupMenuItem(
                  value: 'recontacte', child: Text('Recontacté')),
              PopupMenuItem(
                  value: 'devenu_membre', child: Text(t.devenirMembre)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creer,
        icon: const Icon(Icons.add),
        label: Text(t.nouveauVisiteur),
      ),
      body: FutureBuilder<List<Visiteur>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(message: t.erreurChargement, onRetry: _refresh);
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return EmptyState(
                icon: Icons.person_add_alt_1_outlined, message: t.vide);
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final v = items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.person_add_alt_1_outlined,
                        color: AppTheme.or),
                    title: Text(v.nom,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${formatDateSeule(DateTime.tryParse(v.dateVenue))}${v.telephone == null ? '' : ' · ${v.telephone}'}${v.moyenContact == null ? '' : ' · ${v.moyenContact}'}',
                    ),
                    trailing: v.statut == 'devenu_membre'
                        ? StatusChip(
                            label: t.devenirMembre,
                            color: AppTheme.violetProfond)
                        : TextButton(
                            onPressed: () => _devenirMembre(v),
                            child: Text(t.devenirMembre),
                          ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
