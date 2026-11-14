import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Langue et données (US15, US16).
///
/// US15 : langue des nouveaux écrans seulement (français par défaut,
/// anglais au choix) ; le reste de l'application reste en français.
/// US16 : le mode économique coupe le chargement des photos en réseau
/// (avatars et carte) pour économiser les données. Le repli SMS dépend
/// d'un fournisseur non choisi : aucun envoi réel, aucun coût.
class LangueDonneesScreen extends StatelessWidget {
  const LangueDonneesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesLocales>();
    final t = T12Strings(prefs.estAnglais);
    final estMembre = context.watch<AppState>().isMembre;
    return Scaffold(
      appBar: AppBar(title: Text(t.langueEtDonnees)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'Langue'),
          Card(
            child: RadioGroup<String>(
              groupValue: prefs.langue,
              onChanged: (v) {
                if (v != null) {
                  context.read<PreferencesLocales>().definirLangue(v);
                }
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: Text(t.francais),
                    value: 'fr',
                  ),
                  RadioListTile<String>(
                    title: Text(t.anglais),
                    value: 'en',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.langue,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SectionTitle(title: 'Données'),
          Card(
            child: SwitchListTile(
              title: Text(t.modeEconomique),
              subtitle: Text(t.modeEconomiqueDetail),
              value: prefs.modeEconomique,
              onChanged: (v) => context
                  .read<PreferencesLocales>()
                  .definirModeEconomique(v),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.repliSmsNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (estMembre) ...[
            const SizedBox(height: 8),
            _ConsentementsMembre(),
          ],
        ],
      ),
    );
  }
}

/// Consentements du membre (US10 WhatsApp, US16 repli SMS) et types
/// d'événements de vie à ne pas rappeler (US7).
class _ConsentementsMembre extends StatefulWidget {
  @override
  State<_ConsentementsMembre> createState() => _ConsentementsMembreState();
}

class _ConsentementsMembreState extends State<_ConsentementsMembre> {
  late Future<_Consentements> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Consentements> _load() async {
    final api = context.read<AppState>().api;
    final c = await api.getMesConsentements();
    return _Consentements(
      whatsapp: c.whatsapp,
      smsRepli: c.smsRepli,
      masques: c.evenementsVieMasques.toSet(),
    );
  }

  Future<void> _sauver(_Consentements c) async {
    final api = context.read<AppState>().api;
    await api.saveMesConsentements(
        whatsapp: c.whatsapp, smsRepli: c.smsRepli);
    await api.masquerEvenementsVie(c.masques.toList());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return FutureBuilder<_Consentements>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError || snapshot.data == null) {
          return AppError(
              message: t.erreurChargement,
              onRetry: () => setState(() => _future = _load()));
        }
        final c = snapshot.data!;
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(t.consentementWhatsapp),
                value: c.whatsapp,
                onChanged: (v) async {
                  setState(() => c.whatsapp = v);
                  await _sauver(c);
                  _snack(t.consentementsEnregistres);
                },
              ),
              SwitchListTile(
                title: Text(t.consentementSms),
                value: c.smsRepli,
                onChanged: (v) async {
                  setState(() => c.smsRepli = v);
                  await _sauver(c);
                  _snack(t.consentementsEnregistres);
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t.masquer,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ),
              for (final type in ['anniversaire', 'mariage', 'conversion', 'bapteme'])
                CheckboxListTile(
                  title: Text(switch (type) {
                    'mariage' => t.mariage,
                    'conversion' => t.conversion,
                    'bapteme' => t.bapteme,
                    _ => t.anniversaire,
                  }),
                  value: c.masques.contains(type),
                  onChanged: (v) async {
                    setState(() {
                      if (v == true) {
                        c.masques.add(type);
                      } else {
                        c.masques.remove(type);
                      }
                    });
                    await _sauver(c);
                    _snack(t.masquesEnregistres);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Consentements {
  bool whatsapp;
  bool smsRepli;
  Set<String> masques;

  _Consentements({
    required this.whatsapp,
    required this.smsRepli,
    required this.masques,
  });
}
