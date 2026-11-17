import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/attestation.dart';
import '../models/member.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/signature_pad.dart';

/// Attestations annuelles (maquette, écran 44) : le document qui
/// totalise, pour un membre, ses cotisations et ses dons d'une année.
///
/// L'API ne propose pas de génération pour un seul membre : la
/// génération reste groupée (`genererAttestations`, tous les donateurs
/// de l'année). « Délivrer l'attestation » lance donc cette génération
/// puis retrouve l'attestation du membre choisi ; s'il n'a aucun don
/// confirmé cette année-là, aucune attestation n'est délivrée. Le
/// contenu de l'attestation (ce qu'elle reprend : cotisations, dons en
/// nature) est figé côté serveur : une tranche serveur est nécessaire
/// pour l'élargir. PDF exclusivement.
class AttestationsAnnuellesScreen extends StatefulWidget {
  const AttestationsAnnuellesScreen({super.key});

  @override
  State<AttestationsAnnuellesScreen> createState() =>
      _AttestationsAnnuellesScreenState();
}

class _AttestationsAnnuellesScreenState
    extends State<AttestationsAnnuellesScreen> {
  late int _annee;
  String? _memberId;
  List<Member> _membres = [];
  late Future<List<Attestation>> _future;
  bool _working = false;

  /// Attestations signées pendant cette session (voir
  /// AttestationsScreen : la liste serveur n'expose pas l'état signé).
  final Set<String> _signees = {};

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
      .getAttestations(annee: _annee, type: 'don');

  void _refresh() => setState(() => _future = _load());

  /// Délivrance individuelle : génération groupée, puis on retrouve
  /// l'attestation du membre choisi pour l'année.
  Future<void> _delivrer() async {
    if (_memberId == null) {
      showApiError(context, 'Choisissez le membre concerné.');
      return;
    }
    setState(() => _working = true);
    try {
      await context.read<AppState>().api.genererAttestations(annee: _annee);
      final items = await _load();
      if (!mounted) return;
      final sienne = items
          .where((a) => a.memberId == _memberId && a.estEmise)
          .firstOrNull;
      if (sienne == null) {
        showApiError(
          context,
          'Aucun don confirmé pour ce membre en $_annee : aucune attestation délivrée.',
        );
      } else {
        showSuccess(
          context,
          'Attestation ${sienne.numero} délivrée.',
        );
      }
      _refresh();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Signature dessinée (V1) : pad, POST .../signer, puis le PDF signé
  /// est re-téléchargé. Admin et trésorier seulement.
  Future<void> _signer(Attestation a) async {
    final resultat = await montrerDialogueSignature(
      context,
      titre: 'Signer l’attestation ${a.numero}',
      nomInitial: context.read<AppState>().user?.fullName ?? '',
    );
    if (resultat == null || !mounted) return;
    setState(() => _working = true);
    try {
      await context.read<AppState>().api.signerAttestation(
            a.id,
            points: resultat.trace.points,
            imagePng: resultat.trace.pngBytes,
            nomAffiche: resultat.nom,
          );
      if (!mounted) return;
      setState(() => _signees.add(a.id));
      showSuccess(context, 'Attestation ${a.numero} signée.');
      await _telecharger(a);
      _refresh();
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        if (mounted) {
          setState(() => _signees.add(a.id));
          showApiError(context, 'Attestation déjà signée.');
        }
      } else if (mounted) {
        showApiError(context, e);
      }
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
            XFile.fromData(bytes,
                name: '${a.numero}.pdf', mimeType: 'application/pdf'),
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

  @override
  Widget build(BuildContext context) {
    final annees = [for (var i = 0; i < 3; i++) DateTime.now().year - i];
    final peutSigner = context.watch<AppState>().canManageFinances;
    return Scaffold(
      appBar: AppBar(title: const Text('Attestations annuelles')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Le document qui totalise, pour un membre, ses '
                  'cotisations et ses dons d’une année.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (_membres.isEmpty)
                  const Text(
                    'Aucun membre — créez d’abord un membre',
                    style: TextStyle(fontSize: 16),
                  )
                else
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _memberId,
                    decoration: const InputDecoration(
                      labelText: 'Membre *',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Choisir un membre'),
                    items: [
                      for (final m in _membres)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.fullName} (${m.matricule})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _memberId = v),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _annee,
                  decoration: const InputDecoration(
                    labelText: 'Année *',
                    border: OutlineInputBorder(),
                  ),
                  items: annees
                      .map((a) =>
                          DropdownMenuItem(value: a, child: Text('$a')))
                      .toList(),
                  onChanged: (a) {
                    if (a == null) return;
                    setState(() {
                      _annee = a;
                      _future = _load();
                    });
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      _working || _memberId == null ? null : _delivrer,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Délivrer l’attestation', style: TextStyle(fontSize: 13.5)),
                ),
              ],
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
                    message: 'Aucune attestation annuelle délivrée.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: items
                        .map((a) => Card(
                              child: ListTile(
                                leading:
                                    const Icon(Icons.description_outlined),
                                title: Text(
                                    '${a.membreNom ?? 'Donateur'} — ${a.totalFcfa != null ? formatFcfa(a.totalFcfa!) : a.libelle}',
                                style: const TextStyle(fontSize: 13.5)),
                                subtitle: Text(
                                    '${a.numero}${a.nbDons != null ? ' · ${pluriel(a.nbDons!, 'don')}' : ''} · ${formatDate(a.dateEmission)}${a.estEmise ? '' : ' · annulée'}',
                                    style: const TextStyle(fontSize: 11.5)),
                                trailing: a.estEmise
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (peutSigner &&
                                              !_signees.contains(a.id))
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.draw_outlined),
                                              tooltip: 'Signer',
                                              onPressed: () => _signer(a),
                                            ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.download_outlined),
                                            tooltip: 'Voir le PDF',
                                            onPressed: () => _telecharger(a),
                                          ),
                                        ],
                                      )
                                    : const Icon(Icons.cancel_outlined,
                                        color: AppTheme.rougeErreur),
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
