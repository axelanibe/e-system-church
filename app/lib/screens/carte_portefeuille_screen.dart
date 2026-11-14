import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../widgets/common_widgets.dart';

/// Carte dans le portefeuille du téléphone (US9) : la carte (nom,
/// matricule, code QR) en données exportables, avec le QR affiché.
/// Aucun compte Apple Wallet ni Google Wallet n'est branché : l'export
/// est un fichier pass générique et l'écran l'indique. Aucun coût
/// engagé, aucun compte créé.
class CartePortefeuilleScreen extends StatefulWidget {
  const CartePortefeuilleScreen({super.key});

  @override
  State<CartePortefeuilleScreen> createState() =>
      _CartePortefeuilleScreenState();
}

class _CartePortefeuilleScreenState extends State<CartePortefeuilleScreen> {
  late Future<CartePortefeuille> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().api.getCartePortefeuille();
  }

  void _refresh() => setState(
      () => _future = context.read<AppState>().api.getCartePortefeuille());

  Future<void> _exporter(CartePortefeuille carte) async {
    final passe = jsonEncode({
      'format': 'e-system-church-pass',
      'version': 1,
      'nom': carte.nom,
      'matricule': carte.matricule,
      'eglise': carte.egliseNom,
      'eglise_code': carte.egliseCode,
      'qr_donnees': carte.qrDonnees,
    });
    await Clipboard.setData(ClipboardData(text: passe));
    if (!mounted) return;
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.passCopie)));
  }

  Future<void> _partager(CartePortefeuille carte) async {
    final passe = jsonEncode({
      'format': 'e-system-church-pass',
      'version': 1,
      'nom': carte.nom,
      'matricule': carte.matricule,
      'eglise': carte.egliseNom,
      'eglise_code': carte.egliseCode,
      'qr_donnees': carte.qrDonnees,
    });
    await SharePlus.instance.share(ShareParams(text: passe));
  }

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(title: Text(t.cartePortefeuille)),
      body: FutureBuilder<CartePortefeuille>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(message: t.erreurChargement, onRetry: _refresh);
          }
          final carte = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: AppTheme.bleuNuit,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        carte.nom,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (carte.matricule != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          carte.matricule!,
                          style: AppTheme.styleCode.copyWith(
                            color: AppTheme.or,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        carte.egliseNom,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: carte.qrDonnees,
                          size: 180,
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
                    child: FilledButton.icon(
                      onPressed: () => _exporter(carte),
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(t.exporterPass),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _partager(carte),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Partager'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline,
                      color: AppTheme.orAttention),
                  title: Text(t.aucunCompteWallet),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
