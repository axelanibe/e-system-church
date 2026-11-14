import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Alertes pour l'église mère (US11) : antenne inactive, contributions
/// en baisse, rapport non soumis. Une alerte par antenne et par type
/// tant qu'elle n'est pas traitée ; une antenne ne voit jamais les
/// alertes d'une autre antenne (règle serveur). Les seuils se règlent
/// dans les listes configurables.
class AlertesMereScreen extends StatefulWidget {
  const AlertesMereScreen({super.key});

  @override
  State<AlertesMereScreen> createState() => _AlertesMereScreenState();
}

class _AlertesMereScreenState extends State<AlertesMereScreen> {
  late Future<List<AlerteMere>> _future;
  bool _ouvertesSeulement = true;
  Map<String, String> _nomsAnnexes = const {};

  @override
  void initState() {
    super.initState();
    _future = _load();
    _chargerNoms();
  }

  Future<void> _chargerNoms() async {
    final annexes = await context.read<AppState>().api.getAnnexes();
    if (mounted) {
      setState(() => _nomsAnnexes = {
            for (final a in annexes) a.egliseId: a.egliseNom,
          });
    }
  }

  Future<List<AlerteMere>> _load() => context
      .read<AppState>()
      .api
      .getAlertesMere(statut: _ouvertesSeulement ? 'ouverte' : null);

  void _refresh() => setState(() => _future = _load());
  Future<void> _detecter() async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    await context.read<AppState>().api.detecterAlertes();
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.detectionTerminee)));
  }

  Future<void> _traiter(AlerteMere a) async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    await context.read<AppState>().api.traiterAlerte(a.id);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.alerteTraitee)));
  }

  String _libelleType(AlerteMere a, T12Strings t) => switch (a.type) {
        'baisse_contributions' => t.alerteBaisse,
        'rapport_manquant' => t.alerteRapport,
        _ => t.alerteInactive,
      };

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.alertesMere),
        actions: [
          IconButton(
            icon: const Icon(Icons.radar_outlined),
            tooltip: t.detecter,
            onPressed: _detecter,
          ),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() {
              _ouvertesSeulement = v;
              _refresh();
            }),
            itemBuilder: (context) => [
              PopupMenuItem(value: true, child: Text(t.ouvertesSeulement)),
              PopupMenuItem(value: false, child: Text(t.toutes)),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<AlerteMere>>(
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
                icon: Icons.notifications_none_outlined,
                message: t.aucuneAlerte);
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final a = items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      a.estOuverte
                          ? Icons.warning_amber_outlined
                          : Icons.check_circle_outline,
                      color: a.estOuverte
                          ? AppTheme.orAttention
                          : Colors.green,
                    ),
                    title: Text(_libelleType(a, t),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${_nomsAnnexes[a.annexeId] ?? a.annexeId} · ${a.periode}',
                    ),
                    trailing: a.estOuverte
                        ? TextButton(
                            onPressed: () => _traiter(a),
                            child: Text(t.traiter),
                          )
                        : StatusChip(
                            label: t.alerteTraitee,
                            color: AppTheme.bleuNuit),
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
