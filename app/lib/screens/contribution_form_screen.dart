import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/campagne.dart';
import '../models/contribution.dart';
import '../models/member.dart';
import '../models/paiements.dart';
import '../services/api_service.dart';
import '../services/file_hors_ligne_service.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

/// Formulaire d'enregistrement d'une contribution (dîme, offrande, don
/// ou cotisation). Les dépenses passent uniquement par l'écran
/// « Nouvelle dépense » : le type « Dépense » n'est plus proposé ici.
/// Ouvert depuis Finances, le type est « cotisation » et figé ; le
/// montant d'une cotisation est verrouillé selon le tarif serveur.
///
/// Quand l'église a configuré des moyens de paiement actifs (« Mon église
/// → Paiements »), le don est exécuté par le serveur via ce moyen :
/// Wave ouvre sa page de paiement, virement / espèces enregistrent la
/// contribution en attente de confirmation par le pasteur. Sans moyen
/// configuré, on retombe sur l'enregistrement manuel avec référence.
/// Une cotisation est toujours saisie à la main, pour un membre précis.
class ContributionFormScreen extends StatefulWidget {
  /// Type présélectionné (ex. « cotisation » depuis l'écran Cotisations).
  final String? initialType;

  const ContributionFormScreen({super.key, this.initialType});

  @override
  State<ContributionFormScreen> createState() => _ContributionFormScreenState();
}

