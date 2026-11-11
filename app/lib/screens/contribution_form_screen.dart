import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/campagne.dart';
import '../models/member.dart';
import '../models/paiements.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

/// Formulaire d'enregistrement d'une contribution (dîme, offrande, don ou
/// dépense).
///
/// Quand l'église a configuré des moyens de paiement actifs (« Mon église
/// → Paiements »), le don est exécuté par le serveur via ce moyen :
/// Wave ouvre sa page de paiement, virement / espèces enregistrent la
/// contribution en attente de confirmation par le trésorier. Sans moyen
/// configuré, on retombe sur l'enregistrement manuel avec référence.
class ContributionFormScreen extends StatefulWidget {
  const ContributionFormScreen({super.key});

  @override
  State<ContributionFormScreen> createState() => _ContributionFormScreenState();
}

class _ContributionFormScreenState extends State<ContributionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  final _noteController = TextEditingController();
  String _type = 'dime';
  String _paymentMethod = 'wave';
  String? _moyenCode;
  List<EglisePaiement> _moyens = [];
  String? _memberId;
  List<Member> _members = [];
  String? _campagneId;
  List<Campagne> _campagnes = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadMoyens();
    _loadCampagnes();
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
  /// (l'exécution serveur ne couvre pas les dépenses).
  bool get _viaMoyenConfigure =>
      _moyens.isNotEmpty && _moyenCode != null && _type != 'depense';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_viaMoyenConfigure) {
        await _executerPaiement(amount);
      } else {
        await context.read<AppState>().api.createContribution(
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
        if (mounted) Navigator.of(context).pop(true);
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
            'La contribution de ${formatMontant(amount, state.devise)} est '
            'enregistrée en attente de confirmation.\n\n'
            '${ouvert ? 'La page de paiement est ouverte dans le navigateur.' : 'Le lien de paiement n’a pas pu s’ouvrir automatiquement : copiez-le ci-dessous.'}',
        launchUrl: ouvert ? null : launchUrl,
      );
    } else {
      await _showPaiementDialog(
        title: 'Contribution enregistrée',
        message:
            'La contribution de ${formatMontant(amount, state.devise)} par '
            '$moyenNom est enregistrée en attente : elle devra être '
            'confirmée par le trésorier.',
      );
    }
    if (mounted) Navigator.of(context).pop(true);
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
                label: const Text('Copier le lien'),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devise = context.watch<AppState>().devise;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle contribution')),
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
                          value: 'depense', child: Text('Dépense')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'dime'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Montant ($devise) *',
                      hintText: 'Ex. 10000',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final amount = int.tryParse(v?.trim() ?? '');
                      if (amount == null || amount <= 0) {
                        return 'Montant invalide.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_moyens.isNotEmpty)
                    DropdownButtonFormField<String>(
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
                          setState(() => _paymentMethod = v ?? 'wave'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aucun moyen de paiement configuré pour l’instant : '
                      'configurez-en un dans « Mon église → Paiements ».',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _refController,
                    decoration: const InputDecoration(
                      labelText: 'Référence de paiement',
                      hintText: 'Ex. WAVE-123456',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _memberId,
                    decoration: const InputDecoration(
                      labelText: 'Membre (facultatif)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— Aucun —')),
                      for (final m in _members)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.fullName} (${m.matricule})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _memberId = v),
                  ),
                  if (_type != 'depense' && !_viaMoyenConfigure) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
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
                          : const Text('Enregistrer'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La contribution est enregistrée « en attente » : un admin ou un trésorier devra la confirmer.',
                    textAlign: TextAlign.center,
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
