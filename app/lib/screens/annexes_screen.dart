import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/annexe.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes annexes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Codes de tutelle',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const CodesTutelleScreen()),
              );
            },
          ),
        ],
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
              onSubmitted: (value) => _load(q: value.trim()),
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
                        ? const EmptyState(
                            icon: Icons.account_tree_outlined,
                            message:
                                'Aucune annexe pour l’instant. Une église se rattache à vous avec votre code permanent ou un code de tutelle, depuis « Demandes de rattachement ».',
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
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${a.egliseCode} · ${a.egliseVille ?? ''}'
                                      '${a.niveau == 1 ? '' : ' · niveau ${a.niveau}'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              AnnexeDetailScreen(
                                                  annexeId: a.egliseId),
                                        ),
                                      );
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
            Icon(icon, color: color ?? AppTheme.vertFonce),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
