import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import 'impression_cartes_screen.dart';

/// Espace cartes (admin seulement) : la liste des cartes des membres
/// de l'église, avec un bouton « Imprimer » par carte et
/// « Tout imprimer ». Rien d'inventé : photo, nom et matricule
/// viennent de `GET /membres`, page par page (limite 100).
class CartesMembresScreen extends StatefulWidget {
  const CartesMembresScreen({super.key});

  @override
  State<CartesMembresScreen> createState() => _CartesMembresScreenState();
}

class _CartesMembresScreenState extends State<CartesMembresScreen> {
  late Future<List<Member>> _future;
  final _recherche = TextEditingController();
  String _filtre = '';

  @override
  void initState() {
    super.initState();
    _future = _chargerToutes();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  /// Toutes les cartes, page par page (`GET /membres`, limite 100).
  Future<List<Member>> _chargerToutes() async {
    const limite = 100;
    final toutes = <Member>[];
    var total = 0;
    do {
      final page = await context.read<AppState>().api.getMembers(
            limit: limite,
            offset: toutes.length,
          );
      total = page.total;
      toutes.addAll(page.membres);
    } while (toutes.length < total && toutes.isNotEmpty);
    return toutes;
  }

  List<Member> _filtrees(List<Member> membres) {
    final q = _filtre.toLowerCase();
    if (q.isEmpty) return membres;
    return membres
        .where((m) =>
            m.fullName.toLowerCase().contains(q) ||
            m.matricule.toLowerCase().contains(q))
        .toList();
  }

  void _imprimer(BuildContext context, List<Member> membres) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImpressionCartesScreen(membres: membres),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Cartes des membres')),
      body: !state.isAdmin
          ? const EmptyState(
              icon: Icons.badge_outlined,
              message: 'Réservé à l’administrateur de l’église.',
            )
          : FutureBuilder<List<Member>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoading();
                }
                if (snapshot.hasError) {
                  return AppError(
                    message: snapshot.error.toString(),
                    onRetry: () =>
                        setState(() => _future = _chargerToutes()),
                  );
                }
                final membres = _filtrees(snapshot.data!);
                if (snapshot.data!.isEmpty) {
                  return const EmptyState(
                    icon: Icons.badge_outlined,
                    message: 'Aucun membre pour l’instant.',
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _recherche,
                              onChanged: (v) =>
                                  setState(() => _filtre = v.trim()),
                              decoration: const InputDecoration(
                                labelText: 'Rechercher (nom ou matricule)',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: membres.isEmpty
                                ? null
                                : () => _imprimer(context, membres),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Tout imprimer'),
                          ),
                        ],
                      ),
                    ),
                    if (membres.isEmpty)
                      const Expanded(
                        child: EmptyState(
                          icon: Icons.search_off_outlined,
                          message: 'Aucune carte pour cette recherche.',
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: membres.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) =>
                              _LigneCarte(membre: membres[i]),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// Une ligne : photo, nom, matricule, QR en miniature, et le bouton
/// « Imprimer » qui ouvre la vue d'impression de cette seule carte.
class _LigneCarte extends StatelessWidget {
  final Member membre;

  const _LigneCarte({required this.membre});

  String _qrData(BuildContext context) {
    final code = context.read<AppState>().church?.code;
    return code != null && code.isNotEmpty
        ? '$code:${membre.matricule}'
        : membre.matricule;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.orClair,
          backgroundImage: membre.photoUrl != null
              ? NetworkImage(membre.photoUrl!)
              : null,
          child: membre.photoUrl == null
              ? Text(
                  membre.fullName.isNotEmpty
                      ? membre.fullName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )
              : null,
        ),
        title: Text(
          membre.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Matricule : ${membre.matricule}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.styleCode,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.bordure),
              ),
              child: QrImageView(
                data: _qrData(context),
                version: QrVersions.auto,
                size: 48,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer cette carte',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ImpressionCartesScreen(membres: [membre]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
