import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/frequentation.dart';
import '../models/member.dart';
import '../models/membres_complement.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'member_form_screen.dart';

/// Fiche unique d'un membre, en cartes séparées : carte avec QR, informations,
/// parcours (conversion, baptême, mariage), historique des statuts,
/// départements, cellules, liens parent-enfant et fréquentation (admin
/// seulement). En [lectureSeule] (le fidèle qui regarde sa propre carte),
/// aucun bouton de modification ni de suppression : la carte se regarde,
/// elle ne s'administre pas depuis ici. La photo n'apparaît que si elle a
/// été fournie (migration 018), sinon les initiales.
class MemberDetailScreen extends StatefulWidget {
  final Member member;
  final bool lectureSeule;

  /// Mode carte seule (tranche P1) : seul le visuel de la carte,
  /// sans titre, sans paiement ni modification. Le fidèle voit sa
  /// carte depuis sa coquille, rien d'autre.
  final bool carteSeule;

  const MemberDetailScreen({
    super.key,
    required this.member,
    this.lectureSeule = false,
    this.carteSeule = false,
  });

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  late Member _member;
  late Future<Map<String, dynamic>> _completFuture;
  Future<Frequentation>? _frequentationFuture;

  @override
  void initState() {
    super.initState();
    _member = widget.member;
    if (!widget.carteSeule) {
      _completFuture =
          context.read<AppState>().api.getMembreComplet(widget.member.id);
      if (!widget.lectureSeule) {
        _frequentationFuture =
            context.read<AppState>().api.getFrequentation(widget.member.id);
      }
    }
  }

  void _refresh() {
    if (widget.carteSeule) return;
    setState(() {
      _completFuture =
          context.read<AppState>().api.getMembreComplet(widget.member.id);
      if (!widget.lectureSeule) {
        _frequentationFuture =
            context.read<AppState>().api.getFrequentation(widget.member.id);
      }
    });
  }

