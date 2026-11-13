import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/abonnement.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Mon abonnement (tranche P3) : abonnement annuel de l'église mère,
/// 200 000 FCFA par an, couvrant l'église mère et toutes ses annexes.
/// Textes repris mot pour mot de la projection validée par Axel le
/// 12 novembre 2026. Aucune date d'expiration, aucun code promo ni
/// moyen de paiement inventé : l'expiration affiche « À compléter »
/// tant qu'elle n'est pas renseignée, et le moyen de paiement n'est
/// pas encore décidé.
class AbonnementScreen extends StatefulWidget {
  /// Vrai pour prévisualiser la vue d'une annexe depuis l'écran mère.
  final bool vueAnnexe;

  const AbonnementScreen({super.key, this.vueAnnexe = false});

  @override
  State<AbonnementScreen> createState() => _AbonnementScreenState();
}

class _AbonnementScreenState extends State<AbonnementScreen> {
  late Future<Abonnement> _future;
  int _dureeAnnees = 1;
  final TextEditingController _codePromo = TextEditingController();
  ValidationCodePromo? _promoValidee;
  bool _envoiPromo = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getMonAbonnement();
  }

  @override
  void dispose() {
    _codePromo.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
        _future = context.read<AppState>().api.getMonAbonnement();
        _promoValidee = null;
      });

  int get _totalAffiche =>
      _promoValidee?.totalApres ?? tarifsAbonnement[_dureeAnnees]!;

  Future<void> _appliquerCodePromo() async {
    final code = _codePromo.text.trim();
    if (code.isEmpty) {
      showApiError(context, 'Entrez votre code promo.');
      return;
    }
    setState(() => _envoiPromo = true);
    try {
      final resultat = await context.read<AppState>().api.validerCodePromo(
            code: code,
            dureeAnnees: _dureeAnnees,
          );
      if (!mounted) return;
      // La réduction réelle s'affiche dans la carte sous le champ.
      setState(() => _promoValidee = resultat);
    } on ApiException catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _envoiPromo = false);
    }
  }

  void _renouveler() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Le moyen de paiement du renouvellement n’est pas encore décidé.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estMere = context.watch<AppState>().church?.isMere ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon abonnement')),
      body: FutureBuilder<Abonnement>(
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
                  const Text('Impossible de charger l’abonnement.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          final abonnement = snapshot.data!;
          final vueAnnexe = widget.vueAnnexe || abonnement.estAnnexe;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: vueAnnexe
                    ? _VueAnnexe(egliseMereNom: abonnement.egliseMereNom)
                    : _VueMere(
                        abonnement: abonnement,
                        dureeAnnees: _dureeAnnees,
                        totalAffiche: _totalAffiche,
                        promoValidee: _promoValidee,
                        codePromo: _codePromo,
                        envoiPromo: _envoiPromo,
                        onDuree: (duree) => setState(() {
                          _dureeAnnees = duree;
                          _promoValidee = null;
                        }),
                        onAppliquer: _appliquerCodePromo,
                        onRenouveler: _renouveler,
                        estMere: estMere,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Vue église mère : plan, durée, code promo, encadré Important,
/// bouton Renouveler, et lien vers la vue d'une annexe.
class _VueMere extends StatelessWidget {
  final Abonnement abonnement;
  final int dureeAnnees;
  final int totalAffiche;
  final ValidationCodePromo? promoValidee;
  final TextEditingController codePromo;
  final bool envoiPromo;
  final ValueChanged<int> onDuree;
  final VoidCallback onAppliquer;
  final VoidCallback onRenouveler;
  final bool estMere;

  const _VueMere({
    required this.abonnement,
    required this.dureeAnnees,
    required this.totalAffiche,
    required this.promoValidee,
    required this.codePromo,
    required this.envoiPromo,
    required this.onDuree,
    required this.onAppliquer,
    required this.onRenouveler,
    required this.estMere,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'L’abonnement de votre église mère.',
          style: TextStyle(fontSize: 16),
        ),
        if (abonnement.lectureSeule) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Votre abonnement est expiré. L’application est en lecture seule.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        const SectionTitle(title: 'Mon plan'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Abonnement annuel',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatFcfa(abonnement.montantFcfa)} par an. '
                  'Il couvre l’église mère et toutes ses annexes.',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                Text(
                  'Essai gratuit : ${abonnement.essaiJours} jours pour '
                  'essayer l’application avant de payer.',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Statut : ${abonnement.statutLibelle}',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  abonnement.dateExpiration == null
                      ? 'Date d’expiration : À compléter'
                      : 'Date d’expiration : ${formatDate(abonnement.dateExpiration)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle(title: 'Durée'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choisissez la durée. La remise grandit avec la durée.',
                  style: TextStyle(fontSize: 16),
                ),
                RadioGroup<int>(
                  groupValue: dureeAnnees,
                  onChanged: (v) {
                    if (v != null) onDuree(v);
                  },
                  child: Column(
                    children: [1, 3, 10].map((duree) {
                      final tarif = tarifsAbonnement[duree]!;
                      final ancien = ancienTarifAbonnement(duree);
                      return RadioListTile<int>(
                        contentPadding: EdgeInsets.zero,
                        value: duree,
                        title: Text(
                          '$duree ${duree == 1 ? 'an' : 'ans'}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        subtitle: Text(
                          ancien == null
                              ? formatFcfa(tarif)
                              : '${formatFcfa(tarif)}, au lieu de ${formatFcfa(ancien)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(),
                Text(
                  'Total pour $dureeAnnees ${dureeAnnees == 1 ? 'an' : 'ans'} : ${formatFcfa(totalAffiche)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'La remise de durée est déjà incluse dans le total affiché.',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle(title: 'Code promo'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codePromo,
                        decoration: const InputDecoration(
                          labelText: 'Code promo',
                          hintText: 'Code promo',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: envoiPromo ? null : onAppliquer,
                      child: const Text('Appliquer'),
                    ),
                  ],
                ),
                if (promoValidee != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Code ${promoValidee!.code} appliqué : '
                    '${formatFcfa(promoValidee!.totalAvant)} → '
                    '${formatFcfa(promoValidee!.totalApres)}.',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'La réduction dépend du code.',
                  style: TextStyle(fontSize: 16),
                ),
                const Text(
                  'Codes promo réservés au lancement, avec une date de fin.',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'À l’expiration, l’application passe en lecture seule, '
                  'toutes les fonctionnalités s’interrompent automatiquement.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Rappels avant l’expiration, puis 30 jours de grâce '
                  'avant la lecture seule.',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onRenouveler,
          child: const Text('Renouveler mon abonnement'),
        ),
        const SizedBox(height: 16),
        if (estMere) ...[
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AbonnementScreen(vueAnnexe: true),
                ),
              );
            },
            child: const Text('Voir la vue d’une annexe'),
          ),
          const Text(
            'Une annexe voit un écran différent, sans paiement.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ],
      ],
    );
  }
}

/// Vue annexe : seule la couverture par l'abonnement de l'église
/// mère, sans prix, durée, promo ni renouvellement.
class _VueAnnexe extends StatelessWidget {
  final String? egliseMereNom;

  const _VueAnnexe({this.egliseMereNom});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Votre accès est couvert par l’abonnement de votre église mère.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            if (egliseMereNom != null) ...[
              const SizedBox(height: 8),
              Text(
                egliseMereNom!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
