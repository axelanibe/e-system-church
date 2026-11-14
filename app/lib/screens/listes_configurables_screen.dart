import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/parametres.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Listes configurables (US12, US13) et seuils (US14).
///
/// Rôles (avec leur niveau de droits), catégories de dépense et de
/// recette, statuts de membre, départements. Un libellé archivé ne
/// supprime rien : les enregistrements gardent leur valeur, il n'est
/// plus proposé. Les statuts de membre par défaut (membre,
/// sympathisant, nouveau converti, en formation, suspendu, parti,
/// ancien) s'archivent de la même façon.
/// La dîme suggérée est un repère, jamais imposée : vide = désactivée.
class ListesConfigurablesScreen extends StatefulWidget {
  const ListesConfigurablesScreen({super.key});

  @override
  State<ListesConfigurablesScreen> createState() =>
      _ListesConfigurablesScreenState();
}

const _types = [
  'role',
  'categorie_depense',
  'categorie_recette',
  'statut_membre',
  'departement',
];

class _ListesConfigurablesScreenState
    extends State<ListesConfigurablesScreen> {
  String _type = 'role';
  late Future<List<ListeConfigurable>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ListeConfigurable>> _load() => context
      .read<AppState>()
      .api
      .getListesConfigurables(type: _type);

  void _refresh() => setState(() => _future = _load());

  String _titreType(String type, T12Strings t) => switch (type) {
        'categorie_depense' => t.categoriesDepense,
        'categorie_recette' => t.categoriesRecette,
        'statut_membre' => t.statutsMembre,
        'departement' => t.departements,
        _ => t.roles,
      };

  Future<void> _creer() async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final api = context.read<AppState>().api;
    final libelleController = TextEditingController();
    var niveau = 'membre';
    await showCreateDialog(
      context: context,
      title: t.ajouterLibelle,
      saveLabel: t.enregistrer,
      fields: [
        dialogTextField(
            controller: libelleController, label: '${t.libelle} *'),
        if (_type == 'role')
          StatefulBuilder(
            builder: (context, setDialogState) =>
                DropdownButtonFormField<String>(
              initialValue: niveau,
              decoration: InputDecoration(labelText: t.niveau),
              items: const [
                DropdownMenuItem(
                    value: 'admin_eglise', child: Text('Administrateur')),
                DropdownMenuItem(value: 'tresorier', child: Text('Trésorier')),
                DropdownMenuItem(
                    value: 'responsable_culte',
                    child: Text('Responsable du culte')),
                DropdownMenuItem(value: 'membre', child: Text('Membre')),
              ],
              onChanged: (v) => setDialogState(() => niveau = v ?? 'membre'),
            ),
          ),
      ],
      isValid: () => libelleController.text.trim().length >= 2,
      onSave: () async {
        await api.createListeConfigurable(
          type: _type,
          libelle: libelleController.text.trim(),
          niveau: _type == 'role' ? niveau : null,
        );
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t.enregistre)));
        }
      },
    );
  }

  Future<void> _basculerArchive(ListeConfigurable item) async {
    await context
        .read<AppState>()
        .api
        .updateListeConfigurable(item.id, archive: !item.archive);
    _refresh();
  }

  Future<void> _supprimer(ListeConfigurable item) async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.libelle),
        content: Text(t.confirmer),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.confirmer),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    await context.read<AppState>().api.deleteListeConfigurable(item.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return DefaultTabController(
      length: _types.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.listesConfigurables),
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) {
              if (i < _types.length) {
                setState(() {
                  _type = _types[i];
                  _refresh();
                });
              }
            },
            tabs: [
              for (final type in _types) Tab(text: _titreType(type, t)),
              Tab(text: t.seuilsEtDime),
            ],
          ),
        ),
        floatingActionButton: null,
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final _ in _types) _ListeTab(
              future: _future,
              onRefresh: _refresh,
              onCreer: _creer,
              onBasculerArchive: _basculerArchive,
              onSupprimer: _supprimer,
            ),
            const _SeuilsTab(),
          ],
        ),
      ),
    );
  }
}

