import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/finances.dart';
import '../models/membres_complement.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/plan_comptable_excel.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'sycebnl_screen.dart';

/// Noms des mois en français, pour le suivi mensuel.
const _nomsMois = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

/// Modes de paiement d'une dépense (codes serveur → libellés).
const _modesPaiement = {
  'especes': 'Espèces',
  'wave': 'Wave',
  'orange_money': 'Orange Money',
  'mtn_money': 'MTN Mobile Money',
  'virement': 'Virement',
  'cheque': 'Chèque',
};

/// Module 4 (complément) — Budget, dépenses, caisse et rapport financier.
/// Les contributions (dîmes, offrandes, dons) restent dans FinancesScreen.
class FinancesComplementScreen extends StatefulWidget {
  const FinancesComplementScreen({super.key});

  @override
  State<FinancesComplementScreen> createState() =>
      _FinancesComplementScreenState();
}

class _FinancesComplementScreenState extends State<FinancesComplementScreen> {
  int _tab = 0;
  final _searchController = TextEditingController();
  String _query = '';
  String? _statutDepenseFilter;

  late Future<List<PosteBudgetaire>> _postesFuture;
  late Future<List<Budget>> _budgetsFuture;
  late Future<List<Depense>> _depensesFuture;
  late Future<List<CaisseMouvement>> _mouvementsFuture;
  late Future<CaisseSolde> _soldeFuture;
  Future<RapportFinancier>? _rapportFuture;
  final _anneeController =
      TextEditingController(text: '${DateTime.now().year}');

  // Plan comptable : catégories et départements (référentiels), suivi du
  // mois sélectionné et budgets mensuels de ce mois.
  List<CategorieDepense> _categories = [];
  List<Departement> _departements = [];
  late Future<SuiviMensuel> _suiviFuture;
  late Future<List<BudgetMensuel>> _budgetsMensuelsFuture;
  int _anneeSuivi = DateTime.now().year;
  int _moisSuivi = DateTime.now().month;
  final _anneeSuiviController =
      TextEditingController(text: '${DateTime.now().year}');

  String? _categorieNom(String? categorieId) {
    if (categorieId == null) return null;
    return _categories
        .where((c) => c.id == categorieId)
        .firstOrNull
        ?.libelle;
  }

  String? _departementNom(String? departementId) {
    if (departementId == null) return null;
    return _departements
        .where((d) => d.id == departementId)
        .firstOrNull
        ?.nom;
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _anneeController.dispose();
    _anneeSuiviController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    final api = context.read<AppState>().api;
    setState(() {
      _postesFuture = api.getPostesBudgetaires();
      _budgetsFuture = api.getBudgets();
      _depensesFuture = api.getDepenses();
      _mouvementsFuture = api.getCaisseMouvements();
      _soldeFuture = api.getCaisseSolde();
      _suiviFuture =
          api.getSuiviMensuel(annee: _anneeSuivi, mois: _moisSuivi);
      _budgetsMensuelsFuture = api.getBudgetsMensuels(
          annee: _anneeSuivi, mois: _moisSuivi);
    });
    _chargerReferentiels();
  }

