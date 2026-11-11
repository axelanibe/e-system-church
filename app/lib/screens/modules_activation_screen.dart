import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/module_eglise.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// US1 — Activation des modules de l'église (admin_eglise seulement).
///
/// Liste le noyau (toujours actif) et les modules activables avec un
/// interrupteur. Chaque changement passe par `PATCH /modules/:code` et est
/// journalisé côté serveur. Désactiver ne supprime aucune donnée : réactiver
/// restaure l'accès à l'identique. Chaque église décide seule pour
/// elle-même ; la mère ne force pas ses antennes.
class ModulesActivationScreen extends StatefulWidget {
  const ModulesActivationScreen({super.key});

  @override
  State<ModulesActivationScreen> createState() => _ModulesActivationScreenState();
}

class _ModulesActivationScreenState extends State<ModulesActivationScreen> {
  late Future<List<ModuleEglise>> _modulesFuture;

  @override
  void initState() {
    super.initState();
    _modulesFuture = context.read<AppState>().api.getModules();
  }

  Future<void> _changer(String code, bool actif) async {
    final state = context.read<AppState>();
    try {
      final module = await state.api.setModule(code: code, actif: actif);
      await state.refreshModules();
      if (!mounted) return;
      setState(() {
        _modulesFuture = _modulesFuture.then((modules) => modules
            .map((m) => m.code == code ? module : m)
            .toList());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            actif
                ? 'Module « ${module.label} » activé.'
                : 'Module « ${module.label} » désactivé. Aucune donnée supprimée.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Modules de l’église')),
      body: FutureBuilder<List<ModuleEglise>>(
        future: _modulesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return AppError(
              message: snapshot.error?.toString() ??
                  'Impossible de charger les modules.',
              onRetry: () => setState(() {
                _modulesFuture = context.read<AppState>().api.getModules();
              }),
            );
          }
          final modules = snapshot.data!;
          final noyau = modules.where((m) => m.noyau).toList();
          final activables = modules.where((m) => !m.noyau).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'À la création, seuls le noyau est actif. Activez les modules '
                'dont votre église a besoin : un module désactivé disparaît '
                'de la navigation et des tableaux de bord, sans perdre ses données.',
              ),
              const SizedBox(height: 16),
              const SectionTitle(title: 'Noyau — toujours actif'),
              Card(
                child: Column(
                  children: noyau
                      .map((m) => SwitchListTile(
                            title: Text(m.label),
                            subtitle: const Text('Toujours activé.'),
                            value: true,
                            onChanged: null,
                          ))
                      .toList(),
                ),
              ),
              const SectionTitle(title: 'Modules activables'),
              Card(
                child: Column(
                  children: activables
                      .map((m) => SwitchListTile(
                            title: Text(m.label),
                            value: m.actif,
                            onChanged: state.isAdmin
                                ? (v) => _changer(m.code, v)
                                : null,
                          ))
                      .toList(),
                ),
              ),
              if (!state.isAdmin)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Seul l’admin de l’église peut modifier l’activation.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
