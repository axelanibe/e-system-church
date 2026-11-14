import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/confiance.dart';
import '../models/parametres.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// T11 — Journal d'audit : lecture seule, chaîne de hachage vérifiable,
/// et lectures sensibles journalisées (US17). Aucune route de
/// suppression ou de modification n'existe, côté serveur comme ici.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  List<AuditEntree> _entrees = [];
  List<ConsultationSensible> _consultations = [];
  bool _chargement = true;
  String? _erreur;
  String? _message;
  String? _filtreAction;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final api = context.read<AppState>().api;
      final entrees = await api.getAudit(action: _filtreAction);
      final consultations = await api.getConsultations();
      if (!mounted) return;
      setState(() {
        _entrees = entrees;
        _consultations = consultations;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = messageErreurSimple(e);
        _chargement = false;
      });
    }
  }

  Future<void> _verifierChaine() async {
    try {
      final resultat = await context.read<AppState>().api.verifierAudit();
      if (!mounted) return;
      setState(() {
        _message = resultat.ok
            ? 'Chaîne vérifiée : ${resultat.verifies} ligne(s), aucune rupture.'
            : 'Rupture de chaîne détectée (${resultat.verifies}/${resultat.total} vérifiées).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurSimple(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal d’audit')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_erreur != null)
                    Card(
                      color: AppTheme.rougeErreur.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_erreur!),
                      ),
                    ),
                  if (_message != null)
                    Card(
                      color: AppTheme.vertFonce.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message!),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          // Sans isExpanded, le bouton prend la largeur de
                          // son plus long libellé et déborde de 208 px sur
                          // un téléphone (test d'écran T13).
                          isExpanded: true,
                          initialValue: _filtreAction,
                          decoration: const InputDecoration(
                            labelText: 'Action',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: null, child: Text('Toutes')),
                            DropdownMenuItem(
                                value: 'membre.cree',
                                child: Text('Membre créé')),
                            DropdownMenuItem(
                                value: 'membre.supprime',
                                child: Text('Membre supprimé')),
                            DropdownMenuItem(
                                value: 'contribution.creee',
                                child: Text('Contribution créée')),
                            DropdownMenuItem(
                                value: 'sauvegarde.creee',
                                child: Text('Sauvegarde créée')),
                            DropdownMenuItem(
                                value: 'sauvegarde.restauree',
                                child: Text('Sauvegarde restaurée')),
                            DropdownMenuItem(
                                value: '2fa.activee',
                                child: Text('2FA activée')),
                            DropdownMenuItem(
                                value: '2fa.desactivee',
                                child: Text('2FA désactivée')),
                          ],
                          onChanged: (valeur) {
                            setState(() => _filtreAction = valeur);
                            _charger();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _verifierChaine,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Vérifier'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Journal',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_entrees.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucune ligne dans le journal.'),
                      ),
                    ),
                  for (final entree in _entrees)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.orClair,
                          child: Icon(Icons.fact_check_outlined,
                              color: AppTheme.orFonce),
                        ),
                        title: Text(libelleActionAudit(entree.action)),
                        subtitle: Text(
                          '${entree.utilisateur ?? '—'} · ${formatDateTime(entree.createdAt)}'
                          '${entree.hash == null ? '' : '\nHash : ${entree.hash!.substring(0, 12)}…'}',
                        ),
                        isThreeLine: entree.hash != null,
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Lectures sensibles',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_consultations.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucune lecture sensible journalisée.'),
                      ),
                    ),
                  for (final consultation in _consultations)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.orClair,
                          child: Icon(Icons.visibility_outlined,
                              color: AppTheme.orFonce),
                        ),
                        title: Text(
                          '${consultation.ressourceLabel} · ${consultation.ressourceNom ?? '—'}',
                        ),
                        subtitle: Text(
                          '${consultation.userNom ?? '—'} · ${formatDateTime(consultation.createdAt)}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
