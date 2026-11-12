import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/sycebnl.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// États financiers SYCEBNL (tranche P6) : les quatre états du système
/// normal, générés depuis la vraie comptabilité, en un clic. Textes repris
/// mot pour mot de la projection. Les états restent masqués tant que
/// « Générer mes états financiers » n'a pas été touché, chaque détail reste
/// masqué jusqu'à son bouton « Voir ».
class SycebnlScreen extends StatefulWidget {
  const SycebnlScreen({super.key});

  @override
  State<SycebnlScreen> createState() => _SycebnlScreenState();
}

class _SycebnlScreenState extends State<SycebnlScreen> {
  final _anneeController =
      TextEditingController(text: '${DateTime.now().year}');
  bool _chargement = false;
  EtatsSycebnl? _etats;
  final _detailsVisibles = <String>{};

  @override
  void dispose() {
    _anneeController.dispose();
    super.dispose();
  }

  int get _annee =>
      int.tryParse(_anneeController.text.trim()) ?? DateTime.now().year;

  Future<void> _generer() async {
    final annee = _annee;
    setState(() => _chargement = true);
    try {
      final api = context.read<AppState>().api;
      final exercice = await api.getRapportFinancier(
        annee: annee,
        from: '$annee-01-01',
        to: '$annee-12-31',
      );
      final anterieur = await api.getRapportFinancier(
        to: '$annee-01-01',
      );
      if (!mounted) return;
      setState(() {
        _etats = EtatsSycebnl.depuisRapports(
          annee: annee,
          exercice: exercice,
          anterieur: anterieur,
        );
        _detailsVisibles.clear();
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _chargement = false);
      showApiError(context, e);
    }
  }

  Future<void> _imprimer(String etat, String titre) async {
    final annee = _annee;
    try {
      final bytes = await context.read<AppState>().api.exporterSycebnlPdf(
            etat: etat,
            annee: annee,
          );
      final nom = 'sycebnl-$etat-$annee.pdf';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: nom, mimeType: 'application/pdf'),
          ],
          subject: '$titre SYCEBNL $annee',
        ),
      );
      if (mounted) showSuccess(context, 'Export PDF partagé.');
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _ligne(String label, String valeur, {bool gras = false}) {
    final style = gras
        ? const TextStyle(fontWeight: FontWeight.bold)
        : const TextStyle();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(valeur, style: style),
        ],
      ),
    );
  }

  Widget _carteEtat({
    required String id,
    required String titre,
    required String sousTitre,
    required List<(String, String)> resume,
    required List<(String, String)> detail,
  }) {
    final visible = _detailsVisibles.contains(id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(sousTitre),
            const SizedBox(height: 12),
            for (final (label, valeur) in resume)
              _ligne(label, valeur, gras: true),
            if (visible) ...[
              const Divider(),
              for (final (label, valeur) in detail)
                _ligne(label, valeur),
              const SizedBox(height: 8),
              const Text(
                'À produire depuis votre comptabilité, aucun formulaire officiel à remplir.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        if (visible) {
                          _detailsVisibles.remove(id);
                        } else {
                          _detailsVisibles.add(id);
                        }
                      });
                    },
                    child: const Text('Voir'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _imprimer(id, titre),
                    child: const Text('Imprimer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etats = _etats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('États financiers SYCEBNL'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('← Retour aux finances'),
            ),
          ),
          const Text(
            'Les quatre états du système normal, à produire depuis la comptabilité de votre église.',
          ),
          const SizedBox(height: 12),
          const Card(
            color: AppTheme.fondPapier,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Obligatoire pour les églises avec 50 millions de FCFA de ressources annuelles ou plus, dépôt en ligne avant le 30 mai. En dessous, ce dépôt n\'est pas imposé, mais l\'export reste disponible.',
                style: TextStyle(
                  color: AppTheme.bleuNuit,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SectionTitle(title: 'Cadre de l\'export'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acte uniforme OHADA en vigueur depuis le 1er janvier 2024. Système normal : bilan, compte de résultat, tableau des flux de trésorerie, notes annexes. Dépôt exclusivement numérique, avant le 30 mai de chaque année pour les entités concernées. Premier dépôt le 30 mai 2027, pour l\'exercice clos le 31 décembre 2026.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'À produire depuis votre comptabilité, aucun formulaire officiel à remplir.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.bleuNuit,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _anneeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Année',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _chargement ? null : _generer,
                child: _chargement
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Générer mes états financiers'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Les quatre états s\'affichent vides, prêts à être remplis par les chiffres de votre église.',
          ),
          if (etats != null) ...[
            const SectionTitle(title: 'Les quatre états, système normal'),
            _carteEtat(
              id: 'bilan',
              titre: 'Bilan',
              sousTitre:
                  'L\'actif et le passif de votre église à la clôture de l\'exercice.',
              resume: [
                ('Total de l\'actif', formatFcfa(etats.totalActif)),
                ('Total du passif', formatFcfa(etats.totalPassif)),
              ],
              detail: [
                ('Actif immobilisé', formatFcfa(etats.actifImmobilise)),
                ('Actif circulant', formatFcfa(etats.actifCirculant)),
                ('Trésorerie actif', formatFcfa(etats.tresorerieActif)),
                ('Fonds propres', formatFcfa(etats.fondsPropres)),
                ('Dettes', formatFcfa(etats.dettes)),
                ('Trésorerie passif', formatFcfa(etats.tresoreriePassif)),
              ],
            ),
            _carteEtat(
              id: 'compte_resultat',
              titre: 'Compte de résultat',
              sousTitre:
                  'Les produits et les charges de l\'exercice, et le résultat qui en découle.',
              resume: [
                ('Total des produits', formatFcfa(etats.totalProduits)),
                ('Total des charges', formatFcfa(etats.totalCharges)),
                ('Résultat de l\'exercice', formatFcfa(etats.resultatExercice)),
              ],
              detail: [
                ('Produits d\'exploitation',
                    formatFcfa(etats.produitsExploitation)),
                ('Charges d\'exploitation',
                    formatFcfa(etats.chargesExploitation)),
                ('Produits financiers', formatFcfa(etats.produitsFinanciers)),
                ('Charges financières', formatFcfa(etats.chargesFinancieres)),
                ('Résultat net', formatFcfa(etats.resultatExercice)),
              ],
            ),
            _carteEtat(
              id: 'flux',
              titre: 'Tableau des flux de trésorerie',
              sousTitre:
                  'Les entrées et les sorties de trésorerie de l\'exercice.',
              resume: [
                ('Flux des activités opérationnelles',
                    formatFcfa(etats.fluxOperationnelles)),
                ('Flux des activités d\'investissement',
                    formatFcfa(etats.fluxInvestissement)),
                ('Flux des activités de financement',
                    formatFcfa(etats.fluxFinancement)),
                ('Variation de trésorerie',
                    formatFcfa(etats.variationTresorerie)),
              ],
              detail: [
                ('Trésorerie à l\'ouverture',
                    formatFcfa(etats.tresorerieOuverture)),
                ('Trésorerie à la clôture',
                    formatFcfa(etats.tresorerieCloture)),
              ],
            ),
            _carteEtat(
              id: 'notes',
              titre: 'Notes annexes',
              sousTitre:
                  'Les informations qui complètent et expliquent les trois autres états.',
              resume: [
                ('Notes rédigées', '${etats.notesRedigees}'),
                ('Montants rattachés', formatFcfa(etats.montantsRattaches)),
              ],
              detail: [
                (
                  'Aucune note pour le moment. Vos notes annexes s\'écriront ici, à partir des chiffres de votre comptabilité.',
                  ''
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
