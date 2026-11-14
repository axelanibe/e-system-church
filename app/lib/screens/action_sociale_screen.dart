import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/gouvernance.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// T10 — Action sociale : bénéficiaires et suivi des aides
/// (vivres, financière, médicale, autre).
class ActionSocialeScreen extends StatefulWidget {
  const ActionSocialeScreen({super.key});

  @override
  State<ActionSocialeScreen> createState() => _ActionSocialeScreenState();
}

class _ActionSocialeScreenState extends State<ActionSocialeScreen> {
  int _tab = 0;
  late Future<List<Beneficiaire>> _beneficiairesFuture;
  late Future<List<Aide>> _aidesFuture;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppState>().api;
    _beneficiairesFuture = api.getBeneficiaires();
    _aidesFuture = api.getAides();
    _membresFuture = api.getMembers();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _beneficiairesFuture = api.getBeneficiaires();
      _aidesFuture = api.getAides();
    });
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _createBeneficiaire(List<Member> membres) async {
    final nomController = TextEditingController();
    final telephoneController = TextEditingController();
    final adresseController = TextEditingController();
    final besoinController = TextEditingController();
    String? memberId;
    await showCreateDialog(
      context: context,
      title: 'Nouveau bénéficiaire',
      saveLabel: 'Créer',
      fields: [
        dialogTextField(controller: nomController, label: 'Nom'),
        dialogTextField(
          controller: telephoneController,
          label: 'Téléphone',
          keyboardType: TextInputType.phone,
        ),
        dialogTextField(controller: adresseController, label: 'Adresse'),
        dialogTextField(
          controller: besoinController,
          label: 'Besoin',
          maxLines: 3,
        ),
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre concerné',
          options: {
            null: 'Non membre',
            for (final m in membres) m.id: '${m.fullName} (${m.matricule})',
          },
          onChanged: (v) => memberId = v,
        ),
      ],
      isValid: () => nomController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createBeneficiaire(
                nom: nomController.text.trim(),
                telephone: _opt(telephoneController),
                adresse: _opt(adresseController),
                besoin: _opt(besoinController),
                memberId: memberId,
              );
          if (mounted) showSuccess(context, 'Bénéficiaire créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _createAide(List<Beneficiaire> beneficiaires) async {
    String? beneficiaireId =
        beneficiaires.isEmpty ? null : beneficiaires.first.id;
    String typeAide = 'vivres';
    final montantController = TextEditingController();
    final dateController = TextEditingController();
    final descriptionController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Nouvelle aide',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: beneficiaireId,
          label: 'Bénéficiaire',
          options: {
            for (final b in beneficiaires) b.id: b.nom,
          },
          onChanged: (v) => beneficiaireId = v,
        ),
        dialogDropdown<String>(
          value: typeAide,
          label: 'Type d’aide',
          options: const {
            'vivres': 'Vivres',
            'financier': 'Financière',
            'medical': 'Médicale',
            'autre': 'Autre',
          },
          onChanged: (v) => typeAide = v ?? 'vivres',
        ),
        dialogTextField(
          controller: montantController,
          label: 'Montant (FCFA)',
          keyboardType: TextInputType.number,
        ),
        dialogDateField(
          context: context,
          controller: dateController,
          label: 'Date de l’aide',
        ),
        dialogTextField(
          controller: descriptionController,
          label: 'Description',
          maxLines: 3,
        ),
      ],
      isValid: () => beneficiaireId != null,
      onSave: () async {
        try {
          await context.read<AppState>().api.createAide(
                beneficiaireId: beneficiaireId!,
                typeAide: typeAide,
                montantFcfa: int.tryParse(montantController.text.trim()),
                dateAide: _opt(dateController),
                description: _opt(descriptionController),
              );
          if (mounted) showSuccess(context, 'Aide créée.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _marquerVersee(Aide aide) async {
    try {
      await context.read<AppState>().api.marquerAideVersee(aide.id);
      if (mounted) showSuccess(context, 'Aide marquée versée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimerBeneficiaire(Beneficiaire beneficiaire) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le bénéficiaire « ${beneficiaire.nom} » ? Ses aides seront aussi supprimées.',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteBeneficiaire(beneficiaire.id);
      if (mounted) showSuccess(context, 'Bénéficiaire supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimerAide(Aide aide) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement cette aide ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteAide(aide.id);
      if (mounted) showSuccess(context, 'Aide supprimée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _beneficiairesTab() {
    return FutureBuilder<List<Beneficiaire>>(
      future: _beneficiairesFuture,
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
        final items = snapshot.data!;
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.volunteer_activism_outlined,
            message: 'Aucun bénéficiaire pour l’instant.',
            actionLabel: 'Ajouter un bénéficiaire',
            onAction: () async {
              try {
                final membres = (await _membresFuture).membres;
                if (mounted) await _createBeneficiaire(membres);
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
              final b = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.volunteer_activism_outlined),
                ),
                title: Text(b.nom),
                subtitle: Text(
                  '${b.besoin ?? 'Besoin à compléter'}'
                  '${b.telephone != null ? ' · ${b.telephone}' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: b.statutLabel,
                      color: b.statut == 'clos'
                          ? Colors.grey
                          : AppTheme.violetProfond,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimerBeneficiaire(b),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _aidesTab(Map<String, String> beneficiairesNoms) {
    return FutureBuilder<List<Aide>>(
      future: _aidesFuture,
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
        final items = snapshot.data!;
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.handshake_outlined,
            message: 'Aucune aide enregistrée pour l’instant.',
            actionLabel: 'Enregistrer une aide',
            onAction: () async {
              try {
                final beneficiaires = await _beneficiairesFuture;
                if (mounted) await _createAide(beneficiaires);
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
              final a = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.handshake_outlined),
                ),
                title: Text(
                    beneficiairesNoms[a.beneficiaireId] ?? 'Bénéficiaire'),
                subtitle: Text(
                  '${a.typeLabel}'
                  '${a.montantFcfa != null ? ' · ${formatMontant(a.montantFcfa!, context.watch<AppState>().devise)}' : ''}'
                  '${a.dateAide != null ? ' · ${afficherDate(a.dateAide)}' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: a.statutLabel,
                      color: a.statut == 'annulee'
                          ? AppTheme.rougeErreur
                          : AppTheme.violetProfond,
                    ),
                    if (a.statut == 'prevue')
                      IconButton(
                        icon: const Icon(Icons.check_outlined),
                        tooltip: 'Marquer versée',
                        onPressed: () => _marquerVersee(a),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimerAide(a),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Action sociale'),
          bottom: TabBar(
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Bénéficiaires'),
              Tab(text: 'Aides'),
            ],
          ),
        ),
        body: FutureBuilder<List<Beneficiaire>>(
          future: _beneficiairesFuture,
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
            final noms = {
              for (final b in snapshot.data!) b.id: b.nom,
            };
            return TabBarView(
              children: [
                _beneficiairesTab(),
                _aidesTab(noms),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            try {
              if (_tab == 0) {
                final membres = (await _membresFuture).membres;
                if (mounted) await _createBeneficiaire(membres);
              } else {
                final beneficiaires = await _beneficiairesFuture;
                if (mounted) await _createAide(beneficiaires);
              }
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Ajouter'),
        ),
      ),
    );
  }
}
