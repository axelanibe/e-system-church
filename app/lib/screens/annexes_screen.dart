import 'dart:async';

import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/annexe.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'rattachements_screen.dart';
import 'transferts_screen.dart';
import 'tree_screen.dart';
import 'alertes_mere_screen.dart';
import 'annexe_detail_screen.dart';
import 'codes_tutelle_screen.dart';

/// Mes annexes : les églises sous tutelle de mon église mère, avec leurs
/// chiffres. La mère voit directement ce qui s'y passe, sans changer
/// d'église. Recherche par nom, code ou ville.
class AnnexesScreen extends StatefulWidget {
  const AnnexesScreen({super.key});

  @override
  State<AnnexesScreen> createState() => _AnnexesScreenState();
}

class _AnnexesScreenState extends State<AnnexesScreen> {
  final _recherche = TextEditingController();
  Timer? _debounce;
  List<Annexe> _annexes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _load({String? q}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await context.read<AppState>().api.getAnnexes(q: q);
      if (!mounted) return;
      setState(() {
        _annexes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Recherche en direct, comme sur Membres : temporisation de 400 ms
  /// puis appel serveur avec la recherche.
  void _onRechercheChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _load(q: value.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes annexes'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _recherche,
              decoration: const InputDecoration(
                labelText: 'Rechercher une annexe',
                hintText: 'Nom, code ESC-… ou ville',
                prefixIcon: Icon(Icons.search_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: _onRechercheChanged,
              onSubmitted: (value) {
                _debounce?.cancel();
                _load(q: value.trim());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.swap_horiz_outlined),
                    title: const Text('Transferts de membres'),
                    subtitle: const Text(
                        'Déplacer un membre vers une autre église du réseau.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TransfertsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: const Text('Arbre du réseau'),
                    subtitle: const Text(
                        'Hiérarchie des églises mères et annexes.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TreeScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('Demandes de rattachement'),
                    subtitle: const Text(
                        'Églises qui demandent à se rattacher à vous.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RattachementsScreen(),
                        ),
                      );
                    },
                  ),
                  if (context.watch<AppState>().church?.isMere ?? false) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          const Icon(Icons.warning_amber_outlined),
                      title: const Text('Alertes du réseau'),
                      subtitle: const Text(
                          'Antenne inactive, contributions en baisse, rapport non soumis.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AlertesMereScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const AppLoading()
                : _error != null
                    ? AppError(
                        message: _error!,
                        onRetry: () => _load(q: _recherche.text.trim()),
                      )
                    : _annexes.isEmpty
                        ? EmptyState(
                            icon: Icons.account_tree_outlined,
                            message: _recherche.text.trim().isNotEmpty
                                ? 'Aucune annexe ne correspond à « ${_recherche.text.trim()} ».'
                                : 'Aucune annexe pour l’instant. Une église se rattache à vous avec votre code permanent ou un code de tutelle, depuis « Demandes de rattachement ».',
                            actionLabel:
                                _recherche.text.trim().isNotEmpty
                                    ? null
                                    : 'Voir les demandes de rattachement',
                            onAction: _recherche.text.trim().isNotEmpty
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const RattachementsScreen(),
                                      ),
                                    ),
                          )
                        : RefreshIndicator(
                            onRefresh: () =>
                                _load(q: _recherche.text.trim()),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: _annexes.length,
                              itemBuilder: (context, i) {
                                final a = _annexes[i];
                                return Card(
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.account_tree_outlined),
                                    title: Text(
                                      a.egliseNom,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${a.egliseCode} · ${a.egliseVille ?? ''}'
                                      '${a.niveau == 1 ? '' : ' · niveau ${a.niveau}'}',
                                      maxLines: 2,
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${a.membresActifs} membres',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.bold),
                                        ),
                                        Text(
                                          formatFcfa(a.totalFcfa),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      final supprimee =
                                          await Navigator.of(context).push(
                                        MaterialPageRoute<bool>(
                                          builder: (_) =>
                                              AnnexeDetailScreen(
                                                  annexeId: a.egliseId),
                                        ),
                                      );
                                      if (supprimee == true && context.mounted) {
                                        showSuccess(
                                            context, 'Annexe supprimée.');
                                        _load(
                                            q: _recherche.text.trim());
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const CodesTutelleScreen()),
          );
        },
        icon: const Icon(Icons.key_outlined),
        label: const Text('Code de tutelle'),
      ),
    );
  }
}

/// Petite carte de chiffres, réutilisée par le détail d'annexe.
class StatMini extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const StatMini({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color ?? AppTheme.bleuNuit),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
