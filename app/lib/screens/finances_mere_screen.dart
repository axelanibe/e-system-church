import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/rapport.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Finances de l'église mère en détail : total consolidé + détail par
/// branche, par période (mois, trimestre, année) et par type, avec chaque
/// transaction confirmée. Admin de l'église seulement.
/// La vue agrégée du tableau de bord reste, celle-ci s'ajoute à côté.
/// Périmètre récursif (10 novembre 2026, tranche Plateforme) : mon église
/// + tous ses descendants, petites-filles comprises, avec leur niveau.
/// LS-U1 : au-delà de 1 000 px, deux volets, liste des branches à gauche,
/// détail de la branche choisie à droite ; colonnes de texte centrées,
/// 600 à 720 px.
class FinancesMereScreen extends StatefulWidget {
  const FinancesMereScreen({super.key});

  @override
  State<FinancesMereScreen> createState() => _FinancesMereScreenState();
}

class _FinancesMereScreenState extends State<FinancesMereScreen> {
  String _periode = 'mois';
  DateTime _ancre = DateTime.now();
  late Future<RapportDetailConsolide> _future;

  /// Branche choisie dans le volet de droite (écrans larges seulement).
  String? _selectionEgliseId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String get _moisAncre =>
      '${_ancre.year}-${_ancre.month.toString().padLeft(2, '0')}';

