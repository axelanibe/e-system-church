import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fidele.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';
import 'member_detail_screen.dart';

/// Page Carte seule (tranche P1) : seul le visuel de la carte, sans
/// titre, sans paiement ni modification. Réutilise la carte existante
/// (MemberDetailScreen, mode carte seule).
class CarteFideleScreen extends StatefulWidget {
  const CarteFideleScreen({super.key});

  @override
  State<CarteFideleScreen> createState() => _CarteFideleScreenState();
}

class _CarteFideleScreenState extends State<CarteFideleScreen> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<void> _charger() async {
    // La carte est chargée par MemberDetailScreen (mode carte seule).
    // Ici, on vérifie seulement que le compte est lié à un membre.
    final profil = await context.read<AppState>().api.getMoi();
    if (profil.memberId == null) {
      throw Exception('Aucun membre lié à ce compte.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _future = _charger()),
          );
        }
        return const _CarteMembreSeule();
      },
    );
  }
}

/// Carte du fidèle, chargée depuis le serveur puis affichée seule.
/// Réutilise la fiche existante (MemberDetailScreen, mode carte seule).
class _CarteMembreSeule extends StatefulWidget {
  const _CarteMembreSeule();

  @override
  State<_CarteMembreSeule> createState() => _CarteMembreSeuleState();
}

class _CarteMembreSeuleState extends State<_CarteMembreSeule> {
  late Future<MaCarte> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getMaCarte();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MaCarte>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          return AppError(
            message: snapshot.error.toString(),
            onRetry: () => setState(
              () => _future = context.read<AppState>().api.getMaCarte(),
            ),
          );
        }
        // La carte visuelle seule, avec la note de la projection
        // en dessous : les modifications se font depuis le profil.
        return Column(
          children: [
            Expanded(
              child: MemberDetailScreen(
                member: snapshot.data!.member,
                lectureSeule: true,
                carteSeule: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text(
                'La carte affiche le visuel seul : photo, nom, matricule, '
                'établissement et QR. Les modifications se font depuis le '
                'profil.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        );
      },
    );
  }
}
