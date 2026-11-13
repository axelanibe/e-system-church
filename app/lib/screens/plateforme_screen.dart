import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/acces_plateforme.dart';
import '../models/plateforme.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Chiffres globaux de la plateforme e-System Church, accès Plateforme
/// seulement (admin ou aide, `GET /plateforme/chiffres`). Chiffres
/// seulement : aucun détail nominatif, aucune liste de membres, aucune
/// gestion des membres au jour le jour. La plateforme ne gère pas les
/// membres, elle voit seulement les chiffres de toutes les églises
/// mères ensemble. Le super_admin y ajoute aussi les personnes qui
/// l'aident (droits limités, révocables).
class PlateformeScreen extends StatefulWidget {
  const PlateformeScreen({super.key});

  @override
  State<PlateformeScreen> createState() => _PlateformeScreenState();
}

class _PlateformeScreenState extends State<PlateformeScreen> {
  late Future<ChiffresPlateforme> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getPlateforme();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.isPlateforme) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plateforme')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message:
              'Seuls l’admin de la plateforme et ses aides voient les chiffres globaux.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plateforme'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => context.read<AppState>().logout(),
          ),
        ],
      ),
      body: FutureBuilder<ChiffresPlateforme>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: () => setState(
                () => _future = context.read<AppState>().api.getPlateforme(),
              ),
            );
          }
          final chiffres = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(
              () => _future = context.read<AppState>().api.getPlateforme(),
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Card(
                        color: AppTheme.orClair,
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Chiffres globaux de toutes les églises mères '
                            'ensemble. Aucun détail nominatif, aucune '
                            'gestion des membres au jour le jour : la '
                            'plateforme voit seulement les chiffres.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SectionTitle(title: 'Églises'),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount =
                              constraints.maxWidth > 600 ? 3 : 2;
                          return GridView.count(
                            crossAxisCount: crossAxisCount,
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.6,
                            children: [
                              StatCard(
                                label: 'Églises mères',
                                value: '${chiffres.eglisesMeres}',
                                icon: Icons.account_balance_outlined,
                              ),
                              StatCard(
                                label: 'Branches',
                                value: '${chiffres.branches}',
                                icon: Icons.account_tree_outlined,
                              ),
                              StatCard(
                                label: 'Églises au total',
                                value: '${chiffres.eglisesTotal}',
                                icon: Icons.church_outlined,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      const SectionTitle(title: 'Membres et contributions'),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount =
                              constraints.maxWidth > 600 ? 3 : 2;
                          return GridView.count(
                            crossAxisCount: crossAxisCount,
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.6,
                            children: [
                              StatCard(
                                label: 'Membres actifs',
                                value: '${chiffres.membresActifs}',
                                icon: Icons.people_outline,
                              ),
                              StatCard(
                                label: 'Contributions confirmées',
                                value: '${chiffres.nombreContributions}',
                                icon: Icons.receipt_long_outlined,
                              ),
                              StatCard(
                                label: 'Total des contributions',
                                value: formatFcfa(
                                    chiffres.totalContributionsFcfa),
                                icon: Icons.trending_up,
                                color: AppTheme.bleuNuit,
                              ),
                              StatCard(
                                label: 'Dépenses confirmées',
                                value:
                                    formatFcfa(chiffres.depensesFcfa),
                                icon: Icons.trending_down,
                                color: AppTheme.rougeErreur,
                              ),
                            ],
                          );
                        },
                      ),
                      if (state.isSuperAdmin) ...[
                        const SizedBox(height: 16),
                        const _AccesPlateformeSection(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Accès Plateforme (super_admin seulement) : liste des accès, ajout
/// d'une personne pour aider (droits limités, révocable), révocation.
class _AccesPlateformeSection extends StatefulWidget {
  const _AccesPlateformeSection();

  @override
  State<_AccesPlateformeSection> createState() =>
      _AccesPlateformeSectionState();
}

class _AccesPlateformeSectionState extends State<_AccesPlateformeSection> {
  /// Droits proposables à la création : le serveur n'accepte que
  /// ceux-là aujourd'hui.
  static const _droitsProposables = ['chiffres'];

  late Future<List<AccesPlateforme>> _future;
  final _emailController = TextEditingController();
  final _nomController = TextEditingController();
  final _droits = <String>{'chiffres'};
  bool _creation = false;
  String? _erreurCreation;
  AccesPlateformeCree? _dernierCree;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.listerAccesPlateforme();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nomController.dispose();
    super.dispose();
  }

  void _recharger() {
    setState(
        () => _future = context.read<AppState>().api.listerAccesPlateforme());
  }

  Future<void> _creer() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _erreurCreation = 'Saisissez un e-mail valide.');
      return;
    }
    if (_droits.isEmpty) {
      setState(() => _erreurCreation = 'Choisissez au moins un droit.');
      return;
    }
    setState(() {
      _creation = true;
      _erreurCreation = null;
    });
    try {
      final cree =
          await context.read<AppState>().api.creerAccesPlateforme(
                email: email,
                nom: _nomController.text.trim().isEmpty
                    ? null
                    : _nomController.text.trim(),
                droits: _droits.toList(),
              );
      if (!mounted) return;
      setState(() {
        _dernierCree = cree;
        _emailController.clear();
        _nomController.clear();
      });
      _recharger();
      if (cree.lienInvitation == null) {
        showSuccess(context,
            'Accès ajouté : la personne se connecte avec son mot de passe existant.');
      }
    } catch (e) {
      if (mounted) setState(() => _erreurCreation = messageErreurSimple(e));
    } finally {
      if (mounted) setState(() => _creation = false);
    }
  }

  Future<void> _revoquer(AccesPlateforme acces) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Révoquer cet accès ?'),
        content: Text(
            '${acces.nom} (${acces.email}) ne pourra plus se connecter à la Plateforme.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    try {
      await context.read<AppState>().api.revoquerAccesPlateforme(acces.userId);
      if (!mounted) return;
      showSuccess(context, 'Accès révoqué.');
      _recharger();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: 'Accès Plateforme'),
        const Text(
          'Les personnes qui aident l’admin de la plateforme, avec leurs droits limités. Chacune a sa propre connexion, révocable.',
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<AccesPlateforme>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return AppError(
                message: snapshot.error.toString(),
                onRetry: _recharger,
              );
            }
            final acces = snapshot.data!;
            if (acces.isEmpty) {
              return const EmptyState(
                icon: Icons.admin_panel_settings_outlined,
                message: 'Aucun accès pour l’instant.',
              );
            }
            return Column(
              children: [
                for (final a in acces)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        a.estSuperAdmin
                            ? Icons.admin_panel_settings
                            : Icons.person_outline,
                      ),
                      title: Text(a.nom),
                      subtitle: Text(
                        '${a.email} · ${a.roleLabel} · ${a.droits.map((d) => libellesDroitsPlateforme[d] ?? d).join(', ')}',
                      ),
                      trailing: a.estSuperAdmin
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Révoquer cet accès',
                              onPressed: () => _revoquer(a),
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const SectionTitle(title: 'Ajouter une personne pour aider'),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nomController,
          decoration: const InputDecoration(
            labelText: 'Nom complet (facultatif)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 8),
        for (final droit in _droitsProposables)
          CheckboxListTile(
            title:
                Text(libellesDroitsPlateforme[droit] ?? droit),
            value: _droits.contains(droit),
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _droits.add(droit);
                } else {
                  _droits.remove(droit);
                }
              });
            },
          ),
        if (_erreurCreation != null) ...[
          const SizedBox(height: 8),
          Text(
            _erreurCreation!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _creation ? null : _creer,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _creation
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Ajouter cet accès'),
          ),
        ),
        if (_dernierCree?.lienInvitation != null) ...[
          const SizedBox(height: 12),
          Card(
            color: AppTheme.orClair,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nouveau compte : envoyez ce lien à la personne pour qu’elle crée son mot de passe.',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_dernierCree!.lienInvitation!),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: _dernierCree!.lienInvitation!));
                      if (context.mounted) {
                        showSuccess(context, 'Lien copié.');
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copier le lien'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
