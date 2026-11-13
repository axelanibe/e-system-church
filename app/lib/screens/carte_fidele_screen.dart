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
    final apercu = context.watch<AppState>().apercuFidele;
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoading();
        }
        if (snapshot.hasError) {
          // En aperçu admin, pas de membre lié : la carte s'affiche
          // avec les espaces réservés, sans erreur.
          if (apercu) {
            return const _CarteApercu();
          }
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
        // La carte visuelle seule, sans rien autour.
        return MemberDetailScreen(
          member: snapshot.data!.member,
          lectureSeule: true,
          carteSeule: true,
        );
      },
    );
  }
}

/// Carte en aperçu admin : pas de fausse carte avec des données
/// inventées, un état vide qui explique.
class _CarteApercu extends StatelessWidget {
  const _CarteApercu();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.badge_outlined,
      message: 'En aperçu, la carte d’un membre n’est pas visible. '
          'Connectez-vous avec un compte fidèle pour voir votre carte.',
    );
  }
}
