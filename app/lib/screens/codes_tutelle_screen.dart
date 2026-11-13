import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Codes de tutelle à usage unique (`ESC-T-XXXXXX`, migration 009).
/// La mère génère un code et le donne à une église qui veut se rattacher
/// à elle. À l'acceptation du rattachement le code passe à `Utilisé`,
/// automatiquement, et n'est plus valide. Un code annulé ne sert plus.
class CodesTutelleScreen extends StatefulWidget {
  const CodesTutelleScreen({super.key});

  @override
  State<CodesTutelleScreen> createState() => _CodesTutelleScreenState();
}

class _CodesTutelleScreenState extends State<CodesTutelleScreen> {
  late Future _future;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future _load() =>
      context.read<AppState>().api.getCodesTutelle();

  void _refresh() => setState(() => _future = _load());

  Future<void> _creer() async {
    setState(() => _creating = true);
    try {
      final code = await context.read<AppState>().api.createCodeTutelle();
      if (!mounted) return;
      showSuccess(context, 'Code ${code.code} créé. Donnez-le à l’église à rattacher.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _annuler(String id) async {
    try {
      await context.read<AppState>().api.annulerCodeTutelle(id);
      if (!mounted) return;
      showSuccess(context, 'Code annulé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Seule une église mère génère un code : une annexe ne peut pas
    // avoir d'annexe (règle du 11/11/2026).
    final estMere = context.watch<AppState>().church?.isMere ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Codes de tutelle')),
      body: FutureBuilder(
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
          final codes = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Un code de tutelle ESC-T-… ne sert qu’une fois : donnez-le à une église qui veut se rattacher à vous. Dès que la mère accepte la demande, le code n’est plus valide, automatiquement, et l’église devient une de vos annexes. Votre code permanent ESC-… reste valable pour les membres et les autres demandes.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (estMere)
                  FilledButton.icon(
                    onPressed: _creating ? null : _creer,
                    icon: const Icon(Icons.add_outlined),
                    label: const Text('Générer un code de tutelle'),
                  ),
                const SizedBox(height: 16),
                if (codes.isEmpty)
                  const EmptyState(
                    icon: Icons.key_outlined,
                    message: 'Aucun code de tutelle généré.',
                  )
                else
                  ...codes.map((c) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.key_outlined),
                          title: Text(
                            c.code,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            c.estActif
                                ? 'Actif · créé le ${formatDate(c.createdAt)}'
                                : c.status == 'utilise'
                                    ? 'Utilisé par ${[c.utiliseeParNom, c.utiliseeParCode].where((e) => (e ?? '').isNotEmpty).join(' · ')}'
                                    : 'Annulé',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusChip(
                                label: c.statusLabel,
                                color: c.estActif
                                    ? AppTheme.bleuNuit
                                    : AppTheme.rougeErreur,
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_outlined),
                                tooltip: 'Copier le code',
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: c.code));
                                  showSuccess(context, 'Code copié.');
                                },
                              ),
                              if (c.estActif)
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: AppTheme.rougeErreur),
                                  tooltip: 'Annuler ce code',
                                  onPressed: () => _annuler(c.id),
                                ),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}
