import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';
import 'member_complet_screen.dart';
import 'member_form_screen.dart';

/// Fiche d'un membre : matricule, coordonnées, département, cellule, statut.
class MemberDetailScreen extends StatelessWidget {
  final Member member;

  const MemberDetailScreen({super.key, required this.member});

  Color _statusColor(String status) {
    switch (status) {
      case 'actif':
        return AppTheme.cypress;
      case 'nouveau_converti':
        return AppTheme.presences;
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

  Future<void> _deleteMember(BuildContext context) async {
    final confirmed = await confirmDelete(
      context,
      'Supprimer définitivement le membre « ${member.fullName} » (${member.matricule}) ?',
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    try {
      await context.read<AppState>().api.deleteMember(member.id);
      if (context.mounted) {
        showSuccess(context, 'Membre supprimé.');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // QR de la carte : CODE_EGLISE:MATRICULE (ex. ESC-0411:M-LK-150390-01).
    // Le lecteur accepte aussi les anciennes cartes, matricule seul.
    final codeEglise = context.read<AppState>().church?.code;
    final qrData = codeEglise != null && codeEglise.isNotEmpty
        ? '$codeEglise:${member.matricule}'
        : member.matricule;
    return Scaffold(
      appBar: AppBar(
        title: Text(member.fullName),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () => _deleteMember(context),
          ),
        ],
      ),
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
                            size: 180,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          member.matricule,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            MemberCompletScreen(memberId: member.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Voir la fiche complète'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => MemberFormScreen(member: member),
                      ),
                    );
                    if (changed == true && context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
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
                        _row(context, 'Fonction', member.fonctionAffichee),
                        _row(context, 'Poste', member.poste),
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