class _ListeTab extends StatelessWidget {
  final Future<List<ListeConfigurable>> future;
  final VoidCallback onRefresh;
  final VoidCallback onCreer;
  final void Function(ListeConfigurable) onBasculerArchive;
  final void Function(ListeConfigurable) onSupprimer;

  const _ListeTab({
    required this.future,
    required this.onRefresh,
    required this.onCreer,
    required this.onBasculerArchive,
    required this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onCreer,
              icon: const Icon(Icons.add),
              label: Text(t.ajouterLibelle),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ListeConfigurable>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoading();
              }
              if (snapshot.hasError) {
                return AppError(
                    message: t.erreurChargement, onRetry: onRefresh);
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return EmptyState(
                    icon: Icons.list_outlined, message: t.vide);
              }
              return RefreshIndicator(
                onRefresh: () async => onRefresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.label_outline,
                            color: AppTheme.or),
                        title: Text(item.libelle,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: item.niveau == null
                            ? null
                            : Text(item.niveau!),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.archive)
                              StatusChip(
                                  label: t.archive,
                                  color: AppTheme.orAttention),
                            IconButton(
                              icon: Icon(item.archive
                                  ? Icons.unarchive_outlined
                                  : Icons.archive_outlined),
                              tooltip: item.archive
                                  ? t.desarchiver
                                  : t.archiver,
                              onPressed: () => onBasculerArchive(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => onSupprimer(item),
                            ),
                          ],
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
    );
  }
}

/// Seuils d'alerte, dîme suggérée et transparence (US8, US11, US14).
class _SeuilsTab extends StatefulWidget {
  const _SeuilsTab();

  @override
  State<_SeuilsTab> createState() => _SeuilsTabState();
}

class _SeuilsTabState extends State<_SeuilsTab> {
  late Future<EgliseParametres> _future;
  final _dimeController = TextEditingController();
  final _inactiviteController = TextEditingController();
  final _baisseController = TextEditingController();
  bool _transparence = false;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getParametres();
  }

  @override
  void dispose() {
    _dimeController.dispose();
    _inactiviteController.dispose();
    _baisseController.dispose();
    super.dispose();
  }

  void _remplir(EgliseParametres p) {
    if (_charge) return;
    _charge = true;
    _dimeController.text =
        p.montantDimeSuggere == null ? '' : '${p.montantDimeSuggere}';
    _inactiviteController.text = '${p.seuilInactiviteSemaines}';
    _baisseController.text = '${p.seuilBaisseContributionsPct}';
    _transparence = p.transparenceVisibleMembres;
  }

  Future<void> _enregistrer() async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final dimeTexte = _dimeController.text.trim();
    final inactivite = int.tryParse(_inactiviteController.text) ?? 4;
    final baisse = int.tryParse(_baisseController.text) ?? 30;
    await context.read<AppState>().api.saveParametres(
          montantDimeSuggere:
              dimeTexte.isEmpty ? null : int.tryParse(dimeTexte),
          effacerDimeSuggere: dimeTexte.isEmpty,
          transparenceVisibleMembres: _transparence,
          seuilInactiviteSemaines: inactivite,
          seuilBaisseContributionsPct: baisse,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.enregistre)));
  }

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return FutureBuilder<EgliseParametres>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError || snapshot.data == null) {
          return AppError(
              message: t.erreurChargement,
              onRetry: () => setState(
                  () => _future = context.read<AppState>().api.getParametres()));
        }
        _remplir(snapshot.data!);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _dimeController,
              decoration: InputDecoration(
                labelText: t.dimeSuggeree,
                helperText: t.dimeDesactivee,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(t.transparenceMembres),
              value: _transparence,
              onChanged: (v) => setState(() => _transparence = v),
            ),
            TextField(
              controller: _inactiviteController,
              decoration: InputDecoration(labelText: t.seuilInactivite),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baisseController,
              decoration: InputDecoration(labelText: t.seuilBaisse),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _enregistrer,
                icon: const Icon(Icons.save_outlined),
                label: Text(t.enregistrer),
              ),
            ),
          ],
        );
      },
    );
  }
}
