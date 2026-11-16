import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/finances.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Nouvelle dépense (maquette, écran 24) : seule voie de saisie d'une
/// dépense, depuis la ligne « Dépenses » de Finances.
///
/// Référence : générée automatiquement par le serveur (DEP-AAAA-NNNN),
/// jamais inventée côté application : aucun numéro n'est affiché avant
/// l'enregistrement. Justificatif : photo ou fichier choisi sur
/// l'appareil, jamais une URL à coller ; le serveur n'a pas de support
/// multipart, seul le nom du fichier est enregistré comme référence du
/// justificatif.
class NouvelleDepenseScreen extends StatefulWidget {
  const NouvelleDepenseScreen({super.key});

  @override
  State<NouvelleDepenseScreen> createState() => _NouvelleDepenseScreenState();
}

class _NouvelleDepenseScreenState extends State<NouvelleDepenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montantController = TextEditingController();
  final _descriptionController = TextEditingController();
  late Future<List<PosteBudgetaire>> _postesFuture;
  String? _posteId;
  String? _nomJustificatif;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _postesFuture = context.read<AppState>().api.getPostesBudgetaires();
  }

  @override
  void dispose() {
    _montantController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _choisirJustificatif() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    setState(() => _nomJustificatif = result.files.single.name);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final montant = int.tryParse(_montantController.text.trim());
    if (montant == null || montant <= 0) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final creee = await context.read<AppState>().api.creerDepenseComplete(
            posteId: _posteId,
            montantFcfa: montant,
            motif: _descriptionController.text.trim(),
            justificatifRef: _nomJustificatif,
          );
      if (!mounted) return;
      showSuccess(
        context,
        'Dépense enregistrée (${creee.reference ?? 'sans référence'}).',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devise = context.watch<AppState>().devise;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle dépense')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FutureBuilder<List<PosteBudgetaire>>(
              future: _postesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoading();
                }
                if (snapshot.hasError) {
                  return AppError(
                    message: snapshot.error.toString(),
                    onRetry: () => setState(() => _postesFuture = context
                        .read<AppState>()
                        .api
                        .getPostesBudgetaires()),
                  );
                }
                final postes = snapshot.data!;
                return Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Référence',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Générée automatiquement',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      if (postes.isEmpty)
                        const Text(
                          'Aucun poste dans le plan comptable — créez d’abord un poste.',
                          style: TextStyle(fontSize: 16),
                        )
                      else
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _posteId,
                          decoration: const InputDecoration(
                            labelText: 'Catégorie *',
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Choisir dans le plan comptable'),
                          validator: (v) =>
                              v == null ? 'Choisissez une catégorie.' : null,
                          items: [
                            for (final p in postes)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text(p.nom),
                              ),
                          ],
                          onChanged: (v) => setState(() => _posteId = v),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _montantController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Montant ($devise) *',
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
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description (facultatif)',
                          hintText: 'À quoi correspond la dépense',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Justificatif',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Photo ou fichier — jamais une URL à coller',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _choisirJustificatif,
                        icon: const Icon(Icons.attach_file_outlined),
                        label: Text(_nomJustificatif ?? 'Joindre un justificatif',
                            style: const TextStyle(fontSize: 13)),
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
                        onPressed: _loading || postes.isEmpty ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Enregistrer la dépense', style: TextStyle(fontSize: 13.5)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
