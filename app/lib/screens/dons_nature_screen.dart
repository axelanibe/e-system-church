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

/// Dons en nature (US5) : matériel, nourriture ou temps. Un don en nature
/// n'entre jamais dans les totaux financiers ni dans le solde : il vit
/// dans sa propre table, séparée des contributions en argent.
class DonsNatureScreen extends StatefulWidget {
  const DonsNatureScreen({super.key});

  @override
  State<DonsNatureScreen> createState() => _DonsNatureScreenState();
}

class _DonsNatureScreenState extends State<DonsNatureScreen> {
  late Future<List<DonNature>> _future;
  Map<String, String> _nomsMembres = const {};

  @override
  void initState() {
    super.initState();
    _future = _load();
    _chargerNoms();
  }

  Future<List<DonNature>> _load() =>
      context.read<AppState>().api.getDonsNature();

  Future<void> _chargerNoms() async {
    final page = await context.read<AppState>().api.getMembers();
    if (mounted) {
      setState(() => _nomsMembres = {
            for (final m in page.membres) m.id: m.fullName,
          });
    }
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _creer() async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final api = context.read<AppState>().api;
    final descriptionController = TextEditingController();
    final quantiteController = TextEditingController(text: '1');
    final uniteController = TextEditingController();
    final heuresController = TextEditingController();
    final dateController = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
    var typeDon = 'materiel';
    var anonyme = false;
    String? membreId;
    final membres = await api.getMembers();
    final liste = membres.membres;
    if (liste.isNotEmpty) membreId = liste.first.id;
    if (!mounted) return;
    await showCreateDialog(
      context: context,
      title: t.nouveauDonNature,
      saveLabel: t.enregistrer,
      fields: [
        dialogTextField(
            controller: descriptionController, label: '${t.description} *'),
        StatefulBuilder(
          builder: (context, setDialogState) =>
              DropdownButtonFormField<String>(
            initialValue: typeDon,
            decoration: InputDecoration(labelText: t.typeDon),
            items: [
              DropdownMenuItem(value: 'materiel', child: Text(t.materiel)),
              DropdownMenuItem(value: 'nourriture', child: Text(t.nourriture)),
              DropdownMenuItem(value: 'temps', child: Text(t.temps)),
            ],
            onChanged: (v) => setDialogState(() => typeDon = v ?? 'materiel'),
          ),
        ),
        dialogTextField(
          controller: quantiteController,
          label: t.quantite,
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: uniteController, label: 'Unité'),
        dialogTextField(
          controller: heuresController,
          label: t.heures,
          keyboardType: TextInputType.number,
        ),
        dialogDateField(
            context: context, controller: dateController, label: t.dateVenue),
        StatefulBuilder(
          builder: (context, setDialogState) => Column(
            children: [
              SwitchListTile(
                title: Text(t.anonyme),
                value: anonyme,
                onChanged: (v) => setDialogState(() => anonyme = v),
              ),
              if (!anonyme)
                DropdownButtonFormField<String>(
                  initialValue: membreId,
                  decoration:
                      const InputDecoration(labelText: 'Membre donateur'),
                  items: liste
                      .map((m) => DropdownMenuItem(
                          value: m.id, child: Text(m.fullName)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => membreId = v),
                ),
            ],
          ),
        ),
      ],
      isValid: () => descriptionController.text.trim().length >= 2,
      onSave: () async {
        await api.createDonNature(
          memberId: anonyme ? null : membreId,
          description: descriptionController.text.trim(),
          quantite: int.tryParse(quantiteController.text) ?? 1,
          unite: uniteController.text.isEmpty ? null : uniteController.text,
          typeDon: typeDon,
          heures: double.tryParse(heuresController.text),
          dateDon: dateController.text,
          anonyme: anonyme,
        );
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t.enregistre)));
        }
      },
    );
  }

  String _libelleType(DonNature d, T12Strings t) => switch (d.typeDon) {
        'nourriture' => t.nourriture,
        'temps' => t.temps,
        _ => t.materiel,
      };

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(title: Text(t.donsNature)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creer,
        icon: const Icon(Icons.add),
        label: Text(t.nouveauDonNature),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              t.donHorsFinances,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<DonNature>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoading();
                }
                if (snapshot.hasError) {
                  return AppError(
                      message: t.erreurChargement, onRetry: _refresh);
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return EmptyState(
                      icon: Icons.card_giftcard_outlined, message: t.vide);
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final d = items[i];
                      final nom = d.anonyme
                          ? t.anonyme
                          : (_nomsMembres[d.memberId] ?? t.anonyme);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.card_giftcard_outlined,
                              color: AppTheme.or),
                          title: Text(d.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '$nom · ${_libelleType(d, t)} · ${d.quantite}${d.unite == null ? '' : ' ${d.unite}'}${d.heures == null ? '' : ' · ${d.heures} ${t.heures.toLowerCase()}'} · ${formatDateSeule(DateTime.tryParse(d.dateDon))}',
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