  Future<RapportDetailConsolide> _load() {
    return context.read<AppState>().api.getRapportDetail(
          periode: _periode,
          mois: _moisAncre,
        );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  void _decaler(int sens) {
    final pas = _periode == 'mois'
        ? 1
        : _periode == 'trimestre'
            ? 3
            : 12;
    setState(() {
      _ancre = DateTime(_ancre.year, _ancre.month + sens * pas, 1);
      _future = _load();
    });
  }

  /// Libellé du niveau d'une branche dans le réseau de la mère.
  static String niveauLabel(int niveau) {
    if (niveau == 0) return 'Mon église';
    if (niveau == 1) return 'Sous-église';
    return 'Antenne · niveau $niveau';
  }

  String _csv(RapportDetailConsolide rapport) {
    final lignes = <String>[
      'Rapport finances mere;${rapport.eglise.name};${rapport.periode.label}',
      'Branche;Niveau;Code;Ville;Membres actifs;Dimes FCFA;Offrandes FCFA;Dons FCFA;Depenses FCFA;Entrees FCFA;Solde FCFA',
    ];
    for (final b in rapport.branches) {
      lignes.add([
        b.egliseNom,
        niveauLabel(b.niveau),
        b.egliseCode,
        b.egliseVille ?? '',
        '${b.membresActifs}',
        '${b.totaux['dime']?.totalFcfa ?? 0}',
        '${b.totaux['offrande']?.totalFcfa ?? 0}',
        '${b.totaux['don']?.totalFcfa ?? 0}',
        '${b.totaux['depense']?.totalFcfa ?? 0}',
        '${b.entreesFcfa}',
        '${b.soldeFcfa}',
      ].join(';'));
    }
    lignes.add(
        'Total reseau;;;;${rapport.membresActifs};${rapport.totaux['dime']?.totalFcfa ?? 0};${rapport.totaux['offrande']?.totalFcfa ?? 0};${rapport.totaux['don']?.totalFcfa ?? 0};${rapport.totaux['depense']?.totalFcfa ?? 0};${rapport.entreesFcfa};${rapport.soldeFcfa}');
    lignes.add('');
    lignes.add('Transactions confirmees;Branche;Type;Montant FCFA;Moyen;Reference;Membre;Date');
    for (final b in rapport.branches) {
      for (final t in b.transactions) {
        lignes.add([
          '',
          b.egliseNom,
          t.typeLabel,
          '${t.amountFcfa}',
          t.paymentLabel,
          t.paymentRef ?? '',
          t.membreNom ?? '',
          formatDate(t.createdAt),
        ].join(';'));
      }
    }
    return lignes.join('\n');
  }

  Future<void> _exporter(RapportDetailConsolide rapport) async {
    final csv = _csv(rapport);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rapport — ${rapport.periode.label}'),
        content: SingleChildScrollView(
          child: SelectableText(csv),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
    if (mounted) {
      showSuccess(context, 'Rapport copié (CSV). Collez-le dans un tableur.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Finances de la mère')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message:
              'Seul l’admin de l’église mère voit les finances du réseau.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Finances de la mère')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Période précédente',
                  onPressed: () => _decaler(-1),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final entry in <String, String>{
                          'Mois': 'mois',
                          'Trimestre': 'trimestre',
                          'Année': 'annee',
                        }.entries)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(entry.key),
                              selected: _periode == entry.value,
                              onSelected: (_) {
                                setState(() {
                                  _periode = entry.value;
                                  _future = _load();
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Période suivante',
                  onPressed: () => _decaler(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<RapportDetailConsolide>(
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
                final rapport = snapshot.data!;
                final maxEntrees = rapport.branches.fold<int>(
                    0, (m, b) => b.entreesFcfa > m ? b.entreesFcfa : m);
                final large =
                    MediaQuery.of(context).size.width > 1000;
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: large
                      ? _buildDeuxVolets(context, rapport, maxEntrees)
                      : _buildUneColonne(context, rapport, maxEntrees),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Carte du total consolidé, commune aux deux dispositions.
  Widget _carteTotaux(BuildContext context, RapportDetailConsolide rapport) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rapport.periode.label,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
                '${rapport.membresActifs} membres actifs dans le réseau'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Total(
                    label: 'Entrées',
                    value: formatFcfa(rapport.entreesFcfa),
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _Total(
                    label: 'Dépenses',
                    value: formatFcfa(rapport.depensesFcfa),
                    color: Colors.red,
                  ),
                ),
                Expanded(
                  child: _Total(
                    label: 'Solde',
                    value: formatFcfa(rapport.soldeFcfa),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in [
                  'dime',
                  'offrande',
                  'don',
                  'depense'
                ])
                  Chip(
                    label: Text(
                        '${Contribution.labelForType(type)} : ${formatFcfa(rapport.totaux[type]?.totalFcfa ?? 0)}'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _exporter(rapport),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exporter le rapport'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Carte de comparaison d'une branche (barre d'entrées).
  Widget _carteComparaison(
      BuildContext context, RapportDetailBranche b, int maxEntrees) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              b.egliseNom,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
                '${niveauLabel(b.niveau)} · ${b.egliseCode} · ${b.egliseVille ?? ''} · ${b.membresActifs} membres actifs'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: maxEntrees == 0 ? 0 : b.entreesFcfa / maxEntrees,
            ),
            const SizedBox(height: 4),
            Text(
                'Entrées ${formatFcfa(b.entreesFcfa)} · Dépenses ${formatFcfa(b.depensesFcfa)} · Solde ${formatFcfa(b.soldeFcfa)}'),
          ],
        ),
      ),
    );
  }

  /// Détail d'une branche : totaux par type et transactions confirmées.
  Widget _detailBranche(
      BuildContext context, RapportDetailBranche b) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              b.egliseNom,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
                '${niveauLabel(b.niveau)} · ${b.egliseCode} · ${b.egliseVille ?? ''} · ${b.membresActifs} membres actifs'),
            const SizedBox(height: 8),
            Text(
                'Solde ${formatFcfa(b.soldeFcfa)} · ${b.transactions.length} transactions confirmées'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in ['dime', 'offrande', 'don', 'depense'])
                  Chip(
                    label: Text(
                        '${Contribution.labelForType(type)} : ${formatFcfa(b.totaux[type]?.totalFcfa ?? 0)} (${b.totaux[type]?.nombre ?? 0})'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (b.transactions.isEmpty)
              const Text(
                  'Aucune transaction confirmée sur cette période.')
            else
              ...b.transactions.map(
                (t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Icon(
                      t.type == 'depense' ? Icons.remove : Icons.add,
                    ),
                  ),
                  title: Text(
                      '${t.typeLabel} — ${formatFcfa(t.amountFcfa)}'),
                  subtitle: Text(
                      '${t.paymentLabel}${t.membreNom != null ? ' · ${t.membreNom}' : ''} · ${formatDate(t.createdAt)}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Une colonne (téléphone et tablette) : total, comparaison, puis
  /// détail repliable par branche. Colonne de texte centrée, 720 px au plus.
  Widget _buildUneColonne(BuildContext context,
      RapportDetailConsolide rapport, int maxEntrees) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _carteTotaux(context, rapport),
                const SizedBox(height: 16),
                const SectionTitle(title: 'Comparer les branches'),
                ...rapport.branches.map(
                  (b) => _carteComparaison(context, b, maxEntrees),
                ),
                const SizedBox(height: 16),
                const SectionTitle(title: 'Détail par branche'),
                ...rapport.branches.map(
                  (b) => Card(
                    child: ExpansionTile(
                      title: Text(b.egliseNom),
                      subtitle: Text(
                          '${niveauLabel(b.niveau)} · Solde ${formatFcfa(b.soldeFcfa)} · ${b.transactions.length} transactions confirmées'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final type in [
                                'dime',
                                'offrande',
                                'don',
                                'depense'
                              ])
                                Chip(
                                  label: Text(
                                      '${Contribution.labelForType(type)} : ${formatFcfa(b.totaux[type]?.totalFcfa ?? 0)} (${b.totaux[type]?.nombre ?? 0})'),
                                ),
                            ],
                          ),
                        ),
                        if (b.transactions.isEmpty)
                          const ListTile(
                            title: Text(
                                'Aucune transaction confirmée sur cette période.'),
                          )
                        else
                          ...b.transactions.map(
                            (t) => ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  t.type == 'depense'
                                      ? Icons.remove
                                      : Icons.add,
                                ),
                              ),
                              title: Text(
                                  '${t.typeLabel} — ${formatFcfa(t.amountFcfa)}'),
                              subtitle: Text(
                                  '${t.paymentLabel}${t.membreNom != null ? ' · ${t.membreNom}' : ''} · ${formatDate(t.createdAt)}'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Deux volets (écran large, au-delà de 1 000 px) : total et liste des
  /// branches à gauche, détail de la branche choisie à droite, centré
  /// dans une colonne de 720 px au plus.
  Widget _buildDeuxVolets(BuildContext context,
      RapportDetailConsolide rapport, int maxEntrees) {
    final selection = rapport.branches.firstWhere(
      (b) => b.egliseId == _selectionEgliseId,
      orElse: () => rapport.branches.first,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 380,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _carteTotaux(context, rapport),
              const SizedBox(height: 16),
              const SectionTitle(title: 'Branches du réseau'),
              ...rapport.branches.map(
                (b) => Card(
                  color: b.egliseId == selection.egliseId
                      ? Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                      : null,
                  child: ListTile(
                    title: Text(b.egliseNom),
                    subtitle: Text(
                        '${niveauLabel(b.niveau)} · Solde ${formatFcfa(b.soldeFcfa)} · ${b.transactions.length} transactions'),
                    selected: b.egliseId == selection.egliseId,
                    onTap: () => setState(
                        () => _selectionEgliseId = b.egliseId),
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle(title: 'Comparer les branches'),
                      ...rapport.branches.map(
                        (b) =>
                            _carteComparaison(context, b, maxEntrees),
                      ),
                      const SizedBox(height: 16),
                      const SectionTitle(title: 'Détail de la branche'),
                      _detailBranche(context, selection),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Total({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }
}
