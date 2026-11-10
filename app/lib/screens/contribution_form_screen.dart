import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../state/app_state.dart';

/// Formulaire d'enregistrement d'une contribution (dîme, offrande, don ou
/// dépense). Enregistrement manuel avec référence Mobile Money en MVP.
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
  String? _memberId;
  List<Member> _members = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final page = await context.read<AppState>().api.getMembers();
      if (mounted) setState(() => _members = page.membres);
    } catch (_) {
      // La liste des membres est optionnelle pour le formulaire.
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _noteController.dispose();
    super.dispose();
  }

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
      await context.read<AppState>().api.createContribution(
            type: _type,
            amountFcfa: amount,
            paymentMethod: _paymentMethod,
            paymentRef: _refController.text.trim().isEmpty
                ? null
                : _refController.text.trim(),
            memberId: _memberId,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    decoration: const InputDecoration(
                      labelText: 'Montant (FCFA) *',
                      hintText: 'Ex. 10000',
                      border: OutlineInputBorder(),
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
