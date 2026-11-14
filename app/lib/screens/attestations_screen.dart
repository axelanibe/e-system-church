import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/attestation.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// US3 + tranche B + T10 — Attestations, côté trésorier / admin : choix de
/// l'année et du type, génération des attestations de dons, émission
/// individuelle d'une attestation de mariage, de naissance, de baptême ou
/// d'un certificat de membre, liste, PDF, correction avec motif (nouvelle
/// attestation, ancienne annulée). PDF exclusivement, jamais d'autre format.
class AttestationsScreen extends StatefulWidget {
  const AttestationsScreen({super.key});

  @override
  State<AttestationsScreen> createState() => _AttestationsScreenState();
}

const _typesEvenement = ['mariage', 'naissance', 'bapteme', 'membre'];

class _AttestationsScreenState extends State<AttestationsScreen> {
  late int _annee;
  String? _typeFiltre; // null = tous les types
  late Future<List<Attestation>> _future;
  List<Member> _membres = [];
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _annee = DateTime.now().year;
    _future = _load();
    context.read<AppState>().api.getMembers().then((page) {
      if (mounted) setState(() => _membres = page.membres);
    }).catchError((_) {});
  }

  Future<List<Attestation>> _load() => context
      .read<AppState>()
      .api
      .getAttestations(annee: _annee, type: _typeFiltre);

  void _refresh() => setState(() => _future = _load());

  Future<void> _generer() async {
    setState(() => _working = true);
    try {
      final creees = await context
          .read<AppState>()
          .api
          .genererAttestations(annee: _annee);
      if (!mounted) return;
      showSuccess(
        context,
        creees.isEmpty
            ? 'Aucune nouvelle attestation pour $_annee.'
            : '${pluriel(creees.length, 'attestation créée', 'attestations créées')} pour $_annee.',
      );
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _telecharger(Attestation a) async {
    try {
      final bytes =
          await context.read<AppState>().api.telechargerAttestationPdf(a.id);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: '${a.numero}.pdf', mimeType: 'application/pdf'),
          ],
          subject: 'Attestation ${a.numero}',
        ),
      );
      if (mounted) {
        showSuccess(context, 'Attestation ${a.numero} partagée.');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Formulaire d'émission d'une attestation d'événement. Membre et date
  /// obligatoires ; lieu, officiant et champs propres au type facultatifs.
  Future<void> _emettre() async {
    var type = 'mariage';
    String? memberId;
    DateTime? dateEvenement;
    final lieuCtrl = TextEditingController();
    final officiantCtrl = TextEditingController();
    final conjointCtrl = TextEditingController();
    final pereCtrl = TextEditingController();
    final mereCtrl = TextEditingController();
    final parrainCtrl = TextEditingController();
    final marraineCtrl = TextEditingController();
    String? erreur;
    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          String iso(DateTime d) =>
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          Future<void> choisirDate() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: ctx,
              initialDate: dateEvenement ?? now,
              firstDate: DateTime(1900),
              lastDate: now,
              helpText: 'Date de l’événement',
              cancelText: 'Annuler',
              confirmText: 'Choisir',
            );
            if (picked != null) setDialogState(() => dateEvenement = picked);
          }

          return AlertDialog(
            title: const Text('Émettre une attestation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: _typesEvenement
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(Attestation.libelleType(t)),
                            ))
                        .toList(),
                    onChanged: (t) {
                      if (t != null) setDialogState(() => type = t);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: memberId,
                    decoration: const InputDecoration(
                        labelText: 'Membre concerné *'),
                    items: _membres
                        .map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text('${m.fullName} (${m.matricule})'),
                            ))
                        .toList(),
                    onChanged: (id) => setDialogState(() => memberId = id),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(dateEvenement == null
                            ? 'Date de l’événement *'
                            : formatDate(dateEvenement)),
                      ),
                      TextButton(
                        onPressed: choisirDate,
                        child: const Text('Choisir la date'),
                      ),
                    ],
                  ),
                  TextField(
                    controller: lieuCtrl,
                    decoration: const InputDecoration(labelText: 'Lieu'),
                    maxLength: 200,
                  ),
                  TextField(
                    controller: officiantCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Officiant'),
                    maxLength: 200,
                  ),
                  if (type == 'mariage')
                    TextField(
                      controller: conjointCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Nom du conjoint ou de la conjointe'),
                      maxLength: 200,
                    ),
                  if (type == 'naissance') ...[
                    TextField(
                      controller: pereCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Nom du père'),
                      maxLength: 200,
                    ),
                    TextField(
                      controller: mereCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Nom de la mère'),
                      maxLength: 200,
                    ),
                  ],
                  if (type == 'bapteme') ...[
                    TextField(
                      controller: parrainCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Nom du parrain'),
                      maxLength: 200,
                    ),
                    TextField(
                      controller: marraineCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Nom de la marraine'),
                      maxLength: 200,
                    ),
                  ],
                  if (erreur != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(erreur!,
                          style: const TextStyle(color: AppTheme.rougeErreur)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () async {
                  if (memberId == null || dateEvenement == null) {
                    setDialogState(() => erreur =
                        'Choisissez le membre concerné et la date de l’événement.');
                    return;
                  }
                  setState(() => _working = true);
                  try {
                    final nouvelle = await context
                        .read<AppState>()
                        .api
                        .emettreAttestation(
                          type: type,
                          memberId: memberId!,
                          dateEvenement: iso(dateEvenement!),
                          lieu: lieuCtrl.text.trim(),
                          officiant: officiantCtrl.text.trim(),
                          conjointNom: conjointCtrl.text.trim(),
                          pereNom: pereCtrl.text.trim(),
                          mereNom: mereCtrl.text.trim(),
                          parrainNom: parrainCtrl.text.trim(),
                          marraineNom: marraineCtrl.text.trim(),
                        );
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                    if (mounted) {
                      showSuccess(context,
                          'Attestation ${nouvelle.numero} émise.');
                      _refresh();
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      setDialogState(() => erreur = e.toString());
                    }
                  } finally {
                    if (mounted) setState(() => _working = false);
                  }
                },
                child: const Text('Émettre'),
              ),
            ],
          );
        },
      ),
    );
    lieuCtrl.dispose();
    officiantCtrl.dispose();
    conjointCtrl.dispose();
    pereCtrl.dispose();
    mereCtrl.dispose();
    parrainCtrl.dispose();
    marraineCtrl.dispose();
  }

  Future<void> _corriger(Attestation a) async {
    final motifCtrl = TextEditingController();
    DateTime? dateEvenement;
    final lieuCtrl = TextEditingController();
    final officiantCtrl = TextEditingController();
    final conjointCtrl = TextEditingController();
    final pereCtrl = TextEditingController();
    final mereCtrl = TextEditingController();
    final parrainCtrl = TextEditingController();
    final marraineCtrl = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> choisirDate() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: ctx,
              initialDate: dateEvenement ?? now,
              firstDate: DateTime(1900),
              lastDate: now,
              helpText: 'Nouvelle date de l’événement',
              cancelText: 'Annuler',
              confirmText: 'Choisir',
            );
            if (picked != null) setDialogState(() => dateEvenement = picked);
          }

          return AlertDialog(
            title: const Text('Corriger l’attestation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: motifCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Motif de la correction',
                      hintText: 'Ex. don oublié ajouté',
                    ),
                    maxLength: 500,
                    autofocus: true,
                  ),
                  // Événement : seuls les champs remplis changent,
                  // les autres gardent leur valeur figée.
                  if (!a.estDon) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(dateEvenement == null
                              ? 'Date inchangée'
                              : formatDate(dateEvenement)),
                        ),
                        TextButton(
                          onPressed: choisirDate,
                          child: const Text('Changer la date'),
                        ),
                      ],
                    ),
                    TextField(
                      controller: lieuCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Lieu (vide = inchangé)'),
                      maxLength: 200,
                    ),
                    TextField(
                      controller: officiantCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Officiant (vide = inchangé)'),
                      maxLength: 200,
                    ),
                    if (a.type == 'mariage')
                      TextField(
                        controller: conjointCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Conjoint(e) (vide = inchangé)'),
                        maxLength: 200,
                      ),
                    if (a.type == 'naissance') ...[
                      TextField(
                        controller: pereCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Père (vide = inchangé)'),
                        maxLength: 200,
                      ),
                      TextField(
                        controller: mereCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Mère (vide = inchangé)'),
                        maxLength: 200,
                      ),
                    ],
                    if (a.type == 'bapteme') ...[
                      TextField(
                        controller: parrainCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Parrain (vide = inchangé)'),
                        maxLength: 200,
                      ),
                      TextField(
                        controller: marraineCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Marraine (vide = inchangé)'),
                        maxLength: 200,
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(motifCtrl.text.trim()),
                child: const Text('Corriger'),
              ),
            ],
          );
        },
      ),
    );
    if (motif == null || motif.length < 2) return;
    if (!mounted) return;
    setState(() => _working = true);
    try {
      String? iso(DateTime? d) => d == null
          ? null
          : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final nouvelle = await context.read<AppState>().api.corrigerAttestation(
            a.id,
            motif: motif,
            dateEvenement: iso(dateEvenement),
            lieu: lieuCtrl.text.trim(),
            officiant: officiantCtrl.text.trim(),
            conjointNom: conjointCtrl.text.trim(),
            pereNom: pereCtrl.text.trim(),
            mereNom: mereCtrl.text.trim(),
            parrainNom: parrainCtrl.text.trim(),
            marraineNom: marraineCtrl.text.trim(),
          );
      if (!mounted) return;
      showSuccess(context, 'Nouvelle attestation ${nouvelle.numero} créée.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final annees = [for (var i = 0; i < 3; i++) DateTime.now().year - i];
    return Scaffold(
      appBar: AppBar(title: const Text('Attestations')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: _annee,
                  items: annees
                      .map((a) => DropdownMenuItem(value: a, child: Text('$a')))
                      .toList(),
                  onChanged: (a) {
                    if (a == null) return;
                    setState(() {
                      _annee = a;
                      _future = _load();
                    });
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String?>(
                    value: _typeFiltre,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tous types')),
                      DropdownMenuItem(value: 'don', child: Text('Dons')),
                      DropdownMenuItem(value: 'mariage', child: Text('Mariage')),
                      DropdownMenuItem(value: 'naissance', child: Text('Naissance')),
                      DropdownMenuItem(value: 'bapteme', child: Text('Baptême')),
                      DropdownMenuItem(value: 'membre', child: Text('Membre')),
                    ],
                    onChanged: (t) => setState(() {
                      _typeFiltre = t;
                      _future = _load();
                    }),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _working ? null : _generer,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Générer'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : _emettre,
                      icon: const Icon(Icons.add_outlined),
                      label: const Text('Émettre'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Reçu justificatif seulement, sans valeur fiscale en Côte d’Ivoire (dons).',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Attestation>>(
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
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.description_outlined,
                    message: 'Aucune attestation pour cette année.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: items
                        .map((a) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text(a.estDon && a.totalFcfa != null
                                    ? '${a.membreNom ?? 'Donateur'} — ${formatFcfa(a.totalFcfa!)}'
                                    : '${a.membreNom ?? 'Membre'} — ${a.libelle}'),
                                subtitle: Text(
                                    '${a.numero}${a.estDon && a.nbDons != null ? ' · ${pluriel(a.nbDons!, 'don')}' : ''} · ${formatDate(a.dateEmission)}${a.estEmise ? '' : ' · annulée'}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (a.estEmise)
                                      IconButton(
                                        icon: const Icon(Icons.download_outlined),
                                        tooltip: 'Voir le PDF',
                                        onPressed: () => _telecharger(a),
                                      ),
                                    if (a.estEmise)
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Corriger',
                                        onPressed: () => _corriger(a),
                                      ),
                                    if (!a.estEmise)
                                      const Icon(Icons.cancel_outlined,
                                          color: AppTheme.rougeErreur),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
