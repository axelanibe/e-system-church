import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/annexe.dart';
import '../models/code_tutelle.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'rattachements_screen.dart';
import 'transferts_screen.dart';
import 'tree_screen.dart';
import 'alertes_mere_screen.dart';
import 'annexe_detail_screen.dart';

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
      body: RefreshIndicator(
        onRefresh: () async => _load(q: _recherche.text.trim()),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            // En-tête coloré (design couleurs messagerie, 16 nov.
            // 2026) : référence Projection (.annexe-cover), fond
            // carte, bordure or, phrase d'intro en bleu nuit.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppTheme.or, width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Mon église et ses annexes, transferts, rattachements, '
                'alertes.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.violetProfond,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _recherche,
              decoration: const InputDecoration(
                labelText: 'Rechercher une annexe',
                hintText: 'Nom, code ESC-… ou ville',
                hintStyle: TextStyle(fontSize: 13),
                prefixIcon: Icon(Icons.search_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: _onRechercheChanged,
              onSubmitted: (value) {
                _debounce?.cancel();
                _load(q: value.trim());
              },
            ),
            const SectionTitle(title: 'Mon réseau'),
            const ArbreReseau(),
            const SectionTitle(title: 'Gérer les annexes'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.swap_horiz_outlined),
                    title: const Text('Transferts de membres', style: TextStyle(fontSize: 13.5)),
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
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('Demandes de rattachement', style: TextStyle(fontSize: 13.5)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RattachementsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        const Icon(Icons.warning_amber_outlined),
                    title: const Text('Alertes des annexes', style: TextStyle(fontSize: 13.5)),
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
              ),
            ),
            const SectionTitle(title: 'Code de tutelle'),
            const _CodeTutelleSection(),
            const SectionTitle(title: 'Annexes'),
            if (_loading)
              const AppLoading()
            else if (_error != null)
              AppError(
                message: _error!,
                onRetry: () => _load(q: _recherche.text.trim()),
              )
            else if (_annexes.isEmpty)
              EmptyState(
                icon: Icons.account_tree_outlined,
                message: _recherche.text.trim().isNotEmpty
                    ? 'Aucune annexe ne correspond à « ${_recherche.text.trim()} ».'
                    : 'Aucune annexe rattachée.',
                actionLabel: _recherche.text.trim().isNotEmpty
                    ? null
                    : 'Voir les demandes de rattachement',
                onAction: _recherche.text.trim().isNotEmpty
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RattachementsScreen(),
                          ),
                        ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
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
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${a.egliseCode} · ${a.egliseVille ?? ''}'
                        '${a.niveau == 1 ? '' : ' · niveau ${a.niveau}'}',
                        maxLines: 2,
                        style: const TextStyle(fontSize: 11.5),
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
          ],
        ),
      ),
    );
  }
}

/// Code de tutelle (maquette, écran 12) : le code actuel affiché,
/// régénération avec confirmation (l'ancien code s'arrête
/// immédiatement). Réutilise l'API de codes de tutelle existante
/// (`GET /codes-tutelle`, création puis annulation de l'ancien).
class _CodeTutelleSection extends StatefulWidget {
  const _CodeTutelleSection();

  @override
  State<_CodeTutelleSection> createState() => _CodeTutelleSectionState();
}

class _CodeTutelleSectionState extends State<_CodeTutelleSection> {
  late Future<List<CodeTutelle>> _future;
  bool _traitement = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getCodesTutelle();
  }

  void _refresh() =>
      setState(() => _future = context.read<AppState>().api.getCodesTutelle());

  Future<void> _regenerer(CodeTutelle? actif) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Régénérer le code ?', style: TextStyle(fontSize: 17)),
        content: const Text(
          'Ce code sert aux demandes de rattachement des annexes. '
          'Le régénérer arrête immédiatement l’ancien code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler', style: TextStyle(fontSize: 13.5)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Régénérer le code', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _traitement = true);
    try {
      final api = context.read<AppState>().api;
      if (actif != null) await api.annulerCodeTutelle(actif.id);
      final code = await api.createCodeTutelle();
      if (!mounted) return;
      showSuccess(
          context, 'Nouveau code ${code.code} créé. Donnez-le à l’église à rattacher.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _traitement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Seule une église mère génère un code : une annexe ne peut pas
    // avoir d'annexe (règle du 11/11/2026).
    final estMere = context.watch<AppState>().church?.isMere ?? false;
    return FutureBuilder<List<CodeTutelle>>(
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
        final codes = snapshot.data ?? const <CodeTutelle>[];
        final actif =
            codes.where((c) => c.estActif).firstOrNull;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Code actuel : ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 10.5),
                      ),
                      TextSpan(
                        text: actif?.code ??
                            'Aucun code généré pour l’instant',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ce code sert aux demandes de rattachement des annexes. '
                  'Le régénérer arrête immédiatement l’ancien code : '
                  'confirmation demandée avant.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (actif != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: actif.code));
                          showSuccess(context, 'Code copié.');
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copier', style: TextStyle(fontSize: 13.5)),
                      ),
                    if (actif != null) const SizedBox(width: 8),
                    if (estMere)
                      FilledButton.icon(
                        onPressed:
                            _traitement ? null : () => _regenerer(actif),
                        icon: const Icon(Icons.refresh_outlined),
                        label: const Text('Régénérer le code', style: TextStyle(fontSize: 13.5)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
            Icon(icon, color: color ?? AppTheme.violetProfond),
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
