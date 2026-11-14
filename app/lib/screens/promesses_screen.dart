import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/member.dart';
import '../models/us_restantes.dart';
import '../services/preferences_locales.dart';
import '../services/t12_strings.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialog_helpers.dart';

/// Promesses de don avec échéancier (US4).
///
/// Le membre s'engage pour lui-même ; l'admin ou le trésorier engage un
/// membre. Le versement reçu est une contribution en attente : c'est sa
/// confirmation (flux existant) qui marque l'échéance reçue et clôture
/// la promesse quand il ne reste rien. L'annulation ne touche jamais
/// aux versements déjà reçus.
class PromessesScreen extends StatefulWidget {
  const PromessesScreen({super.key});

  @override
  State<PromessesScreen> createState() => _PromessesScreenState();
}

class _PromessesScreenState extends State<PromessesScreen> {
  late Future<List<Promesse>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Promesse>> _load() =>
      context.read<AppState>().api.getPromesses();

  void _refresh() => setState(() => _future = _load());

  bool get _peutGer => context.read<AppState>().canManageFinances;

  Future<void> _creer() async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final api = context.read<AppState>().api;
    String? membreId;
    List<Member> membres = const [];
    if (_peutGer) {
      final page = await api.getMembers();
      membres = page.membres;
      if (membres.isNotEmpty) membreId = membres.first.id;
    } else {
      final moi = await api.getMoi();
      membreId = moi.memberId;
    }
    if (!mounted || membreId == null) return;
    final montantController = TextEditingController();
    final versementsController = TextEditingController(text: '1');
    final debutController = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
    await showCreateDialog(
      context: context,
      title: t.nouvellePromesse,
      saveLabel: t.enregistrer,
      fields: [
        if (_peutGer)
          StatefulBuilder(
            builder: (context, setDialogState) =>
                DropdownButtonFormField<String>(
              initialValue: membreId,
              decoration: InputDecoration(labelText: t.choisirMembre),
              items: membres
                  .map((m) => DropdownMenuItem(
                      value: m.id, child: Text(m.fullName)))
                  .toList(),
              onChanged: (v) => setDialogState(() => membreId = v),
            ),
          ),
        dialogTextField(
          controller: montantController,
          label: '${t.montantTotal} *',
          keyboardType: TextInputType.number,
        ),
        dialogTextField(
          controller: versementsController,
          label: '${t.nbVersements} *',
          keyboardType: TextInputType.number,
        ),
        dialogDateField(
            context: context, controller: debutController, label: t.dateDebut),
      ],
      isValid: () =>
          (int.tryParse(montantController.text) ?? 0) > 0 &&
          (int.tryParse(versementsController.text) ?? 0) >= 1,
      onSave: () async {
        await api.createPromesse(
          memberId: membreId!,
          montantTotalFcfa: int.parse(montantController.text),
          dateDebut: debutController.text,
          nbVersements: int.parse(versementsController.text),
        );
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t.enregistre)));
        }
      },
    );
  }

  Future<void> _verser(Promesse promesse, EcheancePromesse echeance) async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final api = context.read<AppState>().api;
    var moyen = 'especes';
    final refController = TextEditingController();
    await showCreateDialog(
      context: context,
      title: t.verser,
      saveLabel: t.enregistrer,
      fields: [
        Text(
          '${formatMontant(echeance.montantFcfa, 'FCFA')} — ${formatDateSeule(DateTime.tryParse(echeance.dateEcheance))}',
        ),
        StatefulBuilder(
          builder: (context, setDialogState) =>
              DropdownButtonFormField<String>(
            initialValue: moyen,
            decoration: InputDecoration(labelText: t.moyenPaiement),
            items: const [
              DropdownMenuItem(value: 'especes', child: Text('Espèces')),
              DropdownMenuItem(value: 'wave', child: Text('Wave')),
              DropdownMenuItem(
                  value: 'orange_money', child: Text('Orange Money')),
              DropdownMenuItem(value: 'mtn_momo', child: Text('MTN MoMo')),
              DropdownMenuItem(value: 'virement', child: Text('Virement')),
            ],
            onChanged: (v) => setDialogState(() => moyen = v ?? 'especes'),
          ),
        ),
        dialogTextField(
            controller: refController, label: 'Référence de paiement'),
      ],
      isValid: () => true,
      onSave: () async {
        await api.verserPromesse(
          promesseId: promesse.id,
          echeanceId: echeance.id,
          amountFcfa: echeance.montantFcfa,
          paymentMethod: moyen,
          paymentRef: refController.text.isEmpty ? null : refController.text,
        );
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t.versementEnAttente)));
        }
      },
    );
  }

  Future<void> _annuler(Promesse promesse) async {
    final t = T12Strings(context.read<PreferencesLocales>().estAnglais);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.annuler),
        content: Text(t.promesseAnnulee),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.annuler),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.confirmer),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    await context.read<AppState>().api.annulerPromesse(promesse.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    return Scaffold(
      appBar: AppBar(title: Text(t.promesses)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creer,
        icon: const Icon(Icons.add),
        label: Text(t.nouvellePromesse),
      ),
      body: FutureBuilder<List<Promesse>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading();
          }
          if (snapshot.hasError) {
            return AppError(
                message: t.erreurChargement, onRetry: _refresh);
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return EmptyState(
                icon: Icons.handshake_outlined, message: t.vide);
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final p = items[i];
                return _PromesseCard(
                  promesse: p,
                  peutGer: _peutGer,
                  onVerser: (e) => _verser(p, e),
                  onAnnuler: () => _annuler(p),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Carte d'une promesse : le détail (échéances) se charge à l'ouverture,
/// la liste ne le renvoie pas.
class _PromesseCard extends StatefulWidget {
  final Promesse promesse;
  final bool peutGer;
  final void Function(EcheancePromesse) onVerser;
  final VoidCallback onAnnuler;

  const _PromesseCard({
    required this.promesse,
    required this.peutGer,
    required this.onVerser,
    required this.onAnnuler,
  });

  @override
  State<_PromesseCard> createState() => _PromesseCardState();
}

class _PromesseCardState extends State<_PromesseCard> {
  Future<Promesse>? _detail;

  @override
  Widget build(BuildContext context) {
    final t = T12Strings(context.watch<PreferencesLocales>().estAnglais);
    final p = widget.promesse;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading:
            const Icon(Icons.handshake_outlined, color: AppTheme.or),
        title: Text(
          p.membreNom ?? formatMontant(p.montantTotalFcfa, 'FCFA'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${formatMontant(p.montantTotalFcfa, 'FCFA')} · ${t.recu} ${formatMontant(p.recuFcfa, 'FCFA')} · ${t.reste} ${formatMontant(p.resteFcfa, 'FCFA')}',
        ),
        trailing: StatusChip(
          label: p.estEnCours
              ? t.promesseEnCours
              : (p.statut == 'terminee' ? t.promesseTerminee : t.annuler),
          color: p.estEnCours ? AppTheme.orAttention : AppTheme.bleuNuit,
        ),
        onExpansionChanged: (ouvert) {
          if (ouvert && _detail == null) {
            setState(() => _detail =
                context.read<AppState>().api.getPromesse(p.id));
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(
              value: p.progression,
              backgroundColor: AppTheme.fondPapier,
              color: AppTheme.or,
            ),
          ),
          FutureBuilder<Promesse>(
            future: _detail,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final echeances = snapshot.data?.echeances ?? const [];
              if (echeances.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(t.vide),
                );
              }
              return Column(
                children: [
                  ...echeances.map((e) => ListTile(
                        dense: true,
                        leading: Icon(
                          e.estRecue
                              ? Icons.check_circle_outline
                              : Icons.schedule_outlined,
                          color: e.estRecue
                              ? Colors.green
                              : AppTheme.orAttention,
                        ),
                        title: Text(formatMontant(e.montantFcfa, 'FCFA')),
                        subtitle: Text(formatDateSeule(
                            DateTime.tryParse(e.dateEcheance))),
                        trailing: e.estEnAttente &&
                                p.estEnCours &&
                                widget.peutGer
                            ? TextButton(
                                onPressed: () => widget.onVerser(e),
                                child: Text(t.verser),
                              )
                            : null,
                      )),
                  if (p.estEnCours && widget.peutGer)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: widget.onAnnuler,
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(t.annuler),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
