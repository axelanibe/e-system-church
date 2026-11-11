import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Fiche d'un membre : carte avec QR, coordonnées, département, cellule,
/// statut. Le QR est généré depuis les données réelles du membre :
/// code de l'église active + matricule, par exemple « ESC-GD2026:M-0001 ».
/// Le modèle [Member] n'a pas de `church_id` : l'église affichée est
/// l'église active de la session ([AppState.church]). L'API n'est pas
/// changée dans cette tranche.
class MemberDetailScreen extends StatelessWidget {
  final Member member;

  const MemberDetailScreen({super.key, required this.member});

  Color _statusColor(String status) {
    switch (status) {
      case 'actif':
        return Colors.green;
      case 'nouveau_converti':
        return Colors.blue;
      case 'inactif':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _row(BuildContext context, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value ?? '—',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final church = state.church;

    // Nom de l'église mère quand il est connu : l'église active est
    // elle-même une mère, ou sa mère figure parmi les églises de la
    // session. Sinon, la ligne n'est pas affichée, rien n'est inventé.
    String? motherName;
    if (church != null) {
      if (church.isMere) {
        motherName = church.name;
      } else if (church.parentChurchId != null) {
        for (final membership in state.eglises) {
          if (membership.church.id == church.parentChurchId) {
            motherName = membership.church.name;
            break;
          }
        }
      }
    }

    final qrData = church == null
        ? member.matricule
        : '${church.code}:${member.matricule}';

    return Scaffold(
      appBar: AppBar(title: Text(member.fullName)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          'e-System Church',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          church?.name ?? 'Église non connue',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        if (motherName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Église mère : $motherName',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (church?.city != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            church!.city!,
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 16),
                        CircleAvatar(
                          radius: 36,
                          child: Text(
                            member.fullName.isNotEmpty
                                ? member.fullName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontSize: 32),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          member.fullName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Carte de membre — ${member.matricule}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        StatusChip(
                          label: member.statusLabel,
                          color: _statusColor(member.status),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            size: 200,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          member.fullName,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          qrData,
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row(context, 'Matricule', member.matricule),
                        _row(context, 'Téléphone', member.phone),
                        _row(context, 'E-mail', member.email),
                        _row(context, 'Date de naissance',
                            member.birthDate == null
                                ? null
                                : formatDate(
                                    DateTime.tryParse(member.birthDate!))),
                        _row(context, 'Département', member.department),
                        _row(context, 'Cellule', member.cellGroup),
                        _row(context, 'Membre depuis',
                            formatDate(member.createdAt)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
