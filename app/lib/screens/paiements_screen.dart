import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/paiements.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Module 14 — « Paiements automatiques » (maquette, écran 35) :
/// prélèvements programmés (aucun pour l'instant, aucune date ni
/// montant inventé) et renvoi vers l'état des comptes marchands.
///
/// Cet écran ne gère que les échéances : montant, fréquence, membre
/// concerné. Aucune clé ne se saisit ici, aucun compte marchand ne
/// s'y configure : l'état des comptes se voit dans Finances
/// (« État des comptes marchands »), les clés se saisissent
/// uniquement dans Réglages et confidentialité. Les 3 fournisseurs
/// sont Wave, Orange Money et MTN Mobile Money : pas de Virement ni
/// d'Espèces, pas de sélecteur de pays.
///
/// Les identifiants ne sont jamais affichés : l'API ne renvoie que
/// l'aperçu masqué (`••••1234`) et l'état « configuré ».
class PaiementsScreen extends StatefulWidget {
  const PaiementsScreen({super.key});

  @override
  State<PaiementsScreen> createState() => _PaiementsScreenState();
}

/// Les 3 fournisseurs de la maquette, dans cet ordre.
const _fournisseurs = ['wave', 'orange_money', 'mtn_momo'];

class _PaiementsScreenState extends State<PaiementsScreen> {
  bool _loading = true;
  String? _error;
  List<EglisePaiement> _configs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configs = await state.api.getMesPaiements(state.church!.id);
      if (mounted) {
        setState(() {
          // Seuls les 3 fournisseurs de la maquette comptent.
          _configs = configs
              .where((c) => _fournisseurs.contains(c.fournisseurCode))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paiements automatiques')),
      body: _loading
          ? const AppLoading()
          : _error != null
              ? AppError(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SectionTitle(title: 'Prélèvements programmés'),
                      const EmptyState(
                        icon: Icons.credit_card_outlined,
                        message: 'Aucun prélèvement programmé.',
                      ),
                      const SizedBox(height: 16),
                      const SectionTitle(title: 'Comptes utilisés'),
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wave, Orange Money, MTN Mobile Money',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'État des comptes : voir Finances. Aucune clé ne se saisit ici.',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Un prélèvement ne se programme qu’avec un compte marchand actif. Les clés marchandes et API se saisissent uniquement dans Réglages et confidentialité, section « Clés marchandes et API » — cet écran ne gère que les échéances : montant, fréquence, membre concerné.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      // Maquette, écran 35 : le bouton est en bas et
                      // désactivé — aucune échéance n'existe côté
                      // serveur, la programmation n'est pas branchée.
                      const FilledButton(
                        onPressed: null,
                        child: Text('Programmer un prélèvement',
                            style: TextStyle(fontSize: 13.5)),
                      ),
                      if (!_configs.any((c) => c.actif))
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'La programmation d’un prélèvement exige un compte marchand actif.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