class _ContributionFormScreenState extends State<ContributionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  final _noteController = TextEditingController();
  String _type = 'dime';
  String _paymentMethod = 'especes';
  String? _moyenCode;
  List<EglisePaiement> _moyens = [];
  String? _memberId;
  List<Member> _members = [];
  String? _campagneId;
  List<Campagne> _campagnes = [];
  bool _loading = false;
  String? _error;
  String? _message;
  /// Tarif de cotisation du serveur, quand il est configuré : le
  /// montant est alors affiché et verrouillé, jamais saisi librement.
  int? _tarifCotisation;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null &&
        ['dime', 'offrande', 'don', 'cotisation']
            .contains(widget.initialType)) {
      _type = widget.initialType!;
    }
    _loadMembers();
    _loadMoyens();
    _loadCampagnes();
    if (_type == 'cotisation') _loadTarif();
  }

  /// Tarif de cotisation configuré côté serveur : il verrouille le
  /// montant du champ. Sans tarif configuré, le montant reste libre.
  Future<void> _loadTarif() async {
    try {
      final config =
          await context.read<AppState>().api.getCotisationsConfig();
      if (mounted && config != null) {
        setState(() {
          _tarifCotisation = config.montantFcfa;
          _amountController.text = '${config.montantFcfa}';
        });
      }
    } catch (_) {
      // Sans tarif, le montant reste saisissable.
    }
  }

  /// Campagnes actives de l'église, pour affecter ce don (US2). Une
  /// dépense n'est jamais affectée, et un don payé par un moyen configuré
  /// ne passe pas par ici : le choix n'est proposé qu'en saisie manuelle.
  Future<void> _loadCampagnes() async {
    try {
      final campagnes = await context.read<AppState>().api.getCampagnes();
      if (mounted) {
        setState(() => _campagnes =
            campagnes.where((c) => c.statut == 'active').toList());
      }
    } catch (_) {
      // La campagne est facultative pour le formulaire.
    }
  }

  Future<void> _loadMembers() async {
    try {
      final page = await context.read<AppState>().api.getMembers();
      if (mounted) setState(() => _members = page.membres);
    } catch (_) {
      // La liste des membres est optionnelle pour le formulaire.
    }
  }

  /// Moyens de paiement configurés et actifs de l'église (module 14).
  Future<void> _loadMoyens() async {
    try {
      final state = context.read<AppState>();
      final moyens = await state.api.getMesPaiements(state.church!.id);
      final actifs = moyens.where((m) => m.actif).toList();
      if (mounted) {
        setState(() {
          _moyens = actifs;
          _moyenCode ??= actifs.isEmpty ? null : actifs.first.fournisseurCode;
        });
      }
    } catch (_) {
      // Sans moyen configuré, le formulaire garde la saisie manuelle.
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Devise au format ISO 421 (3 lettres) exigé par l'API de paiement :
  /// « FCFA » devient « XOF ».
  String get _devisePaiement {
    final devise = context.read<AppState>().devise;
    if (devise == 'FCFA') return 'XOF';
    if (RegExp(r'^[A-Z]{3}$').hasMatch(devise)) return devise;
    return 'XOF';
  }

  /// Vrai quand le don passe par un moyen configuré de l'église
  /// (l'exécution serveur ne couvre ni les dépenses ni les cotisations).
  bool get _viaMoyenConfigure =>
      _moyens.isNotEmpty &&
      _moyenCode != null &&
      _type != 'depense' &&
      _type != 'cotisation';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_memberId == null) {
      setState(() => _error = 'Un membre est requis.');
      return;
    }
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      if (_viaMoyenConfigure) {
        await _executerPaiement(amount);
      } else {
        try {
          await state.api.createContribution(
                type: _type,
                amountFcfa: amount,
                paymentMethod: _paymentMethod,
                paymentRef: _refController.text.trim().isEmpty
                    ? null
                    : _refController.text.trim(),
                memberId: _memberId,
                campagneId: _type == 'depense' ? null : _campagneId,
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
              );
        } on ApiException catch (e) {
          // Hors ligne : la saisie est mise en file sur l'appareil,
          // elle sera rejouée à la reconnexion, sans doublon.
          if (e.code == 'hors_ligne' && state.user != null) {
            await FileHorsLigneService().ajouter(
              state.user!.id,
              typeAction: 'contribution.creer',
              charge: {
                'type': _type,
                'amount_fcfa': amount,
                'payment_method': _paymentMethod,
                if (_refController.text.trim().isNotEmpty)
                  'payment_ref': _refController.text.trim(),
                if (_memberId != null) 'member_id': _memberId,
                if (_type != 'depense' && _campagneId != null)
                  'campagne_id': _campagneId,
                if (_noteController.text.trim().isNotEmpty)
                  'note': _noteController.text.trim(),
              },
            );
            if (mounted) {
              setState(() {
                _message =
                    'Hors ligne : contribution enregistrée, elle sera envoyée à la reconnexion.';
              });
            }
            return;
          }
          rethrow;
        }
        if (mounted) Navigator.of(context).pop(_type);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Exécute le don côté serveur avec le moyen choisi, puis guide le
  /// donateur (page Wave, ou confirmation manuelle pour virement/espèces).
  Future<void> _executerPaiement(int amount) async {
    final state = context.read<AppState>();
    final apiBaseUrl = state.apiBaseUrl;
    final result = await state.api.executerPaiement(
      fournisseurCode: _moyenCode!,
      type: _type,
      montant: amount,
      devise: _devisePaiement,
      memberId: _memberId,
      // Pas de page de retour dédiée côté serveur pour l'instant :
      // ces URL renvoient la 404 de l'API.
      successUrl: '$apiBaseUrl/paiement/succes',
      errorUrl: '$apiBaseUrl/paiement/echec',
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    if (!mounted) return;
    final launchUrl = result['launch_url'] as String?;
    final moyen =
        _moyens.where((m) => m.fournisseurCode == _moyenCode).firstOrNull;
    final moyenNom = moyen?.fournisseurNom ?? _moyenCode!;
    if (launchUrl != null) {
      final ouvert = await _ouvrirLien(launchUrl);
      if (!mounted) return;
      await _showPaiementDialog(
        title: 'Paiement $moyenNom',
        message:
            'La ${_type == 'depense' ? 'dépense' : 'contribution'} de ${formatMontant(amount, state.devise)} est '
            'enregistrée en attente de confirmation.\n\n'
            '${ouvert ? 'La page de paiement est ouverte dans le navigateur.' : 'Le lien de paiement n’a pas pu s’ouvrir automatiquement : copiez-le ci-dessous.'}',
        launchUrl: ouvert ? null : launchUrl,
      );
    } else {
      await _showPaiementDialog(
        title: _type == 'depense'
            ? 'Dépense enregistrée'
            : 'Contribution enregistrée',
        message:
            'La ${_type == 'depense' ? 'dépense' : 'contribution'} de ${formatMontant(amount, state.devise)} par '
            '$moyenNom est enregistrée en attente : seul le pasteur peut la confirmer.',
      );
    }
    if (mounted) Navigator.of(context).pop(_type);
  }

  /// Ouvre le lien dans le navigateur externe. Faux si impossible.
  Future<bool> _ouvrirLien(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Dialogue de fin de paiement, avec le lien à copier si besoin.
  Future<void> _showPaiementDialog({
    required String title,
    required String message,
    String? launchUrl,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (launchUrl != null) ...[
              const SizedBox(height: 12),
              SelectableText(launchUrl),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: launchUrl));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lien copié.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copier le lien', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devise = context.watch<AppState>().devise;
    return Scaffold(
      appBar: AppBar(
          title: Text(_type == 'depense'
              ? 'Nouvelle dépense'
              : 'Nouvelle contribution')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Saisir une contribution : type, montant et moyen.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  // Membre obligatoire : sans membre, l'état vide de la
                  // maquette, pas un sélecteur vide.
                  if (_members.isEmpty)
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
                      validator: (v) {
                        if (v == null) {
                          return 'Un membre est requis.';
                        }
                        return null;
                      },
                      items: [
                        for (final m in _members)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text('${m.fullName} (${m.matricule})'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _memberId = v),
                    ),
                  const SizedBox(height: 12),
                  // Type figé quand l'écran l'impose (ex. « cotisation »
                  // depuis Finances) : il s'affiche, il ne se choisit pas.
                  if (widget.initialType != null)
                    TextFormField(
                      initialValue: Contribution.labelForType(_type),
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Type *',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: 'Type *',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'dime', child: Text('Dîme')),
                        DropdownMenuItem(
                            value: 'offrande', child: Text('Offrande')),
                        DropdownMenuItem(value: 'don', child: Text('Don')),
                        DropdownMenuItem(
                            value: 'cotisation',
                            child: Text('Cotisation')),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'dime'),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amountController,
                    enabled: _type != 'cotisation' ||
                        _tarifCotisation == null,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Montant ($devise) *',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final amount = int.tryParse(v?.trim() ?? '');
                      if (amount == null || amount <= 0) {
                        return 'Montant invalide.';
                      }
                      return null;
                    },
                  ),
                  if (_type == 'cotisation' &&
                      _tarifCotisation != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Pour une cotisation, le montant est verrouillé selon le tarif : il s’affiche, il ne se tape pas librement.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_moyens.isNotEmpty)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _moyenCode,
                      decoration: const InputDecoration(
                        labelText: 'Moyen de paiement *',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final m in _moyens)
                          DropdownMenuItem(
                            value: m.fournisseurCode,
                            child: Text(
                              m.libelle != null && m.libelle!.isNotEmpty
                                  ? '${m.fournisseurNom} — ${m.libelle}'
                                  : m.fournisseurNom,
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _moyenCode = v),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Moyen de paiement *',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'wave', child: Text('Wave')),
                        DropdownMenuItem(
                            value: 'orange_money',
                            child: Text('Orange Money')),
                        DropdownMenuItem(
                            value: 'mtn_momo', child: Text('MTN MoMo')),
                        DropdownMenuItem(
                            value: 'especes', child: Text('Espèces')),
                        DropdownMenuItem(
                            value: 'virement', child: Text('Virement')),
                      ],
                      onChanged: (v) =>
                          setState(() => _paymentMethod = v ?? 'especes'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aucun moyen de paiement configuré.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _refController,
                    decoration: const InputDecoration(
                      labelText: 'Référence (facultatif)',
                      hintText: 'Référence du paiement',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Total avant envoi : ${formatFcfa(int.tryParse(_amountController.text.trim()) ?? 0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_type != 'depense' &&
                      _type != 'cotisation' &&
                      !_viaMoyenConfigure) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: _campagneId,
                      decoration: const InputDecoration(
                        labelText: 'Campagne (facultatif)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— Fonds général —')),
                        for (final c in _campagnes)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nom),
                          ),
                      ],
                      onChanged: (v) => setState(() => _campagneId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Seul le pasteur confirme la contribution.',
                    style: TextStyle(fontSize: 11.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer la contribution', style: TextStyle(fontSize: 13.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