  Future<void> _reloadMember() async {
    try {
      final membre =
          await context.read<AppState>().api.getMember(widget.member.id);
      if (mounted) setState(() => _member = membre);
    } catch (_) {}
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'actif':
        return AppTheme.bleuNuit;
      case 'nouveau_converti':
        return AppTheme.bleuFonce;
      case 'inactif':
        return Colors.grey;
      case 'ancien':
        return AppTheme.orFonce;
      default:
        return Colors.grey;
    }
  }

  Widget _row(BuildContext context, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value ?? '—',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMember(BuildContext context) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le membre « ${_member.fullName} » (${_member.matricule}) ?',
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    try {
      await context.read<AppState>().api.deleteMember(_member.id);
      if (context.mounted) {
        showSuccess(context, 'Membre supprimé.');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _changerStatut() async {
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
            'ancien': 'Ancien',
          },
          onChanged: (v) => statut = v ?? 'membre',
        ),
        dialogTextField(controller: motifController, label: 'Motif'),
      ],
      isValid: () => true,
      onSave: () async {
        try {
          await context.read<AppState>().api.changerStatutMembre(
                _member.id,
                statut: statut,
                motif: motifController.text.trim().isEmpty
                    ? null
                    : motifController.text.trim(),
              );
          if (mounted) showSuccess(context, 'Statut mis à jour.');
          await _reloadMember();
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _ajouterBapteme() async {
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
                memberId: _member.id,
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

  /// Dates du parcours (conversion, mariage) modifiées directement sur la
  /// fiche, sans passer par un autre écran.
  Future<void> _modifierDatesParcours() async {
    final conversionController =
        TextEditingController(text: _member.dateConversion ?? '');
    final mariageController =
        TextEditingController(text: _member.dateMariage ?? '');
    await showCreateDialog(
      context: context,
      title: 'Dates du parcours',
      saveLabel: 'Enregistrer',
      fields: [
        dialogDateField(
            context: context,
            controller: conversionController,
            label: 'Date de conversion'),
        dialogDateField(
            context: context,
            controller: mariageController,
            label: 'Date de mariage'),
      ],
      isValid: () => true,
      onSave: () async {
        try {
          final maj = await context.read<AppState>().api.updateMember(
                _member.id,
                fullName: _member.fullName,
                phone: _member.phone,
                email: _member.email,
                birthDate: _member.birthDate,
                sexe: _member.sexe,
                department: _member.department,
                fonction: _member.fonction,
                poste: _member.poste,
                cellGroup: _member.cellGroup,
                status: _member.status,
                dateConversion: conversionController.text.trim().isEmpty
                    ? null
                    : conversionController.text.trim(),
                dateMariage: mariageController.text.trim().isEmpty
                    ? null
                    : mariageController.text.trim(),
              );
          if (mounted) {
            setState(() => _member = maj);
            showSuccess(context, 'Dates du parcours enregistrées.');
          }
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  String? _dateAffichee(String? iso) {
    if (iso == null) return null;
    return formatDate(DateTime.tryParse(iso));
  }

  @override
  Widget build(BuildContext context) {
    // QR de la carte : CODE_EGLISE:MATRICULE (ex. ESC-0411:M-LK-150390-01).
    // Le lecteur accepte aussi les anciennes cartes, matricule seul.
    final codeEglise = context.read<AppState>().church?.code;
    final qrData = codeEglise != null && codeEglise.isNotEmpty
        ? '$codeEglise:${_member.matricule}'
        : _member.matricule;
    // Mode carte seule (P1) : seul le visuel de la carte, sans barre,
    // sans titre, sans paiement ni modification.
    if (widget.carteSeule) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carteVisuelle(context, qrData),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_member.fullName),
        actions: [
          if (!widget.lectureSeule)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer',
              onPressed: () => _deleteMember(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _carteVisuelle(context, qrData),
                const SizedBox(height: 16),
                if (!widget.lectureSeule)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => MemberFormScreen(member: _member),
                        ),
                      );
                      if (changed == true && context.mounted) {
                        await _reloadMember();
                        _refresh();
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row(context, 'Matricule', _member.matricule),
                        _row(context, 'Téléphone', _member.phone),
                        _row(context, 'E-mail', _member.email),
                        _row(context, 'Date de naissance',
                            _dateAffichee(_member.birthDate)),
                        _row(context, 'Département', _member.department),
                        _row(context, 'Fonction', _member.fonctionAffichee),
                        _row(context, 'Poste', _member.poste),
                        _row(context, 'Cellule', _member.cellGroup),
                        _row(context, 'Membre depuis',
                            formatDate(_member.createdAt)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<Map<String, dynamic>>(
                  future: _completFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const AppLoading();
                    }
                    if (snapshot.hasError) {
                      return AppError(
                        message: snapshot.error.toString(),
                        onRetry: _refresh,
                      );
                    }
                    final data = snapshot.data!;
                    final statuts = (data['historique_statuts'] as List? ?? const [])
                        .map((e) => MembreStatut.fromJson(
                            e as Map<String, dynamic>))
                        .toList();
                    final bapteme = data['bapteme'] == null
                        ? null
                        : Bapteme.fromJson(
                            data['bapteme'] as Map<String, dynamic>);
                    final departements =
                        (data['departements'] as List? ?? const [])
                            .map((e) => Departement.fromJson(
                                e as Map<String, dynamic>))
                            .toList();
                    final cellules = (data['cellules'] as List? ?? const [])
                        .map((e) => Cellule.fromJson(
                            e as Map<String, dynamic>))
                        .toList();
                    final enfants = (data['enfants'] as List? ?? const [])
                        .map((e) => LienParentEnfant.fromJson(
                            e as Map<String, dynamic>))
                        .toList();
                    final parents = (data['parents'] as List? ?? const [])
                        .map((e) => LienParentEnfant.fromJson(
                            e as Map<String, dynamic>))
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _parcoursCard(bapteme),
                        const SizedBox(height: 16),
                        if (!widget.lectureSeule) ...[
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _changerStatut,
                                  icon: const Icon(Icons.swap_horiz),
                                  label: const Text('Changer de statut'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _ajouterBapteme,
                                  icon:
                                      const Icon(Icons.water_drop_outlined),
                                  label: const Text('Ajouter un baptême'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        _statutsCard(statuts),
                        const SizedBox(height: 16),
                        _departementsCard(departements),
                        const SizedBox(height: 16),
                        _cellulesCard(cellules),
                        const SizedBox(height: 16),
                        _liensCard(enfants, parents),
                        if (!widget.lectureSeule) ...[
                          const SizedBox(height: 16),
                          _frequentationCard(),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Visuel de la carte de membre, réutilisé par la fiche complète et
  /// par la page Carte seule (P1). Photo, nom, matricule, église,
  /// Membre depuis, QR. Rien d'autre.
  Widget _carteVisuelle(BuildContext context, String qrData) {
    final nomEglise = context.read<AppState>().church?.name;
    // Carte du modèle : dégradé bleu nuit, barre or en haut,
    // matricule en mono. Photo, nom, matricule, église,
    // Membre depuis, QR. Rien d'autre.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.bleuNuit, Color(0xFF16324F)],
          ),
        ),
        child: Column(
          children: [
            Container(height: 6, color: AppTheme.or),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'CARTE DE MEMBRE',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'e-System Church',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          color: AppTheme.or,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white24,
                    backgroundImage: _member.photoUrl != null
                        ? NetworkImage(_member.photoUrl!)
                        : null,
                    child: _member.photoUrl == null
                        ? Text(
                            _member.fullName.isNotEmpty
                                ? _member.fullName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 32, color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _member.fullName,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Carte de membre — ',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                        TextSpan(
                          text: _member.matricule,
                          style: AppTheme.styleCode.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (nomEglise != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      nomEglise,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  Text(
                    _member.createdAt == null
                        ? 'Membre depuis — À compléter'
                        : 'Membre depuis ${formatDate(_member.createdAt)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  if (!widget.carteSeule) ...[
                    const SizedBox(height: 8),
                    StatusChip(
                      label: _member.statutAffiche,
                      color: _statusColor(
                          _member.estAncien ? 'ancien' : _member.status),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 180,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _member.matricule,
                    style: AppTheme.styleCode.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parcoursCard(Bapteme? bapteme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Parcours',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (!widget.lectureSeule)
                  TextButton.icon(
                    onPressed: _modifierDatesParcours,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier les dates'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _row(context, 'Conversion', _dateAffichee(_member.dateConversion)),
            _row(context, 'Baptême',
                bapteme == null ? null : afficherDate(bapteme.dateBapteme)),
            if (bapteme != null)
              _row(context, 'Lieu du baptême',
                  '${bapteme.lieu ?? '—'} · ${bapteme.pasteur ?? '—'}${bapteme.certificatNumero != null ? ' · Certificat ${bapteme.certificatNumero}' : ''}'),
            _row(context, 'Mariage', _dateAffichee(_member.dateMariage)),
          ],
        ),
      ),
    );
  }

  Widget _statutsCard(List<MembreStatut> statuts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historique des statuts',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }

  Widget _departementsCard(List<Departement> departements) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Départements',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (departements.isEmpty)
              const EmptyState(
                icon: Icons.group_work_outlined,
                message: 'Ce membre n’appartient à aucun département.',
              )
            else
              ...departements.map((d) => ListTile(
                    leading: const Icon(Icons.group_work_outlined),
                    title: Text(d.nom),
                    subtitle: Text(d.description ?? 'Aucune description.'),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _cellulesCard(List<Cellule> cellules) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cellules',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }

  Widget _liensCard(
      List<LienParentEnfant> enfants, List<LienParentEnfant> parents) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Liens parent – enfant',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (enfants.isEmpty && parents.isEmpty)
              const EmptyState(
                icon: Icons.family_restroom_outlined,
                message: 'Aucun lien parent-enfant enregistré.',
              )
            else ...[
              ...enfants.map((l) => ListTile(
                    leading: const Icon(Icons.child_care_outlined),
                    title: Text('Enfant : ${l.enfantMemberId}'),
                    subtitle: Text(
                        'Lien : ${l.lienLabel} · ${l.statut == 'valide' ? 'Validé' : l.statut == 'refuse' ? 'Refusé' : 'En attente'}'),
                  )),
              ...parents.map((l) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text('Parent : ${l.parentMemberId}'),
                    subtitle: Text(
                        'Lien : ${l.lienLabel} · ${l.statut == 'valide' ? 'Validé' : l.statut == 'refuse' ? 'Refusé' : 'En attente'}'),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _frequentationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fréquentation',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<Frequentation>(
              future: _frequentationFuture,
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
                final frequentation = snapshot.data!;
                if (frequentation.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.event_available_outlined,
                    message: 'Aucune présence enregistrée.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${frequentation.presents} présents sur ${frequentation.total} pointages.'),
                    const SizedBox(height: 8),
                    ...frequentation.items.map((p) => ListTile(
                          leading: Icon(
                            p.statut == 'present'
                                ? Icons.check_circle_outline
                                : p.statut == 'absent'
                                    ? Icons.cancel_outlined
                                    : Icons.schedule_outlined,
                          ),
                          title: Text(p.titre ?? 'Sans titre'),
                          subtitle: Text(
                              '${p.dateEvenement == null ? '—' : afficherDate(p.dateEvenement)} · ${p.type == 'culte' ? 'Culte' : 'Événement'} · ${p.mode == 'scan_qr' ? 'Scan QR' : p.mode == 'liste' ? 'Liste' : 'Manuel'}'),
                          trailing: StatusChip(
                            label: p.statutLabel,
                            color: p.statut == 'present'
                                ? AppTheme.bleuNuit
                                : p.statut == 'absent'
                                    ? AppTheme.rougeErreur
                                    : Colors.grey,
                          ),
                        )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
