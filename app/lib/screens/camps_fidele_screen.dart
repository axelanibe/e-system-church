import 'package:flutter/material.dart';

import '../widgets/common_widgets.dart';

/// Mes camps (tranche P1) : état vide, comme dans la projection.
/// Les inscriptions aux camps arriveront avec la T5.
class CampsFideleScreen extends StatelessWidget {
  const CampsFideleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes camps')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.event_outlined,
          message: 'Aucun camp pour le moment. '
              'Vos inscriptions aux camps apparaîtront ici.',
        ),
      ),
    );
  }
}
