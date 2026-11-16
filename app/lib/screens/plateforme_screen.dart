import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/acces_plateforme.dart';
import '../models/nettoyage_test.dart';
import '../models/plateforme.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

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
              '',
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plateforme'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: () => context.read<AppState>().logout(),
            ),
          ],
          bottom: const TabBar(
            labelStyle: TextStyle(fontSize: 12.5),
            unselectedLabelStyle: TextStyle(fontSize: 12.5),
            isScrollable: true,
            tabs: [
              Tab(text: 'Chiffres'),
              Tab(text: 'Église mère'),
              Tab(text: 'Codes promo'),
              Tab(text: 'Nettoyage'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            FutureBuilder<ChiffresPlateforme>(
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
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'La Plateforme (super utilisateur) a ses '
                            'identifiants et ses droits propres, hors '
                            'application d’église. Rien ici ne s’ouvre '
                            'depuis une église : ces vues complètent le '
                            'parcours de toute l’application.',
                            style: TextStyle(fontSize: 12),
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
                                label: 'Églises',
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
                                color: AppTheme.violetProfond,
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
          const _CreationEgliseMereSection(),
          const _CodesPromoSection(),
          const _NettoyageTestSection(),
        ],
      ),
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
        title: const Text('Révoquer cet accès ?', style: TextStyle(fontSize: 17)),
        content: Text(
            '${acces.nom} (${acces.email}) ne pourra plus se connecter à la Plateforme.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler', style: TextStyle(fontSize: 13.5)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Révoquer', style: TextStyle(fontSize: 13.5)),
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
                message: 'Aucun accès.',
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
                      title: Text(a.nom, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        '${a.email} · ${a.roleLabel} · ${a.droits.map((d) => libellesDroitsPlateforme[d] ?? d).join(', ')}',
                        style: const TextStyle(fontSize: 11.5),
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
            title: Text(libellesDroitsPlateforme[droit] ?? droit,
                style: const TextStyle(fontSize: 13.5)),
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
                : const Text('Ajouter cet accès', style: TextStyle(fontSize: 13.5)),
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
                    'Envoyez ce lien à la personne.',
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
                    label: const Text('Copier le lien', style: TextStyle(fontSize: 13.5)),
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

/// Création d'une église mère (maquette, écran 33) : Nom, Ville,
/// Téléphone, E-mail facultatif, code généré à la création.
/// Non branchée sur l'inscription existante : `POST /auth/register`
/// crée l'église avec son compte admin et renvoie des jetons qui
/// remplaceraient la session Plateforme, et exige nom, e-mail et mot
/// de passe d'un admin que le formulaire maquette ne demande pas.
/// La création par la Plateforme attend une route serveur dédiée
/// (super_admin) ; le bouton l'explique au lieu d'envoyer une
/// inscription incomplète.
class _CreationEgliseMereSection extends StatefulWidget {
  const _CreationEgliseMereSection();

  @override
  State<_CreationEgliseMereSection> createState() =>
      _CreationEgliseMereSectionState();
}

class _CreationEgliseMereSectionState
    extends State<_CreationEgliseMereSection> {
  final _nomController = TextEditingController();
  final _villeController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _nomController.dispose();
    _villeController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _creer() {
    if (_nomController.text.trim().length < 2 ||
        _villeController.text.trim().length < 2 ||
        _telephoneController.text.trim().length < 8) {
      showApiError(
          context, 'Nom, ville et téléphone sont obligatoires.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Création impossible pour l’instant : la création d’une '
          'église mère par la Plateforme nécessite une route serveur '
          'dédiée. Aucune église n’a été créée.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(title: 'Créer une église mère'),
              TextField(
                controller: _nomController,
                decoration: const InputDecoration(
                  labelText: 'Nom de l’église mère *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _villeController,
                decoration: const InputDecoration(
                  labelText: 'Ville *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _telephoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Le code de l’église est généré à la création ; '
                'l’activité et l’abonnement se suivent ensuite côté Plateforme.',
                style: TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _creer,
                child: const Text('Créer l’église mère', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Création de codes promo (maquette, écran 33) : Code, Réduction,
/// Date de fin. Codes créés par la Plateforme seule, réservés au
/// lancement. Non branchée : seule la validation d'un code existe
/// côté serveur (`POST /moi/abonnement/code-promo`), aucune route de
/// création ; le bouton l'explique au lieu d'envoyer dans le vide.
class _CodesPromoSection extends StatefulWidget {
  const _CodesPromoSection();

  @override
  State<_CodesPromoSection> createState() => _CodesPromoSectionState();
}

class _CodesPromoSectionState extends State<_CodesPromoSection> {
  final _codeController = TextEditingController();
  final _reductionController = TextEditingController();
  final _finController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _reductionController.dispose();
    _finController.dispose();
    super.dispose();
  }

  void _creer() {
    if (_codeController.text.trim().isEmpty ||
        _reductionController.text.trim().isEmpty) {
      showApiError(context, 'Code et réduction sont obligatoires.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Création impossible pour l’instant : aucune route serveur '
          'ne crée de code promo. Aucun code n’a été créé.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(title: 'Codes promo'),
              const EmptyState(
                icon: Icons.local_offer_outlined,
                message: 'Aucun code promo.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code *',
                  hintText: 'Code à communiquer',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reductionController,
                decoration: const InputDecoration(
                  labelText: 'Réduction *',
                  hintText: 'Choisir la réduction',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              dialogDateField(
                context: context,
                controller: _finController,
                label: 'Date de fin',
              ),
              const Text(
                'Codes créés par la Plateforme seule, réservés au lancement. '
                'L’église les applique dans Mon abonnement, bouton « Appliquer ».',
                style: TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _creer,
                child: const Text('Créer le code promo', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nettoyage des comptes TEST (maquette, écran 33) : aperçu puis
/// suppression en une seule transaction, après confirmation.
/// Branché sur l'API NettoyageTest existante
/// (`POST /admin/nettoyage-test`). Attention : la route serveur
/// exige aujourd'hui le rôle admin_eglise, une session Plateforme
/// (super_admin) y reçoit un 403 tant que le serveur ne l'ouvre pas
/// à ce rôle.
class _NettoyageTestSection extends StatefulWidget {
  const _NettoyageTestSection();

  @override
  State<_NettoyageTestSection> createState() => _NettoyageTestSectionState();
}

class _NettoyageTestSectionState extends State<_NettoyageTestSection> {
  late Future<NettoyageTestApercu> _future;
  bool _nettoyage = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getNettoyageTestApercu();
  }

  void _refresh() => setState(
        () => _future = context.read<AppState>().api.getNettoyageTestApercu(),
      );

  Future<void> _nettoyer(int total) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nettoyer les comptes TEST ?', style: TextStyle(fontSize: 17)),
        content: Text(
          '$total élément(s) TEST seront supprimés en une seule transaction. '
          'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler', style: TextStyle(fontSize: 13.5)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Nettoyer', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _nettoyage = true);
    try {
      final resultat =
          await context.read<AppState>().api.executerNettoyageTest();
      if (!mounted) return;
      showSuccess(context,
          '${resultat.total} élément(s) TEST supprimé(s).');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _nettoyage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NettoyageTestApercu>(
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
        final apercu = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionTitle(title: 'Nettoyage des comptes TEST', taille: 12.5),
              Card(
                color: AppTheme.rougeErreur.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aperçu : ${apercu.total} élément(s) TEST détecté(s).',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'La suppression se fait en une seule transaction, après confirmation.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (apercu.elements.isEmpty)
                const EmptyState(
                  icon: Icons.cleaning_services_outlined,
                  message: 'Aucun élément TEST détecté.',
                )
              else
                for (final e in apercu.elements)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(e.label, style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(e.type, style: const TextStyle(fontSize: 11.5)),
                    ),
                  ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _nettoyage || apercu.total == 0
                    ? null
                    : () => _nettoyer(apercu.total),
                child: const Text('Nettoyer les comptes TEST', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          ),
        );
      },
    );
  }
}
