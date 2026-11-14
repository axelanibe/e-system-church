import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Lectures sensibles (US17) : toute lecture d'une donnée sensible est
/// journalisée. L'admin voit le journal de son église ; le membre voit
/// qui a consulté sa fiche. Les données sensibles sont masquées par
/// défaut côté application (téléphone et e-mail des autres membres non
/// affichés hors des écrans de gestion).
class ConsultationsScreen extends StatefulWidget {
  /// Si vrai, le membre voit qui a consulté sa fiche ; sinon, l'admin
  /// voit le journal de l'église.
  final bool vueMembre;

  const ConsultationsScreen({super.key, this.vueMembre = false});

  @override
  State<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

class _ConsultationsScreenState extends State<ConsultationsScreen> {
  late Future<List<ConsultationSensible>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ConsultationSensible>> _load() => widget.vueMembre
      ? context.read<AppState>().api.getMesConsultations()
      : context.read<AppState>().api.getConsultationsSensibles();

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.vueMembre ? t.quiAConsulte : t.consultations)),
      body: FutureBuilder<List<ConsultationSensible>>(
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
                icon: Icons.visibility_outlined,
                message: t.aucuneConsultation);
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final c = items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.visibility_outlined,
                        color: AppTheme.or),
                    title: Text(c.lecteur ?? t.lecture,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${c.ressource}${c.ressourceId == null ? '' : ' · ${c.ressourceId}'}'),
                    trailing: Text(
                      formatDateTime(DateTime.tryParse(c.creeLe)),
                      style: Theme.of(context).textTheme.bodySmall,
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
