import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/periodes.dart';
import '../widgets/common_widgets.dart';
import 'contribution_form_screen.dart';

/// Cotisations de l'église (tranche T7) : montant fixé par l'église,
/// suivi payé et reste par membre, pour la période. Le suivi est calculé
/// par le serveur depuis les contributions confirmées de type
/// « cotisation » : pas de double comptabilité. Saisie admin et
/// trésorier ; lecture admin, trésorier et responsable de culte.
class CotisationsAdminScreen extends StatefulWidget {
  const CotisationsAdminScreen({super.key});

  @override
  State<CotisationsAdminScreen> createState() =>
      _CotisationsAdminScreenState();
}

class _CotisationsAdminScreenState extends State<CotisationsAdminScreen> {
  late Future<SuiviCotisations> _future;
  String? _periode;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<SuiviCotisations> _charger() =>
      context.read<AppState>().api.getCotisationsSuivi(periode: _periode);

  void _refresh() => setState(() => _future = _charger());

  /// Période affichée : mois (AAAA-MM) pour une cotisation mensuelle,
  /// année (AAAA) pour une cotisation annuelle.
  void _periodePrecedente(String periodeActuelle, bool annuelle) {
    setState(() {
      _periode = annuelle
          ? anneePrecedente(periodeActuelle)
          : moisPrecedent(periodeActuelle);
      _future = _charger();
    });
  }

  void _periodeSuivante(String periodeActuelle, bool annuelle) {
    setState(() {
      _periode = annuelle
          ? anneeSuivante(periodeActuelle)
          : moisSuivant(periodeActuelle);
      _future = _charger();
    });
  }

  Future<void> _modifierConfig(CotisationConfig? actuelle) async {
    final montantController = TextEditingController(
        text: actuelle == null ? '' : '${actuelle.montantFcfa}');
    var periodicite = actuelle?.periodicite ?? 'mensuelle';
    var actif = actuelle?.actif ?? true;
    final formKey = GlobalKey<FormState>();
    final enregistre = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(actuelle == null
              ? 'Fixer la cotisation'
              : 'Modifier la cotisation'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: montantController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Montant (FCFA) *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final montant = int.tryParse(v?.trim() ?? '');
                    if (montant == null || montant <= 0) {
                      return 'Montant invalide.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: periodicite,
                  decoration: const InputDecoration(
                    labelText: 'Périodicité',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'mensuelle', child: Text('Mensuelle')),
                    DropdownMenuItem(
                        value: 'annuelle', child: Text('Annuelle')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => periodicite = v ?? 'mensuelle'),
                ),
                SwitchListTile(
                  title: const Text('Cotisation active'),
                  value: actif,
                  onChanged: (v) => setDialogState(() => actif = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await context.read<AppState>().api.saveCotisationsConfig(
                        montantFcfa:
                            int.parse(montantController.text.trim()),
                        periodicite: periodicite,
                        actif: actif,
                      );
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (e) {
                  if (context.mounted) showApiError(context, e);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    montantController.dispose();
    if (enregistre == true && mounted) {
      // Un changement de périodicité change le format de période :
      // on repart de la période en cours.
      setState(() => _periode = null);
      _refresh();
      showSuccess(context, 'Cotisation enregistrée.');
    }
  }

  Future<void> _nouvelleCotisation() async {
    final cree = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            const ContributionFormScreen(initialType: 'cotisation'),
      ),
    );
    if (cree != null && mounted) {
      showSuccess(context, 'Cotisation enregistrée (en attente).');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.canReadFinances) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cotisations')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message: 'Votre rôle ne donne pas accès aux finances de l’église.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Cotisations')),
      body: FutureBuilder<SuiviCotisations>(
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
          final suivi = snapshot.data!;
          final config = suivi.config;
          final annuelle = config?.periodicite == 'annuelle';
          final periode = suivi.periode;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Montant fixé par l’église',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (state.canManageFinances)
                              OutlinedButton(
                                onPressed: () => _modifierConfig(config),
                                child: Text(config == null
                                    ? 'Fixer le montant'
                                    : 'Modifier'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (config == null)
                          const Text(
                            'Aucune cotisation configurée pour le moment : fixez un montant pour suivre les paiements par membre.',
                          )
                        else ...[
                          Text(
                            formatMontant(config.montantFcfa, state.devise),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Text(
                            'Par membre, ${config.periodiciteLabel.toLowerCase()}${config.actif ? '' : ' · inactive'}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () =>
                          _periodePrecedente(periode, annuelle),
                      tooltip: 'Période précédente',
                    ),
                    Text(
                      annuelle
                          ? periode
                          : libellePeriodeMois(periode),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () =>
                          _periodeSuivante(periode, annuelle),
                      tooltip: 'Période suivante',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
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
                          label: 'Total dû',
                          value: formatMontant(
                              suivi.totaux.totalDuFcfa, state.devise),
                          icon: Icons.payments_outlined,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'Total payé',
                          value: formatMontant(
                              suivi.totaux.totalPayeFcfa, state.devise),
                          icon: Icons.trending_up,
                          color: AppTheme.bleuNuit,
                        ),
                        StatCard(
                          label: 'Reste à payer',
                          value: formatMontant(
                              suivi.totaux.totalResteFcfa, state.devise),
                          icon: Icons.trending_down,
                          color: AppTheme.rougeErreur,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '${pluriel(suivi.totaux.membresPayes, 'membre payé', 'membres payés')} sur ${suivi.totaux.membresTotal}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                // Sans montant fixé, la carte du haut l'explique déjà :
                // la section Par membre n'apparaît qu'avec une config.
                if (!suivi.configAbsente) ...[
                  const SectionTitle(title: 'Par membre'),
                  if (suivi.membres.isEmpty)
                    const EmptyState(
                      icon: Icons.payments_outlined,
                      message: 'Aucun membre actif pour cette période.',
                    )
                  else
                    ...suivi.membres.map(
                      (ligne) => LigneCotisationTile(
                        ligne: ligne,
                        devise: state.devise,
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: state.canManageFinances
          ? FloatingActionButton.extended(
              onPressed: _nouvelleCotisation,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle cotisation'),
            )
          : null,
    );
  }
}

/// Une ligne du suivi des cotisations : nom, matricule, dû, payé,
/// reste, et statut (Payée, Partielle, Impayée).
class LigneCotisationTile extends StatelessWidget {
  final LigneCotisation ligne;
  final String devise;

  const LigneCotisationTile({
    super.key,
    required this.ligne,
    required this.devise,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = switch (ligne.statut) {
      'payee' => AppTheme.bleuNuit,
      'partielle' => Colors.orange,
      _ => AppTheme.rougeErreur,
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(ligne.membreNom),
        subtitle: Text(
          [
            if (ligne.membreMatricule != null) ligne.membreMatricule!,
            'Dû : ${formatMontant(ligne.montantDuFcfa, devise)}',
            'Payé : ${formatMontant(ligne.montantPayeFcfa, devise)}',
            'Reste : ${formatMontant(ligne.resteFcfa, devise)}',
          ].join(' · '),
        ),
        trailing: StatusChip(
          label: ligne.statutLabel,
          color: couleur,
        ),
      ),
    );
  }
}
