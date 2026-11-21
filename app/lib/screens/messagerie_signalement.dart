import 'package:flutter/material.dart';

import '../models/messagerie.dart';
import '../services/api_service.dart';

/// Feuille de signalement (T-Msg-4).
///
/// Motif, description facultative de 500 caractères maximum,
/// destinataire (modérateurs de mon église ou église mère), et une
/// phrase qui explique clairement qui verra le signalement, avant
/// l'envoi : la personne signalée ne voit jamais le nom du
/// rapporteur. La sécurité d'un enfant part toujours vers le
/// référent protection de l'enfance, hors du circuit ordinaire,
/// quel que soit le destinataire choisi.
Future<void> ouvrirFeuilleSignalement(
  BuildContext context, {
  required ApiService api,
  required String targetType,
  required String targetId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _FeuilleSignalement(
      api: api,
      targetType: targetType,
      targetId: targetId,
    ),
  );
}

class _FeuilleSignalement extends StatefulWidget {
  final ApiService api;
  final String targetType;
  final String targetId;

  const _FeuilleSignalement({
    required this.api,
    required this.targetType,
    required this.targetId,
  });

  @override
  State<_FeuilleSignalement> createState() => _FeuilleSignalementState();
}

class _FeuilleSignalementState extends State<_FeuilleSignalement> {
  String _motif = 'harassment';
  String _destinataire = 'local';
  final _descriptionController = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.api.signalerContenu(
        targetType: widget.targetType,
        targetId: widget.targetId,
        motif: _motif,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        destinataire: _destinataire,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signalement envoyé. Merci.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Signaler',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _motif,
            decoration: const InputDecoration(
              labelText: 'Motif *',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: [
              for (final motif in motifsSignalement)
                DropdownMenuItem<String>(
                  value: motif,
                  child: Text(
                    libelleMotifSignalement(motif),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            onChanged: (valeur) =>
                setState(() => _motif = valeur ?? 'other'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _destinataire,
            decoration: const InputDecoration(
              labelText: 'Transmettre à *',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: [
              for (final destinataire in destinatairesSignalement)
                DropdownMenuItem<String>(
                  value: destinataire,
                  child: Text(
                    libelleDestinataireSignalement(destinataire),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            onChanged: (valeur) =>
                setState(() => _destinataire = valeur ?? 'local'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (facultative)',
              hintText: 'Précisez ce qui s’est passé…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            phraseVisibiliteSignalement(_destinataire, _motif),
            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(
              _erreur!,
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _enCours ? null : _envoyer,
              child: _enCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Envoyer le signalement'),
            ),
          ),
        ],
      ),
    );
  }
}
