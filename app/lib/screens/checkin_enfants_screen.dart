import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/checkin_enfant.dart';
import '../models/member.dart';
import '../state/app_state.dart';
import '../utils/qr_carte.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Check-in enfants, double QR ECODIM.
///
/// Arrivée jumelée : on scanne d'abord le QR du bracelet parent
/// (matricule), puis le QR du bracelet enfant (code #KIDS-XXXX).
/// La saisie manuelle des deux codes reste le repli quand la caméra est
/// refusée ou absente. La liste des présents du jour permet la sortie
/// sécurisée (même code enfant, même parent) et l'alerte silencieuse au
/// parent pendant le culte : enregistrement en base seulement, pas de SMS.
class CheckinEnfantsScreen extends StatefulWidget {
  const CheckinEnfantsScreen({super.key});

  @override
  State<CheckinEnfantsScreen> createState() => _CheckinEnfantsScreenState();
}

class _CheckinEnfantsScreenState extends State<CheckinEnfantsScreen> {
  late final MobileScannerController _controller;
  final _codeParentController = TextEditingController();
  final _codeEnfantController = TextEditingController();
  final _salleController = TextEditingController();
  final _allergieController = TextEditingController();

  late Future<MemberPage> _membresFuture;
  late Future<List<CheckinEnfant>> _presentsFuture;
  List<Member> _membres = [];
  String? _enfantId;
  String? _parentId;
  bool _etapeParent = true; // true : on scanne le parent, false : l'enfant
  bool _enCours = false;
  bool _torche = false;
  String? _message;
  bool _succes = false;
  String? _dernierCode;
  DateTime? _dernierInstant;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
    );
    final api = context.read<AppState>().api;
    _membresFuture = api.getMembers();
    _presentsFuture = api.getCheckinsEnfantsJour();
  }

  @override
  void dispose() {
    _controller.dispose();
    _codeParentController.dispose();
    _codeEnfantController.dispose();
    _salleController.dispose();
    _allergieController.dispose();
    super.dispose();
  }

  void _refreshPresents() {
    setState(() {
      _presentsFuture = context.read<AppState>().api.getCheckinsEnfantsJour();
    });
  }

  void _afficher(String message, {required bool succes}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _succes = succes;
    });
  }

  Member? _parMatricule(String matricule) {
    final cherche = matricule.trim().toUpperCase();
    for (final m in _membres) {
      if (m.matricule.toUpperCase() == cherche) return m;
    }
    return null;
  }

  void _traiterCode(String brut) {
    if (_enCours) return;
    final maintenant = DateTime.now();
    if (_dernierCode == brut &&
        _dernierInstant != null &&
        maintenant.difference(_dernierInstant!).inSeconds < 3) {
      return;
    }
    _dernierCode = brut;
    _dernierInstant = maintenant;
    final state = context.read<AppState>();
    if (_etapeParent) {
      final lecture =
          lireQrCarte(brut, codeEglise: state.church?.code);
      if (!lecture.ok) {
        _afficher(lecture.erreur!, succes: false);
        return;
      }
      final parent = _parMatricule(lecture.matricule!);
      setState(() {
        _codeParentController.text = lecture.matricule!;
        _parentId = parent?.id;
        _etapeParent = false;
      });
      _afficher(
        parent == null
            ? 'QR parent lu (${lecture.matricule}), choisissez le parent dans la liste.'
            : 'Parent : ${parent.fullName}. Scannez maintenant le QR de l’enfant.',
        succes: true,
      );
    } else {
      final contenu = brut.trim().toUpperCase();
      final code = contenu.contains(':')
          ? contenu.split(':').last.trim()
          : contenu;
      if (!RegExp(r'^KIDS-[A-Z0-9]{4}$').hasMatch(code)) {
        _afficher(
          'QR enfant invalide : attendu un code #KIDS-XXXX.',
          succes: false,
        );
        return;
      }
      setState(() => _codeEnfantController.text = code);
      _afficher('Code enfant $code lu. Choisissez l’enfant, puis validez.',
          succes: true);
    }
  }

  Future<void> _checkin() async {
    if (_enfantId == null || _parentId == null) {
      _afficher('Choisissez l’enfant et le parent.', succes: false);
      return;
    }
    final codeEnfant = _codeEnfantController.text.trim().toUpperCase();
    if (!RegExp(r'^KIDS-[A-Z0-9]{4}$').hasMatch(codeEnfant)) {
      _afficher('Code enfant invalide : format #KIDS-XXXX.', succes: false);
      return;
    }
    final codeParent = _codeParentController.text.trim();
    if (codeParent.isEmpty) {
      _afficher('Saisissez ou scannez le code du parent.', succes: false);
      return;
    }
    setState(() => _enCours = true);
    try {
      final checkin = await context.read<AppState>().api.checkinEnfant(
            enfantMemberId: _enfantId!,
            parentMemberId: _parentId!,
            codeParent: codeParent,
            codeEnfant: codeEnfant,
            salle: _salleController.text.trim().isEmpty
                ? null
                : _salleController.text.trim(),
            allergie: _allergieController.text.trim().isEmpty
                ? null
                : _allergieController.text.trim(),
          );
      if (!mounted) return;
      _codeEnfantController.clear();
      setState(() {
        _etapeParent = true;
        _enCours = false;
      });
      _afficher(
        'Arrivée enregistrée : ${checkin.enfantNom ?? 'enfant'} '
        '(${checkin.codeAffiche}).',
        succes: true,
      );
      _refreshPresents();
    } catch (e) {
      if (mounted) setState(() => _enCours = false);
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  Future<void> _sortie(CheckinEnfant checkin) async {
    final codeEnfant = TextEditingController(text: _codeEnfantController.text);
    final codeParent = TextEditingController(text: _codeParentController.text);
    var ok = false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sortie sécurisée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enfant : ${checkin.enfantNom ?? checkin.codeAffiche}'),
            const SizedBox(height: 12),
            TextField(
              controller: codeEnfant,
              decoration: const InputDecoration(
                labelText: 'Code enfant (#KIDS-XXXX)',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            TextField(
              controller: codeParent,
              decoration: const InputDecoration(
                labelText: 'Code parent (matricule)',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              ok = true;
              Navigator.of(context).pop();
            },
            child: const Text('Confirmer la sortie'),
          ),
        ],
      ),
    );
    if (!ok) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.sortieEnfant(
            checkinId: checkin.id,
            codeEnfant: codeEnfant.text.trim().toUpperCase(),
            codeParent: codeParent.text.trim(),
          );
      if (!mounted) return;
      _afficher('Sortie enregistrée : ${checkin.enfantNom ?? ''}.',
          succes: true);
      _refreshPresents();
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  Future<void> _alerte(CheckinEnfant checkin) async {
    final message = TextEditingController();
    var ok = false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alerte silencieuse au parent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enfant : ${checkin.enfantNom ?? checkin.codeAffiche}. '
              'L’alerte est enregistrée, le parent est prévenu en app, '
              'sans SMS.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              decoration: const InputDecoration(
                labelText: 'Message pour le parent',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              ok = true;
              Navigator.of(context).pop();
            },
            child: const Text('Envoyer l’alerte'),
          ),
        ],
      ),
    );
    if (!ok || message.text.trim().isEmpty) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().api.alerteCheckinEnfant(
            checkinId: checkin.id,
            message: message.text.trim(),
          );
      if (!mounted) return;
      _afficher('Alerte silencieuse enregistrée.', succes: true);
      _refreshPresents();
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in enfants'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _torche = !_torche);
              _controller.toggleTorch();
            },
            icon: Icon(_torche ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Lampe torche',
          ),
        ],
      ),
      body: FutureBuilder<MemberPage>(
        future: _membresFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {
                _membresFuture = context.read<AppState>().api.getMembers();
              }),
            );
          }
          _membres = snapshot.data!.membres;
          return _contenu();
        },
      ),
    );
  }

  Widget _contenu() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('1. QR parent')),
              ButtonSegment(value: false, label: Text('2. QR enfant')),
            ],
            selected: {_etapeParent},
            onSelectionChanged: (s) =>
                setState(() => _etapeParent = s.first),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    for (final code in capture.barcodes) {
                      final valeur = code.rawValue;
                      if (valeur != null && valeur.isNotEmpty) {
                        _traiterCode(valeur);
                        break;
                      }
                    }
                  },
                  errorBuilder: (context, error) => const Center(
                    child: Text(
                      'Caméra indisponible : saisissez les codes à la main.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.orAmbre, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_message != null)
            Text(
              _message!,
              style: TextStyle(
                color: _succes ? AppTheme.cypress : AppTheme.rougeErreur,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 12),
          dialogDropdown<String>(
            value: _enfantId,
            label: 'Enfant',
            options: {
              for (final m in _membres) m.id: '${m.fullName} (${m.matricule})',
            },
            onChanged: (v) => setState(() => _enfantId = v),
          ),
          const SizedBox(height: 8),
          dialogDropdown<String>(
            value: _parentId,
            label: 'Parent',
            options: {
              for (final m in _membres) m.id: '${m.fullName} (${m.matricule})',
            },
            onChanged: (v) {
              final parent =
                  _membres.where((m) => m.id == v).firstOrNull;
              setState(() {
                _parentId = v;
                if (parent != null) {
                  _codeParentController.text = parent.matricule;
                }
              });
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _codeParentController,
            decoration: const InputDecoration(
              labelText: 'Code parent (matricule, ou QR scanné)',
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _codeEnfantController,
            decoration: const InputDecoration(
              labelText: 'Code enfant (#KIDS-XXXX, ou QR scanné)',
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _salleController,
            decoration: const InputDecoration(labelText: 'Salle'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _allergieController,
            decoration: const InputDecoration(
              labelText: 'Allergie ou remarque santé',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _enCours ? null : _checkin,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Enregistrer l’arrivée'),
          ),
          const SizedBox(height: 20),
          Text(
            'Présents du jour',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<CheckinEnfant>>(
            future: _presentsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoading();
              }
              if (snapshot.hasError) {
                return AppError(
                  message: snapshot.error.toString(),
                  onRetry: _refreshPresents,
                );
              }
              final presents = snapshot.data!;
              if (presents.isEmpty) {
                return const Text('Aucun enfant enregistré aujourd’hui.');
              }
              return Column(
                children: presents
                    .map((c) => Card(
                          child: ListTile(
                            title: Text(
                              '${c.enfantNom ?? 'Enfant'} ${c.codeAffiche}',
                            ),
                            subtitle: Text(
                              [
                                if (c.salle != null) 'Salle ${c.salle}',
                                if (c.parentNom != null)
                                  'Parent : ${c.parentNom}',
                                if (c.allergie != null)
                                  'Allergie : ${c.allergie}',
                                if (c.alerte) 'Alerte envoyée au parent',
                                c.enClasse ? 'En classe' : 'Sorti',
                              ].join(' • '),
                            ),
                            trailing: c.enClasse
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () => _alerte(c),
                                        icon: const Icon(
                                          Icons.notification_important,
                                        ),
                                        tooltip: 'Alerte silencieuse',
                                      ),
                                      IconButton(
                                        onPressed: () => _sortie(c),
                                        icon: const Icon(Icons.logout),
                                        tooltip: 'Sortie',
                                      ),
                                    ],
                                  )
                                : const Icon(Icons.check_circle_outline),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
