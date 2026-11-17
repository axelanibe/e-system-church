import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/gouvernance.dart';
import '../models/member.dart';
import '../models/parametres.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import '../widgets/liste_avec_fab.dart';
import '../widgets/signature_pad.dart';
import 'documents_screen.dart';

/// Mandats et nominations (maquette Membres Finances, écran 7) : hub
/// unique à 4 onglets (Mandats en cours, Nominations, Procès-verbaux,
/// Documents). Le contenu Procès-verbaux vient de l'ancien 3e onglet
/// de ReunionsConseilScreen, le contenu Documents est le même widget
/// que DocumentsScreen (ContenuDocuments) : rien n'est dupliqué.
/// Une nomination est un mandat, sa décision est gardée quand elle
/// existe.
class MandatsScreen extends StatefulWidget {
  final int ongletInitial;

  const MandatsScreen({super.key, this.ongletInitial = 0});

  @override
  State<MandatsScreen> createState() => _MandatsScreenState();
}

class _MandatsScreenState extends State<MandatsScreen> {
  int _tab = 0;
  late Future<List<Mandat>> _enCoursFuture;
  late Future<List<Mandat>> _tousFuture;
  late Future<MemberPage> _membresFuture;
  late Future<List<Decision>> _decisionsFuture;
  late Future<List<ReunionConseil>> _reunionsFuture;
  late Future<List<ProcesVerbal>> _pvFuture;
  late Future<EgliseParametres> _parametresFuture;

  // L'onglet actif est-il vide ? Sert à masquer le FAB quand l'état
  // vide affiche déjà le bouton de création (motif Serviteurs : un
  // seul bouton, pas deux).
  bool _enCoursVides = false;
  bool _tousVides = false;
  bool _pvVides = false;
  bool _documentsVides = false;

  final _documentsKey = GlobalKey<ContenuDocumentsState>();

  @override
  void initState() {
    super.initState();
    _tab = widget.ongletInitial.clamp(0, 3);
    final api = context.read<AppState>().api;
    _enCoursFuture = api.getMandats(statut: 'en_cours');
    _tousFuture = api.getMandats();
    _membresFuture = api.getMembers();
    _decisionsFuture = api.getDecisions();
    _reunionsFuture = api.getReunionsConseil();
    _pvFuture = api.getProcesVerbaux();
    _parametresFuture = api.getParametres();
  }

