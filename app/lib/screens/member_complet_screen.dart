import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../models/membres_complement.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Fiche enrichie d'un membre : identité, historique des statuts, baptême,
/// départements, cellules et liens parent-enfant. Permet de changer de
/// statut et d'ajouter un baptême.
class MemberCompletScreen extends StatefulWidget {
  final String memberId;

  const MemberCompletScreen({super.key, required this.memberId});

  @override
  State<MemberCompletScreen> createState() => _MemberCompletScreenState();
}

T _as<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  if (value is T) return value;
  return fromJson(value as Map<String, dynamic>);
}

List<T> _asList<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  final list = value as List? ?? const [];
  return list.map((e) => _as<T>(e, fromJson)).toList();
}

class _MemberCompletScreenState extends State<MemberCompletScreen> {
  late Future<Map<String, dynamic>> _future;
  late Future<MemberPage> _membresFuture;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _membresFuture = context.read<AppState>().api.getMembers();
  }

  Future<Map<String, dynamic>> _load() {
    return context.read<AppState>().api.getMembreComplet(widget.memberId);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _changerStatut(Member membre) async {
    String statut = 'membre';
    final motifController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Changer de statut',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDropdown<String>(
          value: statut,
          label: 'Nouveau statut',
          options: const {
            'membre': 'Membre',
            'sympathisant': 'Sympathisant',
            'nouveau_converti': 'Nouveau converti',
            'en_formation': 'En formation',
            'suspendu': 'Suspendu',
            'parti': 'Parti',
          },
          onChanged: (v) => statut = v ?? 'membre',
        ),
        dialogTextField(controller: motifController, label: 'Motif'),
      ],
      isValid: () => true,
      onSave: () async {
        try {
          await context.read<AppState>().api.changerStatutMembre(
                membre.id,
                statut: statut,
                motif: motifController.text.trim().isEmpty
                    ? null
                    : motifController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Statut mis à jour.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _ajouterBapteme(Member membre) async {
    final dateController = TextEditingController();
    final lieuController = TextEditingController();
    final pasteurController = TextEditingController();
    final certificatController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: 'Ajouter un baptême',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDateField(
            context: context, controller: dateController, label: 'Date du baptême'),
        dialogTextField(controller: lieuController, label: 'Lieu'),
        dialogTextField(controller: pasteurController, label: 'Pasteur'),
        dialogTextField(
            controller: certificatController, label: 'N° de certificat'),
      ],
      isValid: () => dateController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createBapteme(
                memberId: membre.id,
                dateBapteme: dateController.text.trim(),
                lieu: lieuController.text.trim().isEmpty
                    ? null
                    : lieuController.text.trim(),
                pasteur: pasteurController.text.trim().isEmpty
                    ? null
                    : pasteurController.text.trim(),
                certificatNumero: certificatController.text.trim().isEmpty
                    ? null
                    : certificatController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Baptême enregistré.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche complète')),
      body: FutureBuilder<Map<String, dynamic>>(
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
          final data = snapshot.data!;
          final membre = _as<Member>(data['membre'], Member.fromJson);
          final statuts = _asList<MembreStatut>(
              data['historique_statuts'], MembreStatut.fromJson);
          final bapteme = data['bapteme'] == null
              ? null
              : _as<Bapteme>(data['bapteme'], Bapteme.fromJson);
          final departements = _asList<Departement>(
              data['departements'], Departement.fromJson);
          final cellules =
              _asList<Cellule>(data['cellules'], Cellule.fromJson);
          final enfants = _asList<LienParentEnfant>(
              data['enfants'], LienParentEnfant.fromJson);
          final parents = _asList<LienParentEnfant>(
              data['parents'], LienParentEnfant.fromJson);

          return FutureBuilder<MemberPage>(
            future: _membresFuture,
            builder: (context, membresSnapshot) {
              final noms = {
                for (final m in membresSnapshot.data?.membres ?? const <Member>[])
                  m.id: m.fullName
              };
              return _buildBody(
                context,
                membre: membre,
                statuts: statuts,
                bapteme: bapteme,
                departements: departements,
                cellules: cellules,
                enfants: enfants,
                parents: parents,
                noms: noms,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required Member membre,
    required List<MembreStatut> statuts,
    required Bapteme? bapteme,
    required List<Departement> departements,
    required List<Cellule> cellules,
    required List<LienParentEnfant> enfants,
    required List<LienParentEnfant> parents,
    required Map<String, String> noms,
  }) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(membre.fullName.isNotEmpty
                          ? membre.fullName[0].toUpperCase()
                          : '?'),
                    ),
                    title: Text(membre.fullName),
                    subtitle: Text(
                      '${membre.matricule} · ${membre.statusLabel}'
                      '${membre.department != null ? ' · ${membre.department}' : ''}'
                      '${membre.fonction != null ? ' · ${membre.fonctionAffichee}' : ''}'
                      '${membre.poste != null ? ' · ${membre.poste}' : ''}'
                      '${membre.cellGroup != null ? ' · ${membre.cellGroup}' : ''}',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _changerStatut(membre),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Changer de statut'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _ajouterBapteme(membre),
                        icon: const Icon(Icons.water_drop_outlined),
                        label: const Text('Ajouter un baptême'),
                      ),
                    ),
                  ],
                ),
                const SectionTitle(title: 'Historique des statuts'),
                if (statuts.isEmpty)
                  const EmptyState(
                    icon: Icons.history,
                    message: 'Aucun changement de statut enregistré.',
                  )
                else
                  ...statuts.map((s) => ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(s.statutLabel),
                        subtitle: Text(
                            '${s.ancienStatut != null ? '${MembreStatut.labelForStatut(s.ancienStatut!)} → ' : ''}${s.statutLabel}${s.motif != null ? ' · ${s.motif}' : ''}'),
                        trailing: Text(afficherDate(s.createdAt)),
                      )),
                const SectionTitle(title: 'Baptême'),
                if (bapteme == null)
                  const EmptyState(
                    icon: Icons.water_drop_outlined,
                    message: 'Aucun baptême enregistré pour ce membre.',
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.water_drop_outlined),
                    title: Text(afficherDate(bapteme.dateBapteme)),
                    subtitle: Text(
                        '${bapteme.lieu ?? '—'} · ${bapteme.pasteur ?? '—'}${bapteme.certificatNumero != null ? ' · Certificat ${bapteme.certificatNumero}' : ''}'),
                  ),
                const SectionTitle(title: 'Départements'),
                if (departements.isEmpty)
                  const EmptyState(
                    icon: Icons.group_work_outlined,
                    message: 'Ce membre n’appartient à aucun département.',
                  )
                else
                  ...departements.map((d) => ListTile(
                        leading: const Icon(Icons.group_work_outlined),
                        title: Text(d.nom),
                        subtitle:
                            Text(d.description ?? 'Aucune description.'),
                      )),
                const SectionTitle(title: 'Cellules'),
                if (cellules.isEmpty)
                  const EmptyState(
                    icon: Icons.groups_outlined,
                    message: 'Ce membre n’appartient à aucune cellule.',
                  )
                else
                  ...cellules.map((c) => ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(c.nom),
                        subtitle: Text(
                            '${c.quartier ?? '—'}${c.jourReunion != null ? ' · ${c.jourReunion}' : ''}${c.heureReunion != null ? ' à ${c.heureReunion}' : ''}'),
                      )),
                const SectionTitle(title: 'Liens parent – enfant'),
                if (enfants.isEmpty && parents.isEmpty)
                  const EmptyState(
                    icon: Icons.family_restroom_outlined,
                    message: 'Aucun lien parent-enfant enregistré.',
                  )
                else ...[
                  ...enfants.map((l) => ListTile(
                        leading: const Icon(Icons.child_care_outlined),
                        title: Text(
                            'Enfant : ${noms[l.enfantMemberId] ?? l.enfantMemberId}'),
                        subtitle: Text('Lien : ${l.lienLabel}'),
                      )),
                  ...parents.map((l) => ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                            'Parent : ${noms[l.parentMemberId] ?? l.parentMemberId}'),
                        subtitle: Text('Lien : ${l.lienLabel}'),
                      )),
                ],
              ],
            ),
          );
  }
}
