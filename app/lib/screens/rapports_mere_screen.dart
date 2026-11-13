import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/rapport_annexe.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import 'exemple_bilan_screen.dart';
import 'rapports_recus_screen.dart';

class _DonneesRapport {
  final EgliseMereContact mere;
  final int membres;
  final int recettesFcfa;
  final int depensesFcfa;

  const _DonneesRapport({
    required this.mere,
    required this.membres,
    required this.recettesFcfa,
    required this.depensesFcfa,
  });

  int get soldeFcfa => recettesFcfa - depensesFcfa;
}

/// Rapports à mon église mère (tranche P5) : l'annexe choisit le type
/// de rapport, l'application le génère depuis ses vraies données et
/// l'envoie par e-mail à son église mère, en pièce jointe PDF.
/// Textes repris mot pour mot de la projection validée par Axel le
/// 12 novembre 2026. L'aperçu réel reste à 0 tant que l'église n'a
/// pas de données, l'adresse e-mail affiche « À compléter » tant
/// qu'elle n'est pas renseignée en base.
/// L'envoi par e-mail passe par mailer.ts (Lot B) : en attendant, le
/// bouton enregistre le rapport, visible par la mère dans
/// « Rapports reçus », et l'envoi est marqué en attente du Lot B,
/// jamais présenté comme envoyé.
class RapportsMereScreen extends StatefulWidget {
  const RapportsMereScreen({super.key});

  @override
  State<RapportsMereScreen> createState() => _RapportsMereScreenState();
}

class _RapportsMereScreenState extends State<RapportsMereScreen> {
  late Future<_DonneesRapport> _future;
  String _type = 'bilan_annuel';
  final TextEditingController _message = TextEditingController();
  bool _apercuGenere = false;
  bool _envoi = false;
  RapportAnnexe? _envoye;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<_DonneesRapport> _load() async {
    final api = context.read<AppState>().api;
    final mere = await api.getMaMere();
    final membres = await api.getMembers();
    var recettes = 0;
    var depenses = 0;
    try {
      final page = await api.getContributions();
      for (final entry in page.totaux.entries) {
        if (entry.key == 'depense') {
          depenses += entry.value.totalFcfa;
        } else {
          recettes += entry.value.totalFcfa;
        }
      }
    } catch (_) {
      recettes = 0;
      depenses = 0;
    }
    return _DonneesRapport(
      mere: mere,
      membres: membres.total,
      recettesFcfa: recettes,
      depensesFcfa: depenses,
    );
  }

  void _refresh() => setState(() {
        _future = _load();
        _apercuGenere = false;
        _envoye = null;
      });