  /// Catégories comptables et départements : l'écran reste utilisable
  /// sans eux si le chargement échoue (postes sans catégorie).
  Future<void> _chargerReferentiels() async {
    try {
      final api = context.read<AppState>().api;
      final categories = await api.getCategoriesDepenses();
      final departements = await api.getDepartements();
      if (mounted) {
        setState(() {
          _categories = categories;
          _departements = departements;
        });
      }
    } catch (_) {
      // Référentiels indisponibles : on continue sans eux.
    }
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      if (_tab == 0) {
        _postesFuture = api.getPostesBudgetaires();
        _budgetsFuture = api.getBudgets();
      }
      if (_tab == 1) _depensesFuture = api.getDepenses();
      if (_tab == 2) {
        _mouvementsFuture = api.getCaisseMouvements();
        _soldeFuture = api.getCaisseSolde();
      }
      if (_tab == 4) {
        _suiviFuture =
            api.getSuiviMensuel(annee: _anneeSuivi, mois: _moisSuivi);
        _budgetsMensuelsFuture = api.getBudgetsMensuels(
            annee: _anneeSuivi, mois: _moisSuivi);
      }
    });
  }

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _createPoste() async {
    final nomController = TextEditingController();
    final descriptionController = TextEditingController();
    String categorie = 'depense';
    String? categorieId;
    bool estRecurrente = false;
    await showCreateDialog(
      context: context,
      title: 'Nouveau poste budgétaire',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom du poste'),
        dialogDropdown<String>(
          value: categorie,
          label: 'Catégorie',
          options: const {'recette': 'Recette', 'depense': 'Dépense'},
          onChanged: (v) => categorie = v ?? 'depense',
        ),
        dialogDropdown<String?>(
          value: categorieId,
          label: 'Catégorie comptable (dépenses)',
          options: {
            null: 'Sans catégorie',
            for (final c in _categories) c.id: c.libelle,
          },
          onChanged: (v) => categorieId = v,
        ),
        StatefulBuilder(
          builder: (context, setDialogState) => SwitchListTile(
            title: const Text('Dépense récurrente'),
            subtitle: const Text('Sinon, dépense ponctuelle.'),
            value: estRecurrente,
            onChanged: (v) => setDialogState(() => estRecurrente = v),
          ),
        ),
        dialogTextField(
            controller: descriptionController, label: 'Description'),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.creerPostePlanComptable(
                nom: nomController.text.trim(),
                categorie: categorie,
                description: _opt(descriptionController),
                categorieId: categorie == 'depense' ? categorieId : null,
                estRecurrente: categorie == 'depense' && estRecurrente,
              );
          if (mounted) showSuccess(context, 'Poste budgétaire créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  /// Change la catégorie comptable et le marqueur récurrente d'un poste
  /// de dépense. Le nom et la catégorie recette ou dépense ne changent pas ici.
  Future<void> _modifierPoste(PosteBudgetaire poste) async {
    String? categorieId = poste.categorieId;
    bool estRecurrente = poste.estRecurrente;
    await showCreateDialog(
      context: context,
      title: 'Modifier le poste « ${poste.nom} »',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDropdown<String?>(
          value: categorieId,
          label: 'Catégorie comptable',
          options: {
            null: 'Sans catégorie',
            for (final c in _categories) c.id: c.libelle,
          },
          onChanged: (v) => categorieId = v,
        ),
        StatefulBuilder(
          builder: (context, setDialogState) => SwitchListTile(
            title: const Text('Dépense récurrente'),
            subtitle: const Text('Sinon, dépense ponctuelle.'),
            value: estRecurrente,
            onChanged: (v) => setDialogState(() => estRecurrente = v),
          ),
        ),
      ],
      isValid: () => true,
      onSave: () async {
        try {
          await context.read<AppState>().api.modifierPostePlanComptable(
                id: poste.id,
                categorieId: categorieId,
                estRecurrente: estRecurrente,
              );
          if (mounted) showSuccess(context, 'Poste budgétaire modifié.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createBudget(List<PosteBudgetaire> postes) async {
    final anneeController =
        TextEditingController(text: '${DateTime.now().year}');
    final montantController = TextEditingController();
    String? posteId = postes.isEmpty ? null : postes.first.id;
    await showCreateDialog(
      context: context,
      title: 'Nouveau budget',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: posteId,
          label: 'Poste budgétaire',
          options: {for (final p in postes) p.id: p.nom},
          onChanged: (v) => posteId = v,
        ),
        dialogTextField(
          controller: anneeController,
          label: 'Année',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
          controller: montantController,
          label: 'Montant prévu',
          keyboardType: TextInputType.number,
        ),
      ],
      isValid: () =>
          posteId != null && montantController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createBudget(
                posteId: posteId!,
                annee: int.tryParse(anneeController.text.trim()) ??
                    DateTime.now().year,
                montantPrevu: int.tryParse(montantController.text.trim()) ?? 0,
              );
          if (mounted) showSuccess(context, 'Budget créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createDepense(List<PosteBudgetaire> postes) async {
    final montantController = TextEditingController();
    final motifController = TextEditingController();
    final justificatifController = TextEditingController();
    final dateController = TextEditingController();
    final fournisseurController = TextEditingController();
    final responsableDepenseController = TextEditingController();
    final responsableAutorisationController = TextEditingController();
    final deviseController = TextEditingController(text: 'FCFA');
    String? posteId = postes.isEmpty ? null : postes.first.id;
    String? departementId;
    String? modePaiement;
    await showCreateDialog(
      context: context,
      title: 'Nouvelle dépense',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: posteId,
          label: 'Poste budgétaire',
          options: {for (final p in postes) p.id: p.nom},
          onChanged: (v) => posteId = v,
        ),
        dialogTextField(
          controller: montantController,
          label: 'Montant',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: motifController, label: 'Motif'),
        dialogDropdown<String?>(
          value: departementId,
          label: 'Département bénéficiaire',
          options: {
            null: 'Sans département',
            for (final d in _departements) d.id: d.nom,
          },
          onChanged: (v) => departementId = v,
        ),
        dialogDropdown<String?>(
          value: modePaiement,
          label: 'Mode de paiement',
          options: {
            null: 'Non précisé',
            for (final e in _modesPaiement.entries) e.key: e.value,
          },
          onChanged: (v) => modePaiement = v,
        ),
        dialogTextField(
            controller: fournisseurController,
            label: 'Fournisseur ou bénéficiaire'),
        dialogTextField(
            controller: responsableDepenseController,
            label: 'Responsable ayant effectué la dépense'),
        dialogTextField(
            controller: responsableAutorisationController,
            label: 'Responsable ayant autorisé la dépense'),
        dialogTextField(controller: deviseController, label: 'Devise'),
        dialogTextField(
            controller: justificatifController, label: 'Référence du justificatif'),
        dialogDateField(
            context: context, controller: dateController, label: 'Date de la dépense'),
      ],
      isValid: () =>
          posteId != null && montantController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          final creee = await context
              .read<AppState>()
              .api
              .creerDepenseComplete(
                posteId: posteId!,
                montantFcfa: int.tryParse(montantController.text.trim()) ?? 0,
                motif: motifController.text.trim(),
                justificatifRef: _opt(justificatifController),
                dateDepense: _opt(dateController),
                departementId: departementId,
                modePaiement: modePaiement,
                fournisseurBeneficiaire: _opt(fournisseurController),
                responsableDepense: _opt(responsableDepenseController),
                responsableAutorisation:
                    _opt(responsableAutorisationController),
                devise: _opt(deviseController) ?? 'FCFA',
              );
          if (mounted) {
            showSuccess(context,
                'Dépense enregistrée (${creee.reference ?? 'sans référence'}).');
          }
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  /// Saisie du budget mensuel d'un poste de dépense : un montant prévu
  /// pour un mois donné. Un second enregistrement remplace le premier.
  Future<void> _createBudgetMensuel(List<PosteBudgetaire> postes) async {
    final depenses =
        postes.where((p) => p.categorie == 'depense').toList();
    if (depenses.isEmpty) {
      showApiError(context, 'Aucun poste de dépense pour l’instant.');
      return;
    }
    final montantController = TextEditingController();
    final anneeController =
        TextEditingController(text: '$_anneeSuivi');
    String? posteId = depenses.first.id;
    int mois = _moisSuivi;
    await showCreateDialog(
      context: context,
      title: 'Budget mensuel',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDropdown<String?>(
          value: posteId,
          label: 'Poste budgétaire',
          options: {for (final p in depenses) p.id: p.nom},
          onChanged: (v) => posteId = v,
        ),
        dialogDropdown<int>(
          value: mois,
          label: 'Mois',
          options: {
            for (var m = 1; m <= 12; m++) m: _nomsMois[m - 1],
          },
          onChanged: (v) => mois = v ?? _moisSuivi,
        ),
        dialogTextField(
          controller: anneeController,
          label: 'Année',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
          controller: montantController,
          label: 'Montant prévu',
          keyboardType: TextInputType.number,
        ),
      ],
      isValid: () =>
          posteId != null && montantController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.creerBudgetMensuel(
                posteId: posteId!,
                annee: int.tryParse(anneeController.text.trim()) ??
                    DateTime.now().year,
                mois: mois,
                montantPrevu:
                    int.tryParse(montantController.text.trim()) ?? 0,
              );
          if (mounted) showSuccess(context, 'Budget mensuel enregistré.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _deleteBudgetMensuel(
      BudgetMensuel budget, String? posteNom) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le budget mensuel ${posteNom ?? '—'} '
      '(${_nomsMois[budget.mois - 1]} ${budget.annee}) ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.supprimerBudgetMensuel(budget.id);
      if (mounted) showSuccess(context, 'Budget mensuel supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Export du rapport des dépenses : PDF par le serveur, Excel construit
  /// côté application depuis les mêmes chiffres. Partage par SharePlus.
  Future<void> _exporterRapportDepenses(
      {required bool mensuel, required bool excel}) async {
    final annee = _anneeSuivi;
    final mois = mensuel ? _moisSuivi : null;
    try {
      final nom = mensuel
          ? 'rapport-depenses-$annee-${mois.toString().padLeft(2, '0')}'
          : 'rapport-depenses-$annee';
      if (excel) {
        final rapport = await context
            .read<AppState>()
            .api
            .getRapportPlanComptable(annee: annee, mois: mois);
        final bytes = construireClasseurPlanComptable(rapport);
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                name: '$nom.xlsx',
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              ),
            ],
            subject: 'Rapport des dépenses $nom',
          ),
        );
      } else {
        final bytes = await context
            .read<AppState>()
            .api
            .exporterRapportPlanComptablePdf(annee: annee, mois: mois);
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(bytes,
                  name: '$nom.pdf', mimeType: 'application/pdf'),
            ],
            subject: 'Rapport des dépenses $nom',
          ),
        );
      }
      if (mounted) showSuccess(context, 'Export partagé.');
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _setDepenseStatut(Depense depense, String statut) async {
    try {
      await context
          .read<AppState>()
          .api
          .setDepenseStatut(depense.id, statut);
      if (mounted) showSuccess(context, 'Dépense mise à jour.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deletePoste(PosteBudgetaire poste) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le poste budgétaire « ${poste.nom} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deletePosteBudgetaire(poste.id);
      if (mounted) showSuccess(context, 'Poste budgétaire supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deleteBudget(Budget budget, String? posteNom) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le budget ${posteNom ?? '—'} (année ${budget.annee}) ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteBudget(budget.id);
      if (mounted) showSuccess(context, 'Budget supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deleteDepense(Depense depense) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement la dépense « ${depense.motif} » ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteDepense(depense.id);
      if (mounted) showSuccess(context, 'Dépense supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _createMouvement() async {
    final montantController = TextEditingController();
    final motifController = TextEditingController();
    final referenceController = TextEditingController();
    String type = 'entree';
    await showCreateDialog(
      context: context,
      title: 'Nouveau mouvement de caisse',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String>(
          value: type,
          label: 'Type',
          options: const {'entree': 'Entrée', 'sortie': 'Sortie'},
          onChanged: (v) => type = v ?? 'entree',
        ),
        dialogTextField(
          controller: montantController,
          label: 'Montant',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(controller: motifController, label: 'Motif'),
        dialogTextField(controller: referenceController, label: 'Référence'),
      ],
      isValid: () => montantController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createCaisseMouvement(
                type: type,
                montantFcfa: int.tryParse(montantController.text.trim()) ?? 0,
                motif: motifController.text.trim(),
                reference: _opt(referenceController),
              );
          if (mounted) showSuccess(context, 'Mouvement enregistré.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Color _depenseColor(String statut) {
    switch (statut) {
      case 'payee':
        return AppTheme.bleuNuit;
      case 'validee_pasteur':
      case 'validee_tresorier':
        return AppTheme.bleuPresences;
      case 'soumise':
        return Colors.orange;
      case 'refusee':
        return AppTheme.rougeErreur;
      default:
        return Colors.grey;
    }
  }

  String _depenseLabel(String statut) {
    switch (statut) {
      case 'soumise':
        return 'Soumise';
      case 'validee_tresorier':
        return 'Validée (trésorier)';
      case 'validee_pasteur':
        return 'Validée (pasteur)';
      case 'payee':
        return 'Payée';
      case 'refusee':
        return 'Refusée';
      default:
        return statut;
    }
  }

  Widget _budgetTab() {
    final state = context.watch<AppState>();
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un poste budgétaire',
        ),
        Expanded(
          child: FutureBuilder<List<PosteBudgetaire>>(
            future: _postesFuture,
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
              final postes = snapshot.data!
                  .where((p) => _matches(p.nom))
                  .toList();
              return FutureBuilder<List<Budget>>(
                future: _budgetsFuture,
                builder: (context, budgetSnapshot) {
                  if (budgetSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const AppLoading();
                  }
                  if (budgetSnapshot.hasError) {
                    return AppError(
                      message: budgetSnapshot.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  final budgets = budgetSnapshot.data!;
                  if (postes.isEmpty && budgets.isEmpty) {
                    return EmptyState(
                      icon: Icons.account_balance_outlined,
                      message: 'Aucun poste budgétaire pour l’instant.',
                      actionLabel: 'Créer un poste budgétaire',
                      onAction: _createPoste,
                    );
                  }
                  final budgetsParPoste = <String, List<Budget>>{};
                  for (final b in budgets) {
                    budgetsParPoste.putIfAbsent(b.posteId, () => []).add(b);
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      children: [
                        const SectionTitle(title: 'Postes budgétaires'),
                        if (postes.isEmpty)
                          const EmptyState(
                            icon: Icons.account_balance_outlined,
                            message: 'Aucun poste budgétaire pour l’instant.',
                          )
                        else
                          ...postes.map((p) => Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Icon(p.categorie == 'recette'
                                        ? Icons.trending_up
                                        : Icons.trending_down),
                                  ),
                                  title: Text(p.nom),
                                  subtitle: Text([
                                    p.categorie == 'recette'
                                        ? 'Recette'
                                        : 'Dépense',
                                    if (_categorieNom(p.categorieId) != null)
                                      _categorieNom(p.categorieId)!,
                                    if (p.categorie == 'depense')
                                      p.estRecurrente
                                          ? 'Récurrente'
                                          : 'Ponctuelle',
                                    if (p.description != null)
                                      p.description!,
                                  ].join(' · ')),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (budgetsParPoste[p.id] != null)
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: budgetsParPoste[p.id]!
                                              .map((b) => Text(
                                                    '${b.annee} : ${formatMontant(b.montantPrevu, state.devise)}',
                                                    style: const TextStyle(
                                                        fontSize: 14),
                                                  ))
                                              .toList(),
                                        ),
                                      if (p.categorie == 'depense')
                                        IconButton(
                                          icon: const Icon(
                                              Icons.edit_outlined),
                                          tooltip: 'Modifier',
                                          onPressed: () =>
                                              _modifierPoste(p),
                                        ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline),
                                        tooltip: 'Supprimer',
                                        onPressed: () => _deletePoste(p),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                        const SectionTitle(title: 'Budgets'),
                        if (budgets.isEmpty)
                          const EmptyState(
                            icon: Icons.pie_chart_outline,
                            message: 'Aucun budget défini pour l’instant.',
                          )
                        else
                          ...budgets.map((b) {
                            final poste = postes
                                .where((p) => p.id == b.posteId)
                                .firstOrNull;
                            return ListTile(
                              leading: const Icon(Icons.pie_chart_outline),
                              title: Text(poste?.nom ?? 'Poste inconnu'),
                              subtitle: Text('Année ${b.annee}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formatMontant(
                                        b.montantPrevu, state.devise),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon:
                                        const Icon(Icons.delete_outline),
                                    tooltip: 'Supprimer',
                                    onPressed: () =>
                                        _deleteBudget(b, poste?.nom),
                                  ),
                                ],
                              ),
                            );
                          }),
                        const SizedBox(height: 80),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _depensesTab() {
    final state = context.watch<AppState>();
    return Column(
      children: [
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher une dépense',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in <String, String?>{
                  'Tous statuts': null,
                  'Soumises': 'soumise',
                  'Validées (trésorier)': 'validee_tresorier',
                  'Validées (pasteur)': 'validee_pasteur',
                  'Payées': 'payee',
                  'Refusées': 'refusee',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(entry.key),
                      selected: _statutDepenseFilter == entry.value,
                      onSelected: (_) {
                        setState(() {
                          _statutDepenseFilter = entry.value;
                          _depensesFuture = context
                              .read<AppState>()
                              .api
                              .getDepenses(statut: entry.value);
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Depense>>(
            future: _depensesFuture,
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
              final items = snapshot.data!
                  .where((d) => _matches(d.motif))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: snapshot.data!.isEmpty
                      ? 'Aucune dépense enregistrée pour l’instant.'
                      : 'Aucune dépense ne correspond à la recherche.',
                  actionLabel: 'Enregistrer une dépense',
                  onAction: () async {
                    try {
                      final postes = await _postesFuture;
                      if (mounted) await _createDepense(postes);
                    } catch (e) {
                      if (context.mounted) showApiError(context, e);
                    }
                  },
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final d = items[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long_outlined),
                        ),
                        title: Text(
                            '${d.motif} — ${formatMontant(d.montantFcfa, state.devise)}'),
                        subtitle: Text(
                          '${d.reference ?? 'Sans référence'} · ${afficherDate(d.dateDepense)}'
                          '${d.justificatifRef != null ? ' · Justificatif ${d.justificatifRef}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusChip(
                              label: _depenseLabel(d.statut),
                              color: _depenseColor(d.statut),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Supprimer',
                              onPressed: () => _deleteDepense(d),
                            ),
                          ],
                        ),
                        onTap: () async {
                          final actions = <Widget>[];
                          if (d.statut == 'soumise') {
                            actions.add(TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _setDepenseStatut(d, 'validee_tresorier');
                              },
                              child: const Text('Valider (trésorier)'),
                            ));
                            actions.add(TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _setDepenseStatut(d, 'refusee');
                              },
                              child: const Text('Refuser'),
                            ));
                          }
                          if (d.statut == 'validee_tresorier') {
                            actions.add(TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _setDepenseStatut(d, 'validee_pasteur');
                              },
                              child: const Text('Valider (pasteur)'),
                            ));
                            actions.add(TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _setDepenseStatut(d, 'refusee');
                              },
                              child: const Text('Refuser'),
                            ));
                          }
                          if (d.statut == 'validee_pasteur') {
                            actions.add(TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _setDepenseStatut(d, 'payee');
                              },
                              child: const Text('Marquer payée'),
                            ));
                          }
                          if (actions.isEmpty) return;
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(d.motif),
                              content: Text([
                                'Statut : ${_depenseLabel(d.statut)}',
                                if (d.reference != null)
                                  'Référence : ${d.reference}',
                                'Montant : ${formatMontant(d.montantFcfa, state.devise)}',
                                if (_departementNom(d.departementId) != null)
                                  'Département : ${_departementNom(d.departementId)}',
                                'Paiement : ${d.modePaiementLabel}',
                                if (d.fournisseurBeneficiaire != null)
                                  'Fournisseur : ${d.fournisseurBeneficiaire}',
                                if (d.responsableDepense != null)
                                  'Effectuée par : ${d.responsableDepense}',
                                if (d.responsableAutorisation != null)
                                  'Autorisée par : ${d.responsableAutorisation}',
                                if (d.devise != null)
                                  'Devise : ${d.devise}',
                              ].join('\n')),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(),
                                  child: const Text('Fermer'),
                                ),
                                ...actions,
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _caisseTab() {
    final state = context.watch<AppState>();
    return Column(
      children: [
        FutureBuilder<CaisseSolde>(
          future: _soldeFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: AppLoading(),
              );
            }
            if (snapshot.hasError) {
              return AppError(
                message: snapshot.error.toString(),
                onRetry: _refresh,
              );
            }
            final solde = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount =
                      constraints.maxWidth > 600 ? 3 : 2;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      StatCard(
                        label: 'Solde de caisse',
                        value: formatMontant(solde.solde, state.devise),
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      StatCard(
                        label: 'Entrées',
                        value: formatMontant(solde.entrees, state.devise),
                        icon: Icons.trending_up,
                        color: AppTheme.bleuNuit,
                      ),
                      StatCard(
                        label: 'Sorties',
                        value: formatMontant(solde.sorties, state.devise),
                        icon: Icons.trending_down,
                        color: AppTheme.rougeErreur,
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        searchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          label: 'Rechercher un mouvement',
        ),
        Expanded(
          child: FutureBuilder<List<CaisseMouvement>>(
            future: _mouvementsFuture,
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
              final items = snapshot.data!
                  .where((m) => _matches(m.motif))
                  .toList();
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.swap_horiz,
                  message: snapshot.data!.isEmpty
                      ? 'Aucun mouvement de caisse pour l’instant.'
                      : 'Aucun mouvement ne correspond à la recherche.',
                  actionLabel: 'Enregistrer un mouvement',
                  onAction: _createMouvement,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final m = items[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(m.type == 'entree'
                            ? Icons.add
                            : Icons.remove),
                      ),
                      title: Text(
                          '${m.type == 'entree' ? 'Entrée' : 'Sortie'} — ${formatMontant(m.montantFcfa, state.devise)}'),
                      subtitle: Text(
                        '${m.motif}${m.reference != null ? ' · ${m.reference}' : ''} · ${afficherDateTime(m.createdAt)}',
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Export PDF des finances pour l'année affichée : le détail couvre
  /// toute l'année (1er janvier au 31 décembre), le résumé reprend les
  /// totaux du rapport (par mois, par poste, par branche). Partage par le
  /// même mécanisme que les attestations (SharePlus). Admin et trésorier
  /// seulement, le serveur refuse le reste (403).
  Future<void> _exporterFinancesPdf({required bool detail}) async {
    final annee =
        int.tryParse(_anneeController.text.trim()) ?? DateTime.now().year;
    try {
      final bytes = detail
          ? await context.read<AppState>().api.exporterFinancesDetailPdf(
                from: '$annee-01-01',
                to: '$annee-12-31',
              )
          : await context
              .read<AppState>()
              .api
              .exporterFinancesResumePdf(annee: annee);
      final nom =
          detail ? 'finances-detail-$annee.pdf' : 'finances-resume-$annee.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: nom, mimeType: 'application/pdf'),
          ],
          subject: detail
              ? 'Détail des finances $annee'
              : 'Résumé des finances $annee',
        ),
      );
      if (mounted) showSuccess(context, 'Export PDF partagé.');
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _rapportTab() {
    final state = context.watch<AppState>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _anneeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Année',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _rapportFuture = context
                        .read<AppState>()
                        .api
                        .getRapportFinancier(
                          annee: int.tryParse(_anneeController.text.trim()),
                        );
                  });
                },
                child: const Text('Afficher'),
              ),
            ],
          ),
        ),
        if (state.canManageFinances)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _exporterFinancesPdf(detail: true),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Détail (PDF)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _exporterFinancesPdf(detail: false),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Résumé (PDF)'),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _rapportFuture == null
              ? const EmptyState(
                  icon: Icons.assessment_outlined,
                  message: 'Choisissez une année puis affichez le rapport financier.',
                )
              : FutureBuilder<RapportFinancier>(
                  future: _rapportFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const AppLoading();
                    }
                    if (snapshot.hasError) {
                      return AppError(
                        message: snapshot.error.toString(),
                        onRetry: () => setState(() {
                          _rapportFuture = context
                              .read<AppState>()
                              .api
                              .getRapportFinancier(
                                annee: int.tryParse(
                                    _anneeController.text.trim()),
                              );
                        }),
                      );
                    }
                    final rapport = snapshot.data!;
                    return RefreshIndicator(
                      onRefresh: () async => setState(() {
                        _rapportFuture = context
                            .read<AppState>()
                            .api
                            .getRapportFinancier(
                              annee: int.tryParse(
                                  _anneeController.text.trim()),
                            );
                      }),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const SectionTitle(title: 'Par mois'),
                          if (rapport.parMois.isEmpty)
                            const EmptyState(
                              icon: Icons.calendar_month_outlined,
                              message:
                                  'Aucune contribution confirmée sur cette période.',
                            )
                          else
                            ...rapport.parMois.map((l) {
                              final total =
                                  (l['total_fcfa'] as num?)?.toInt() ?? 0;
                              final nombre =
                                  (l['nombre'] as num?)?.toInt() ?? 0;
                              return ListTile(
                                leading: const Icon(
                                    Icons.calendar_month_outlined),
                                title: Text(
                                    '${l['mois'] ?? '—'} — ${l['type'] ?? ''}'),
                                trailing: Text(
                                  formatMontant(total, state.devise),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle:
                                    Text(pluriel(nombre, 'contribution')),
                              );
                            }),
                          const SectionTitle(title: 'Par poste'),
                          if (rapport.parPoste.isEmpty)
                            const EmptyState(
                              icon: Icons.account_balance_outlined,
                              message: 'Aucun poste budgétaire pour l’instant.',
                            )
                          else
                            ...rapport.parPoste.map((l) {
                              final budget =
                                  (l['budget_fcfa'] as num?)?.toInt() ?? 0;
                              final realise =
                                  (l['realise_fcfa'] as num?)?.toInt() ?? 0;
                              return ListTile(
                                leading: const Icon(
                                    Icons.account_balance_outlined),
                                title: Text('${l['poste'] ?? '—'}'),
                                subtitle: Text(
                                    'Budget : ${formatMontant(budget, state.devise)}'),
                                trailing: Text(
                                  'Réalisé : ${formatMontant(realise, state.devise)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              );
                            }),
                          const SectionTitle(title: 'Par branche'),
                          if (rapport.parBranche.isEmpty)
                            const EmptyState(
                              icon: Icons.account_tree_outlined,
                              message:
                                  'Aucune sous-église rattachée pour l’instant.',
                            )
                          else
                            ...rapport.parBranche.map((b) {
                              final total =
                                  (b['total_fcfa'] as num?)?.toInt() ?? 0;
                              final membres =
                                  (b['membres_actifs'] as num?)?.toInt() ?? 0;
                              final contributions = (b['nombre_contributions']
                                          as num?)
                                      ?.toInt() ??
                                  0;
                              return ListTile(
                                leading: const Icon(
                                    Icons.account_tree_outlined),
                                title: Text('${b['eglise_nom'] ?? '—'}'),
                                subtitle: Text(
                                    '${pluriel(membres, 'membre actif', 'membres actifs')} · ${pluriel(contributions, 'contribution')}'),
                                trailing: Text(
                                  formatMontant(total, state.devise),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              );
                            }),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SectionTitle(title: 'Déclarations et exports'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'États financiers SYCEBNL',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Bilan, compte de résultat, tableau des flux de trésorerie et notes annexes, à produire depuis votre comptabilité. L\'export reste disponible pour toutes les églises, même quand le dépôt n\'est pas imposé.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SycebnlScreen(),
                          ),
                        );
                      },
                      child: const Text('Ouvrir l\'export SYCEBNL'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Suivi mensuel du plan comptable : prévu contre réel par catégorie
  /// et par poste, alerte visible en cas de dépassement, budgets mensuels
  /// du mois et exports du rapport mensuel ou annuel en PDF et Excel.
  Widget _suiviTab() {
    final state = context.watch<AppState>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: dialogDropdown<int>(
                  value: _moisSuivi,
                  label: 'Mois',
                  options: {
                    for (var m = 1; m <= 12; m++) m: _nomsMois[m - 1],
                  },
                  onChanged: (v) => setState(
                      () => _moisSuivi = v ?? DateTime.now().month),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _anneeSuiviController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Année',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _anneeSuivi =
                          int.tryParse(_anneeSuiviController.text.trim()) ??
                              DateTime.now().year;
                    });
                    _refresh();
                  },
                  child: const Text('Afficher'),
                ),
              ),
            ],
          ),
        ),
        if (state.canManageFinances)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exporterRapportDepenses(
                            mensuel: true, excel: false),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Mensuel (PDF)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exporterRapportDepenses(
                            mensuel: true, excel: true),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Mensuel (Excel)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exporterRapportDepenses(
                            mensuel: false, excel: false),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Annuel (PDF)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exporterRapportDepenses(
                            mensuel: false, excel: true),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Annuel (Excel)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<SuiviMensuel>(
            future: _suiviFuture,
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
              final suivi = snapshot.data!;
              Widget ligneSuivi(SuiviMensuelLigne ligne, {bool poste = false}) {
                return ListTile(
                  leading: Icon(poste
                      ? Icons.account_balance_outlined
                      : Icons.category_outlined),
                  title: Text(ligne.libelle),
                  subtitle: Text(
                    'Prévu : ${formatMontant(ligne.prevuFcfa, state.devise)}'
                    '${poste && ligne.recurrente != null ? ' · ${ligne.recurrente! ? 'Récurrente' : 'Ponctuelle'}' : ''}'
                    '${!ligne.budgetDefini ? ' · Sans budget mensuel' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatMontant(ligne.reelFcfa, state.devise),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (ligne.depassement) ...[
                        const SizedBox(width: 8),
                        const StatusChip(
                          label: 'Dépassement',
                          color: AppTheme.rougeErreur,
                        ),
                      ],
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.assessment_outlined),
                        title: Text(
                            '${_nomsMois[suivi.mois - 1]} ${suivi.annee}'),
                        subtitle: Text(
                          'Prévu : ${formatMontant(suivi.totalPrevuFcfa, state.devise)}'
                          ' · Réel : ${formatMontant(suivi.totalReelFcfa, state.devise)}',
                        ),
                      ),
                    ),
                    const SectionTitle(title: 'Par catégorie'),
                    if (suivi.parCategories.isEmpty)
                      const EmptyState(
                        icon: Icons.category_outlined,
                        message: 'Aucun poste de dépense pour l’instant.',
                      )
                    else
                      ...suivi.parCategories.map((l) => ligneSuivi(l)),
                    const SectionTitle(title: 'Par poste'),
                    if (suivi.parPostes.isEmpty)
                      const EmptyState(
                        icon: Icons.account_balance_outlined,
                        message: 'Aucun poste de dépense pour l’instant.',
                      )
                    else
                      ...suivi.parPostes
                          .map((l) => ligneSuivi(l, poste: true)),
                    const SectionTitle(title: 'Budgets mensuels'),
                    FutureBuilder<List<BudgetMensuel>>(
                      future: _budgetsMensuelsFuture,
                      builder: (context, budgetSnapshot) {
                        if (budgetSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const AppLoading();
                        }
                        if (budgetSnapshot.hasError) {
                          return AppError(
                            message: budgetSnapshot.error.toString(),
                            onRetry: _refresh,
                          );
                        }
                        final budgets = budgetSnapshot.data!;
                        if (budgets.isEmpty) {
                          return const EmptyState(
                            icon: Icons.calendar_month_outlined,
                            message:
                                'Aucun budget mensuel pour ce mois.',
                          );
                        }
                        return FutureBuilder<List<PosteBudgetaire>>(
                          future: _postesFuture,
                          builder: (context, posteSnapshot) {
                            final postes = posteSnapshot.data ?? [];
                            String nomPoste(String posteId) => postes
                                .where((p) => p.id == posteId)
                                .firstOrNull
                                ?.nom ??
                                'Poste inconnu';
                            return Column(
                              children: budgets
                                  .map((b) => ListTile(
                                        leading: const Icon(
                                            Icons.calendar_month_outlined),
                                        title: Text(nomPoste(b.posteId)),
                                        subtitle: Text(
                                            '${_nomsMois[b.mois - 1]} ${b.annee}'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              formatMontant(
                                                  b.montantPrevu,
                                                  state.devise),
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              tooltip: 'Supprimer',
                                              onPressed: () =>
                                                  _deleteBudgetMensuel(
                                                      b, nomPoste(b.posteId)),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Budget & caisse'),
          bottom: TabBar(
            onTap: (i) => setState(() {
              _tab = i;
              _query = '';
              _searchController.clear();
            }),
            tabs: const [
              Tab(text: 'Budget'),
              Tab(text: 'Dépenses'),
              Tab(text: 'Caisse'),
              Tab(text: 'Rapport'),
              Tab(text: 'Suivi mensuel'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _budgetTab(),
            _depensesTab(),
            _caisseTab(),
            _rapportTab(),
            _suiviTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              if (_tab == 0) {
                await _createPoste();
              } else if (_tab == 1) {
                final postes = await _postesFuture;
                if (mounted) await _createDepense(postes);
              } else if (_tab == 2) {
                await _createMouvement();
              } else if (_tab == 3) {
                final postes = await _postesFuture;
                if (mounted) await _createBudget(postes);
              } else {
                final postes = await _postesFuture;
                if (mounted) await _createBudgetMensuel(postes);
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_tab == 0
              ? 'Poste'
              : _tab == 1
                  ? 'Dépense'
                  : _tab == 2
                      ? 'Mouvement'
                      : _tab == 3
                          ? 'Budget'
                          : 'Budget mensuel'),
        ),
      ),
    );
  }
}
