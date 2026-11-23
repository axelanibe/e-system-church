import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/depot_sycebnl.dart';
import '../models/identite.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'identite_institutionnelle_screen.dart';
import 'registres_sycebnl_screen.dart';
import 'sycebnl_screen.dart';

/// Écran « Dépôt SYCEBNL » (tranche dépôt SYCEBNL, migration 043) :
/// ressources annuelles de l'exercice civil, seuil de 50 000 000
/// FCFA, dépôt requis ou non, échéance du 30 mai de l'année suivante,
/// et suivi du dépôt (à préparer, prêt, déposé).
///
/// Il n'existe pas d'API DGI : le dépôt se fait par l'église sur
/// e-impots.gouv.ci avec son NCC. L'application prépare, exporte et
/// suit, elle ne dépose pas elle-même. Le statut « déposé » ne se met
/// que par un geste explicite de l'admin, jamais automatiquement.
/// En dessous du seuil, aucun dépôt fiscal SYCEBNL n'est imposé.
class DepotSycebnlScreen extends StatefulWidget {
  const DepotSycebnlScreen({super.key});

  @override
  State<DepotSycebnlScreen> createState() => _DepotSycebnlScreenState();
}

class _DepotSycebnlScreenState extends State<DepotSycebnlScreen> {
  int _annee = DateTime.now().year;
  late Future<(DepotSycebnl, IdentiteInstitutionnelle)> _future;

  // Suivi : champs du formulaire, remplis à chaque chargement.
  String _statut = 'a_preparer';
  final _dateDepotController = TextEditingController();
  final _referenceController = TextEditingController();
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _dateDepotController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _future = Future.wait([
        api.getDepotSycebnl(annee: _annee),
        api.getIdentite(),
      ]).then((v) {
        final depot = v[0] as DepotSycebnl;
        _statut = depot.suivi?.statut ?? 'a_preparer';
        _dateDepotController.text = depot.suivi?.dateDepot ?? '';
        _referenceController.text = depot.suivi?.reference ?? '';
        return (depot, v[1] as IdentiteInstitutionnelle);
      });
    });
  }

  Future<void> _enregistrerSuivi() async {
    if (_statut == 'depose' && _dateDepotController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Indiquez la date du dépôt pour marquer l’exercice comme déposé.',
          ),
        ),
      );
      return;
    }
    setState(() => _enregistrement = true);
    try {
      await context.read<AppState>().api.updateDepotSycebnl(
        annee: _annee,
        statut: _statut,
        dateDepot: _dateDepotController.text.trim().isEmpty
            ? null
            : _dateDepotController.text.trim(),
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
      );
      if (mounted) showSuccess(context, 'Suivi du dépôt enregistré.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devise = context.read<AppState>().devise;
    final anneeCourante = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(title: const Text('Dépôt SYCEBNL')),
      body: FutureBuilder<(DepotSycebnl, IdentiteInstitutionnelle)>(
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
          final depot = snapshot.data!.$1;
          final identite = snapshot.data!.$2;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    const Text(
                      'Exercice',
                      style: TextStyle(fontSize: 13.5),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _annee,
                      items: [
                        for (final a in [
                          anneeCourante - 2,
                          anneeCourante - 1,
                          anneeCourante,
                        ])
                          DropdownMenuItem(value: a, child: Text('$a')),
                      ],
                      onChanged: (a) {
                        if (a == null) return;
                        setState(() => _annee = a);
                        _refresh();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Card(
                  color: AppTheme.orClair,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Le dépôt se fait par l’église sur e-impots.gouv.ci '
                      'avec son NCC. L’application prépare, exporte et '
                      'suit, elle ne dépose pas elle-même.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.violetProfond,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ressources annuelles',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatMontant(depot.ressources, devise),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dîmes, offrandes, dons et cotisations confirmés '
                          'de l’exercice $_annee.',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Seuil de dépôt : ${formatMontant(depot.seuil, devise)}',
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          depot.requis
                              ? 'Dépôt requis : vos ressources atteignent le seuil.'
                              : 'Aucun dépôt fiscal SYCEBNL n’est imposé pour cet exercice : vos ressources sont en dessous du seuil.',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: depot.requis
                                ? AppTheme.violetProfond
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Échéance',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'À déposer avant le ${depot.echeanceAffichee}.',
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          identite.ncc == null || identite.ncc!.isEmpty
                              ? 'NCC non renseigné : ajoutez-le dans l’identité institutionnelle, il sert au dépôt sur e-impots.'
                              : 'NCC : ${identite.ncc}',
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        if (identite.ncc == null || identite.ncc!.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const IdentiteInstitutionnelleScreen(),
                                ),
                              ),
                              icon: const Icon(Icons.badge_outlined),
                              label: const Text(
                                'Renseigner le NCC',
                                style: TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'Suivi du dépôt',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.or,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                depot.suivi?.statutLibelle ?? 'À préparer',
                                style: const TextStyle(
                                  color: AppTheme.violetProfond,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        dialogDropdown<String>(
                          value: _statut,
                          label: 'Statut',
                          options: const {
                            'a_preparer': 'À préparer',
                            'pret': 'Prêt',
                            'depose': 'Déposé',
                          },
                          onChanged: (v) =>
                              setState(() => _statut = v ?? 'a_preparer'),
                        ),
                        dialogDateField(
                          context: context,
                          controller: _dateDepotController,
                          label: 'Date de dépôt',
                        ),
                        dialogTextField(
                          controller: _referenceController,
                          label: 'Référence',
                          aide:
                              'Ex. numéro de reçu e-impots, si le dépôt est fait.',
                        ),
                        const SizedBox(height: 4),
                        FilledButton.icon(
                          onPressed: _enregistrement
                              ? null
                              : _enregistrerSuivi,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text(
                            'Enregistrer le suivi',
                            style: TextStyle(fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SycebnlScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text(
                    'Ouvrir les états SYCEBNL',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RegistresSycebnlScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text(
                    'Gérer les registres',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
