import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Rappels d'événements de vie (US7) : anniversaire, mariage,
/// conversion, baptême. Les dates sont celles des fiches membres ; un
/// membre masque les types qu'il ne veut pas voir rappelés depuis ses
/// paramètres. Aucune date n'est inventée.
class EvenementsVieScreen extends StatefulWidget {
  const EvenementsVieScreen({super.key});

  @override
  State<EvenementsVieScreen> createState() => _EvenementsVieScreenState();
}

class _EvenementsVieScreenState extends State<EvenementsVieScreen> {
  late Future<List<EvenementVie>> _future;
  int _jours = 30;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EvenementVie>> _load() =>
      context.read<AppState>().api.getEvenementsVie(jours: _jours);

  void _refresh() => setState(() => _future = _load());

  String _libelleType(EvenementVie e, T12Strings t) => switch (e.type) {
        'mariage' => t.mariage,
        'conversion' => t.conversion,
        'bapteme' => t.bapteme,
        _ => t.anniversaire,
      };

  IconData _iconeType(EvenementVie e) => switch (e.type) {
        'mariage' => Icons.favorite_outline,
        'conversion' => Icons.auto_awesome_outlined,
        'bapteme' => Icons.water_drop_outlined,
        _ => Icons.cake_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.evenementsVie),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.calendar_month_outlined),
            onSelected: (v) => setState(() {
              _jours = v;
              _refresh();
            }),
            itemBuilder: (context) => [
              PopupMenuItem(value: 7, child: Text('7 ${t.prochainsJours.toLowerCase()}')),
              PopupMenuItem(value: 30, child: Text('30 ${t.prochainsJours.toLowerCase()}')),
              PopupMenuItem(value: 90, child: Text('90 ${t.prochainsJours.toLowerCase()}')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<EvenementVie>>(
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
                icon: Icons.cake_outlined, message: t.vide);
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                final delai = e.joursRestants == 0
                    ? t.aujourdhui
                    : '${e.joursRestants} ${t.joursRestants}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(_iconeType(e), color: AppTheme.or),
                    title: Text(e.nom,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${_libelleType(e, t)} · ${formatDateSeule(DateTime.tryParse(e.date))}'),
                    trailing: Text(delai,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
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
