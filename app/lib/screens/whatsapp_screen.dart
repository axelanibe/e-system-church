import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// WhatsApp avec consentement (US10) : la liste des membres qui ont
/// consenti, avec leur téléphone. Aucun message n'est envoyé ici :
/// aucun fournisseur n'est branché, aucun envoi réel n'est possible
/// tant qu'Axel n'a pas choisi le canal. Un membre qui n'a pas consenti
/// n'apparaît jamais.
class WhatsappScreen extends StatefulWidget {
  const WhatsappScreen({super.key});

  @override
  State<WhatsappScreen> createState() => _WhatsappScreenState();
}

class _WhatsappScreenState extends State<WhatsappScreen> {
  late Future<List<WhatsappConsentement>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getWhatsappConsentements();
  }

  void _refresh() => setState(() =>
      _future = context.read<AppState>().api.getWhatsappConsentements());

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(title: Text(t.whatsapp)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              t.aucunFournisseur,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<WhatsappConsentement>>(
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
                      icon: Icons.message_outlined, message: t.vide);
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final m = items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.message_outlined,
                              color: AppTheme.or),
                          title: Text(m.nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle:
                              Text(m.telephone ?? '', maxLines: 1),
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