  void _refresh() {
    final api = context.read<AppState>().api;
    setState(() {
      _enCoursFuture = api.getMandats(statut: 'en_cours');
      _tousFuture = api.getMandats();
      _pvFuture = api.getProcesVerbaux();
    });
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _createMandat(List<Member> membres, List<Decision> decisions) async {
    String? memberId = membres.isEmpty ? null : membres.first.id;
    String? decisionId;
    final fonctionController = TextEditingController();
    final debutController = TextEditingController();
    final finController = TextEditingController();
    await showCreateDialog(
      context: context,
      // Une nomination est un mandat : même dialogue, le titre suit
      // l'onglet (R2-25 : le contenu suit l'onglet).
      title: _tab == 0 ? 'Nouveau mandat' : 'Nouvelle nomination',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: memberId,
          label: 'Membre',
          options: {for (final m in membres) m.id: '${m.fullName} (${m.matricule})'},
          onChanged: (v) => memberId = v,
        ),
        dialogTextField(controller: fonctionController, label: 'Fonction'),
        dialogDateField(
          context: context,
          controller: debutController,
          label: 'Date de début',
        ),
        dialogDateField(
          context: context,
          controller: finController,
          label: 'Date de fin (facultative)',
        ),
        dialogDropdown<String?>(
          value: decisionId,
          label: 'Décision de nomination',
          options: {
            null: 'Aucune',
            for (final d in decisions) d.id: d.titre,
          },
          onChanged: (v) => decisionId = v,
        ),
      ],
      isValid: () =>
          memberId != null &&
          fonctionController.text.trim().isNotEmpty &&
          debutController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createMandat(
                memberId: memberId!,
                fonction: fonctionController.text.trim(),
                dateDebut: debutController.text.trim(),
                dateFin: _opt(finController),
                decisionId: decisionId,
              );
          if (mounted) showSuccess(context, 'Mandat créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  Future<void> _terminer(Mandat mandat) async {
    try {
      await context.read<AppState>().api.terminerMandat(mandat.id);
      if (mounted) showSuccess(context, 'Mandat terminé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimer(Mandat mandat, Map<String, String> noms) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le mandat de ${noms[mandat.memberId] ?? 'ce membre'} (${mandat.fonction}) ?',
    );
    if (!confirmed) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.deleteMandat(mandat.id);
      if (mounted) showSuccess(context, 'Mandat supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _createPv(
    List<ReunionConseil> reunions,
    String? signataireDefaut,
  ) async {
    String? reunionId = reunions.isEmpty ? null : reunions.first.id;
    final numeroController = TextEditingController();
    final contenuController = TextEditingController();
    final dateController = TextEditingController();
    final signataireController =
        TextEditingController(text: signataireDefaut ?? '');
    await showCreateDialog(
      context: context,
      title: 'Nouveau procès-verbal',
      saveLabel: 'Créer',
      fields: [
        dialogDropdown<String?>(
          value: reunionId,
          label: 'Réunion',
          options: {
            null: 'Aucune',
            for (final r in reunions) r.id: r.titre,
          },
          onChanged: (v) => reunionId = v,
        ),
        dialogTextField(controller: numeroController, label: 'Numéro'),
        dialogTextField(
          controller: contenuController,
          label: 'Contenu',
          maxLines: 5,
        ),
        dialogDateField(
          context: context,
          controller: dateController,
          label: 'Date du procès-verbal',
        ),
        dialogTextField(
          controller: signataireController,
          label: 'Signataire',
        ),
      ],
      isValid: () => contenuController.text.trim().isNotEmpty,
      onSave: () async {
        try {
          await context.read<AppState>().api.createProcesVerbal(
                reunionId: reunionId,
                numero: _opt(numeroController),
                contenu: contenuController.text.trim(),
                datePv: _opt(dateController),
                signataire: _opt(signataireController),
              );
          if (mounted) showSuccess(context, 'Procès-verbal créé.');
          _refresh();
        } catch (e) {
          if (mounted) showApiError(context, e);
        }
      },
    );
  }

  /// Signature dessinée (V1) : le dialogue texte est remplacé par le
  /// pad, le champ nom est gardé (pré-rempli par le signataire du PV,
  /// le signataire configuré, ou le nom de l'utilisateur connecté).
  /// Après signature, le PDF signé est re-téléchargé.
  Future<void> _signer(ProcesVerbal pv, String? signataireDefaut) async {
    final resultat = await montrerDialogueSignature(
      context,
      titre: 'Signer le procès-verbal',
      nomInitial: pv.signataire ??
          signataireDefaut ??
          context.read<AppState>().user?.fullName ??
          '',
    );
    if (resultat == null || !mounted) return;
    try {
      await context.read<AppState>().api.signerProcesVerbal(
            pv.id,
            points: resultat.trace.points,
            imagePng: resultat.trace.pngBytes,
            nomAffiche: resultat.nom,
          );
      if (!mounted) return;
      showSuccess(context, 'Procès-verbal signé.');
      _refresh();
      await _telechargerPv(pv);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _telechargerPv(ProcesVerbal pv) async {
    try {
      final bytes = await context
          .read<AppState>()
          .api
          .telechargerProcesVerbalPdf(pv.id);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes,
                name: '${pv.numero ?? 'proces-verbal'}.pdf',
                mimeType: 'application/pdf'),
          ],
          subject: 'Procès-verbal ${pv.numero ?? ''}',
        ),
      );
      if (mounted) {
        showSuccess(context, 'Procès-verbal ${pv.numero ?? ''} partagé.');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _supprimerPv(ProcesVerbal pv) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le procès-verbal « ${pv.numero ?? 'sans numéro'} » ?',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().api.deleteProcesVerbal(pv.id);
      if (mounted) showSuccess(context, 'Procès-verbal supprimé.');
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _liste(Future<List<Mandat>> future, Map<String, String> noms,
      {ValueChanged<bool>? onVideChange}) {
    return FutureBuilder<List<Mandat>>(
      future: future,
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
        // Signale le vide au parent (FAB masqué quand l'état vide
        // affiche déjà son bouton). Le parent ne reconstruit que si
        // la valeur change.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) onVideChange?.call(items.isEmpty);
        });
        if (items.isEmpty) {
          // États vides de la maquette, écran 7.
          return EmptyState(
            icon: Icons.verified_outlined,
            message: _tab == 0
                ? 'Aucun mandat en cours\nLes mandats des responsables, avec leurs dates, s’enregistrent ici.'
                : 'Aucune nomination\nChaque nomination garde sa décision et sa date d’effet.',
            actionLabel:
                _tab == 0 ? 'Créer un mandat' : 'Créer une nomination',
            onAction: () async {
              try {
                final membres = (await _membresFuture).membres;
                final decisions = await _decisionsFuture;
                if (mounted) await _createMandat(membres, decisions);
              } catch (e) {
                if (context.mounted) showApiError(context, e);
              }
            },
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final m = items[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.verified_outlined),
                ),
                title: Text(noms[m.memberId] ?? 'Membre', style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '${m.fonction} · ${afficherDate(m.dateDebut)}'
                  '${m.dateFin != null ? ' — ${afficherDate(m.dateFin)}' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                      label: m.statutLabel,
                      color: m.enCours ? AppTheme.violetProfond : Colors.grey,
                    ),
                    if (m.enCours)
                      IconButton(
                        icon: const Icon(Icons.check_outlined),
                        tooltip: 'Terminer le mandat',
                        onPressed: () => _terminer(m),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimer(m, noms),
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

  Widget _pvTab(Map<String, String> reunionsNoms, String? signataireDefaut) {
    return FutureBuilder<List<ProcesVerbal>>(
      future: _pvFuture,
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
        if (items.isEmpty != _pvVides) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pvVides != items.isEmpty) {
              setState(() => _pvVides = items.isEmpty);
            }
          });
        }
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.description_outlined,
            // État vide de la maquette, écran 7.
            message: 'Aucun procès-verbal\nLes réunions du bureau produisent leur procès-verbal ici.',
            actionLabel: 'Rédiger un procès-verbal',
            onAction: () async {
              try {
                final reunions = await _reunionsFuture;
                if (mounted) await _createPv(reunions, signataireDefaut);
              } catch (e) {
                if (context.mounted) showApiError(context, e);
              }
            },
          );
        }
        return ListeAvecFab(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final pv = items[index];
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.description_outlined),
                  ),
                  title: Text(
                    pv.numero ?? 'Sans numéro',
                    style: pv.numero == null
                        ? TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 13.5,
                          )
                        : const TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '${pv.reunionId != null ? '${reunionsNoms[pv.reunionId] ?? '—'} · ' : ''}'
                    '${pv.datePv != null ? afficherDate(pv.datePv) : 'Date à compléter'}'
                    '${pv.signataire != null ? ' · ${pv.signataire}' : ''}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusChip(
                        label: pv.statutLabel,
                        color: pv.statut == 'signe'
                            ? AppTheme.violetProfond
                            : Colors.grey,
                      ),
                      if (pv.statut == 'brouillon')
                        IconButton(
                          icon: const Icon(Icons.draw_outlined),
                          tooltip: 'Signer',
                          onPressed: () => _signer(pv, signataireDefaut),
                        ),
                      if (pv.statut == 'signe')
                        IconButton(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: 'Voir le PDF signé',
                          onPressed: () => _telechargerPv(pv),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Supprimer',
                        onPressed: () => _supprimerPv(pv),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Informe le parent que la liste d'un onglet Mandats est vide ou
  /// non, pour masquer le FAB quand l'état vide a déjà son bouton.
  void _signalerVide(int onglet, bool vide) {
    if (onglet == 0 && _enCoursVides != vide) {
      setState(() => _enCoursVides = vide);
    } else if (onglet == 1 && _tousVides != vide) {
      setState(() => _tousVides = vide);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: _tab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mandats et nominations'),
          bottom: TabBar(
            isScrollable: true,
            labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            onTap: (i) => setState(() => _tab = i),
            tabs: const [
              Tab(text: 'Mandats en cours'),
              Tab(text: 'Nominations'),
              Tab(text: 'Procès-verbaux'),
              Tab(text: 'Documents'),
            ],
          ),
        ),
        body: FutureBuilder<MemberPage>(
          future: _membresFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (snapshot.hasError) {
              return AppError(
                message: snapshot.error.toString(),
                onRetry: () => setState(() {
                  _membresFuture =
                      context.read<AppState>().api.getMembers();
                }),
              );
            }
            final noms = {
              for (final m in snapshot.data!.membres) m.id: m.fullName
            };
            return FutureBuilder<List<ReunionConseil>>(
              future: _reunionsFuture,
              builder: (context, reunionsSnapshot) {
                if (reunionsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const AppLoading();
                }
                if (reunionsSnapshot.hasError) {
                  return AppError(
                    message: reunionsSnapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }
                final reunionsNoms = {
                  for (final r in reunionsSnapshot.data!) r.id: r.titre
                };
                return FutureBuilder<EgliseParametres>(
                  future: _parametresFuture,
                  builder: (context, paramsSnapshot) {
                    final signataireDefaut =
                        paramsSnapshot.data?.signataireProcesVerbaux;
                    return TabBarView(
                      children: [
                        _liste(_enCoursFuture, noms,
                            onVideChange: (v) => _signalerVide(0, v)),
                        _liste(_tousFuture, noms,
                            onVideChange: (v) => _signalerVide(1, v)),
                        _pvTab(reunionsNoms, signataireDefaut),
                        ContenuDocuments(
                          key: _documentsKey,
                          onVideChange: (vide) {
                            if (vide != _documentsVides) {
                              setState(
                                  () => _documentsVides = vide);
                            }
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: ((_tab == 0 && _enCoursVides) ||
                (_tab == 1 && _tousVides) ||
                (_tab == 2 && _pvVides) ||
                (_tab == 3 && _documentsVides))
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  try {
                    if (_tab == 3) {
                      await _documentsKey.currentState?.creer();
                      return;
                    }
                    if (_tab == 2) {
                      final reunions = await _reunionsFuture;
                      final params = await _parametresFuture;
                      if (mounted) {
                        await _createPv(reunions,
                            params.signataireProcesVerbaux);
                      }
                      return;
                    }
                    final membres = (await _membresFuture).membres;
                    final decisions = await _decisionsFuture;
                    if (mounted) await _createMandat(membres, decisions);
                  } catch (e) {
                    if (context.mounted) showApiError(context, e);
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(_tab == 0
                    ? 'Créer un mandat'
                    : _tab == 1
                        ? 'Créer une nomination'
                        : _tab == 2
                            ? 'Rédiger un procès-verbal'
                            : 'Ajouter un document',
                    style: const TextStyle(fontSize: 13.5)),
              ),
      ),
    );
  }
}
