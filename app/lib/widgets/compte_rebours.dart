import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Compte à rebours en trois cases : jours, heures, minutes.
/// Calculé en direct depuis la date réelle du culte, réévalué
/// chaque minute. « -- » quand le culte n'a pas de date exploitable.
/// Partagé par l'accueil fidèle et le détail du culte.
class CompteRebours extends StatefulWidget {
  final DateTime? date;

  const CompteRebours({super.key, required this.date});

  @override
  State<CompteRebours> createState() => _CompteReboursState();
}

class _CompteReboursState extends State<CompteRebours> {
  Timer? _timer;
  DateTime _maintenant = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) setState(() => _maintenant = DateTime.now());
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    String jours = '--';
    String heures = '--';
    String minutes = '--';
    if (date != null) {
      final reste = date.difference(_maintenant);
      if (!reste.isNegative) {
        jours = '${reste.inDays}';
        heures = '${reste.inHours % 24}';
        minutes = '${reste.inMinutes % 60}';
      }
    }
    return Row(
      children: [
        _CaseCompte(valeur: jours, unite: 'Jours'),
        const SizedBox(width: AppSpacing.xs),
        _CaseCompte(valeur: heures, unite: 'Heures'),
        const SizedBox(width: AppSpacing.xs),
        _CaseCompte(valeur: minutes, unite: 'Minutes'),
      ],
    );
  }
}

class _CaseCompte extends StatelessWidget {
  final String valeur;
  final String unite;

  const _CaseCompte({required this.valeur, required this.unite});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: PaletteMembre.fond,
          border: Border.all(color: PaletteMembre.bordure),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          children: [
            Text(
              valeur,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: AppFontSizes.s20,
                    color: PaletteMembre.violetRoyal,
                  ),
            ),
            Text(
              unite,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PaletteMembre.texteSecondaire,
                    fontSize: AppFontSizes.s10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