  Future<void> _contacter() async {
    final donnees = await _future;
    final email = donnees.mere.email;
    if (email == null || email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Adresse e-mail de votre église mère : À compléter.',
            ),
          ),
        );
      }
      return;
    }
    final ouvert = await launchUrl(Uri.parse('mailto:$email'));
    if (!ouvert && mounted) {
      showApiError(context, 'Impossible d’ouvrir la messagerie.');
    }
  }

  Future<void> _envoyer(_DonneesRapport donnees) async {
    setState(() => _envoi = true);
    try {
      final rapport =
          await context.read<AppState>().api.envoyerRapportAnnexe(
                type: _type,
                message:
                    _message.text.trim().isEmpty ? null : _message.text.trim(),
                membres: donnees.membres,
                recettesFcfa: donnees.recettesFcfa,
                depensesFcfa: donnees.depensesFcfa,
                soldeFcfa: donnees.soldeFcfa,
              );
      if (!mounted) return;
      setState(() => _envoye = rapport);
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estMere = context.watch<AppState>().church?.isMere ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Rapports à mon église mère')),
      body: estMere
          ? EmptyState(
              icon: Icons.mail_outline,
              message: 'Cet écran est pour une église annexe. Une église '
                  'mère lit les rapports dans « Rapports reçus ».',
              actionLabel: 'Voir les rapports reçus',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RapportsRecusScreen(),
                ),
              ),
            )
          : FutureBuilder<_DonneesRapport>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Impossible de charger les rapports.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _refresh,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  );
                }
                final donnees = snapshot.data!;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Contactez votre église mère et envoyez vos '
                            'rapports par e-mail, directement depuis votre '
                            'espace.',
                            style: TextStyle(fontSize: 16),
                          ),
                          const SectionTitle(title: 'Mon église mère'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    donnees.mere.nom,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Adresse e-mail : ${donnees.mere.email ?? 'À compléter'}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _contacter,
                                    icon: const Icon(Icons.email_outlined),
                                    label: const Text(
                                      'Contacter mon église mère',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SectionTitle(title: 'Envoyer un rapport'),
                          const Text(
                            'Le rapport se prépare en cinq étapes.',
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          const _Etape(
                            numero: '1',
                            titre: 'Choisir le type de rapport',
                            texte:
                                'Bilan annuel, bilan d’activité ou rapport financier.',
                          ),
                          const _Etape(
                            numero: '2',
                            titre: 'Générer le rapport',
                            texte:
                                'L’application remplit le rapport avec les données de votre église.',
                          ),
                          const _Etape(
                            numero: '3',
                            titre: 'Relire l’aperçu',
                            texte:
                                'Vous relisez le rapport avant l’envoi.',
                          ),
                          const _Etape(
                            numero: '4',
                            titre: 'Envoyer à votre église mère',
                            texte:
                                'Le rapport est enregistré pour votre église mère. L’envoi par e-mail sera activé prochainement.',
                          ),
                          const _Etape(
                            numero: '5',
                            titre: 'Confirmation',
                            texte:
                                'Vous voyez que le rapport est bien enregistré.',
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Type de rapport',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          RadioGroup<String>(
                            groupValue: _type,
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _type = v;
                                  _apercuGenere = false;
                                  _envoye = null;
                                });
                              }
                            },
                            child: Column(
                              children: typesRapportAnnexe.entries
                                  .map(
                                    (e) => RadioListTile<String>(
                                      contentPadding: EdgeInsets.zero,
                                      value: e.key,
                                      title: Text(
                                        e.value,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _message,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Message',
                              hintText: 'Votre message à votre église mère',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () =>
                                setState(() => _apercuGenere = true),
                            child: const Text('Générer mon rapport'),
                          ),
                          if (_apercuGenere) ...[
                            const SectionTitle(title: 'Aperçu du rapport'),
                            const Text(
                              'Généré depuis vos vraies données.',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Ligne(
                                      'Type',
                                      typesRapportAnnexe[_type]!,
                                    ),
                                    _Ligne(
                                      'Membres',
                                      '${donnees.membres}',
                                    ),
                                    _Ligne(
                                      'Recettes',
                                      formatFcfa(donnees.recettesFcfa),
                                    ),
                                    _Ligne(
                                      'Dépenses',
                                      formatFcfa(donnees.depensesFcfa),
                                    ),
                                    _Ligne(
                                      'Solde',
                                      formatFcfa(donnees.soldeFcfa),
                                    ),
                                    _Ligne(
                                      'Destinataire',
                                      'Votre église mère, adresse e-mail : '
                                      '${donnees.mere.email ?? 'À compléter'}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _envoi || _envoye != null
                                  ? null
                                  : () => _envoyer(donnees),
                              icon: const Icon(Icons.email_outlined),
                              label: const Text(
                                'Envoyer à mon église mère',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'L’envoi par e-mail sera activé prochainement : '
                              'le rapport est déjà enregistré, votre église '
                              'mère le voit dans « Rapports reçus ».',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                          ],
                          if (_envoye != null) ...[
                            const SizedBox(height: 16),
                            const Card(
                              color: AppTheme.orClair,
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Rapport enregistré pour votre église mère',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Votre église mère le verra dans '
                                      '« Rapports reçus ». Elle le recevra '
                                      'par e-mail, en pièce jointe PDF, quand '
                                      'l’envoi sera activé.',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SectionTitle(title: 'Exemple de rapport'),
                          const Text(
                            'Voyez à quoi ressemble un bilan annuel rempli. '
                            'Les chiffres sont des chiffres d’exemple.',
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ExempleBilanScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('Voir un exemple de rapport'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Etape extends StatelessWidget {
  final String numero;
  final String titre;
  final String texte;

  const _Etape({
    required this.numero,
    required this.titre,
    required this.texte,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(numero, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(texte, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  final String libelle;
  final String valeur;

  const _Ligne(this.libelle, this.valeur);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(libelle, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
