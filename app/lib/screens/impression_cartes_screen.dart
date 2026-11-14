import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/impression.dart';
import '../widgets/carte_membre_visuelle.dart';

/// Vue d'impression des cartes (web) : les cartes seules, sur fond
/// clair, sans navigation. Le bouton « Imprimer » ouvre la fenêtre
/// d'impression du navigateur. Pendant l'impression, la barre et le
/// bouton disparaissent pour ne pas figurer sur la feuille.
/// Sur l'APK, l'impression n'existe pas : un message l'indique.
class ImpressionCartesScreen extends StatefulWidget {
  final List<Member> membres;

  const ImpressionCartesScreen({super.key, required this.membres});

  @override
  State<ImpressionCartesScreen> createState() =>
      _ImpressionCartesScreenState();
}

class _ImpressionCartesScreenState extends State<ImpressionCartesScreen> {
  bool _impressionEnCours = false;

  void _imprimer() {
    if (!impressionWebDisponible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'L’impression des cartes est disponible sur le web.',
          ),
        ),
      );
      return;
    }
    setState(() => _impressionEnCours = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      imprimerPage();
      if (mounted) setState(() => _impressionEnCours = false);
    });
  }

  String _qrData(Member membre) {
    final code = context.read<AppState>().church?.code;
    return code != null && code.isNotEmpty
        ? '$code:${membre.matricule}'
        : membre.matricule;
  }

  @override
  Widget build(BuildContext context) {
    if (_impressionEnCours) {
      // Feuille seule : cartes sur fond blanc, sans barre ni bouton.
      return ColoredBox(
        color: Colors.white,
        child: _listeCartes(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.membres.length == 1
              ? 'Imprimer une carte'
              : 'Imprimer ${widget.membres.length} cartes',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Dans la fenêtre d’impression, activez '
              '« Graphiques d’arrière-plan » pour garder les '
              'couleurs de la carte.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: _listeCartes()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _imprimer,
        icon: const Icon(Icons.print_outlined),
        label: const Text('Imprimer'),
      ),
    );
  }

  Widget _listeCartes() {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: widget.membres.length,
      separatorBuilder: (_, __) => const SizedBox(height: 24),
      itemBuilder: (context, i) {
        final membre = widget.membres[i];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: CarteMembreVisuelle(
              member: membre,
              qrData: _qrData(membre),
            ),
          ),
        );
      },
    );
  }
}
