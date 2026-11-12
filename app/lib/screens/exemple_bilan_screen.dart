import 'package:flutter/material.dart';

import '../widgets/common_widgets.dart';

/// Exemple de bilan annuel (tranche P5) : à quoi ressemble un bilan
/// annuel rempli. Chiffres repris mot pour mot de la projection
/// validée par Axel le 12 novembre 2026, marqués EXEMPLE partout :
/// ce ne sont pas les données de votre église. Les vrais rapports
/// partent des vraies données, à 0 tant que l'église n'a pas de
/// données.
class ExempleBilanScreen extends StatelessWidget {
  const ExempleBilanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bilan annuel')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Exemple de rapport envoyé par une église annexe à son '
                  'église mère.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'EXEMPLE',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ces chiffres sont des chiffres d’exemple. Ils ne sont '
                  'pas les données de votre église.',
                  style: TextStyle(fontSize: 16),
                ),
                const SectionTitle(title: 'Membres'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _Ligne('Membres inscrits', '120'),
                        _Ligne('Nouveaux membres', '18'),
                        _Ligne('Présence moyenne au culte', '86'),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Finances'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _Ligne('Recettes', '2 450 000 FCFA'),
                        _Ligne('Dépenses', '1 980 000 FCFA'),
                        _Ligne('Solde', '470 000 FCFA'),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Cultes et activités'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _Ligne('Cultes tenus', '52'),
                        _Ligne('Études bibliques', '48'),
                        _Ligne('Réunions de prière', '24'),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(title: 'Projets'),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _Ligne(
                          'Rénovation du lieu de culte',
                          'En cours',
                        ),
                        _Ligne(
                          'Matériel de sonorisation',
                          'Achat prévu',
                        ),
                        _Ligne(
                          'Action sociale du quartier',
                          'À l’étude',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Exemple seulement. Vos vrais rapports partent de vos '
                  'vraies données.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('← Retour aux rapports'),
                ),
              ],
            ),
          ),
        ),
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
