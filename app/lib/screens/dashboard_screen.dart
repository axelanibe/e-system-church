import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:provider/provider.dart';

import '../models/abonnement.dart';
import '../models/announcement.dart';
import '../models/cultes.dart';
import '../models/rapport.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../utils/periodes.dart';
import '../widgets/common_widgets.dart';
import '../widgets/logo_app.dart';
import '../widgets/soft_button.dart';
import '../widgets/soft_card.dart';
import 'annonces_screen.dart';
import 'cultes_screen.dart';
import 'mon_eglise_screen.dart';
import 'pastoral_screen.dart';
import 'prieres_screen.dart';
import 'rapports_mere_screen.dart';
import 'rapports_recus_screen.dart';
import 'transferts_screen.dart';

/// Période du sélecteur du tableau de bord (pastilles, modèle Facebook).
enum PeriodeTableauBord { aujourdHui, septJours, trenteJours }

/// Libellé d'une période, tel qu'affiché dans les pastilles.
String libellePeriodeTableauBord(PeriodeTableauBord periode) {
  switch (periode) {
    case PeriodeTableauBord.aujourdHui:
      return 'Aujourd’hui';
    case PeriodeTableauBord.septJours:
      return '7 jours';
    case PeriodeTableauBord.trenteJours:
      return '30 jours';
  }
}

/// Nombre de jours d'une période.
int joursPeriodeTableauBord(PeriodeTableauBord periode) {
  switch (periode) {
    case PeriodeTableauBord.aujourdHui:
      return 1;
    case PeriodeTableauBord.septJours:
      return 7;
    case PeriodeTableauBord.trenteJours:
      return 30;
  }
}

/// Fenêtre d'une période : [debut, fin] courante et [debutPrec, finPrec]
/// précédente équivalente, en dates seules. Pour « Aujourd’hui », la
/// période précédente est hier.
({DateTime debut, DateTime fin, DateTime debutPrec, DateTime finPrec})
    fenetresPeriodeTableauBord(
        PeriodeTableauBord periode, DateTime reference) {
  final jour =
      DateTime(reference.year, reference.month, reference.day);
  final duree = joursPeriodeTableauBord(periode);
  final debut = jour.subtract(Duration(days: duree - 1));
  final finPrec = debut.subtract(const Duration(days: 1));
  final debutPrec = finPrec.subtract(Duration(days: duree - 1));
  return (debut: debut, fin: jour, debutPrec: debutPrec, finPrec: finPrec);
}

/// Texte de variation (« +3 », « -2 », « +0 »), null quand il n'y a
/// rien à comparer (0 des deux côtés : pas de bruit sur une carte vide).
String? texteVariation(int actuel, int precedent) {
  if (actuel == 0 && precedent == 0) return null;
  final diff = actuel - precedent;
  return diff >= 0 ? '+$diff' : '$diff';
}

/// Signaux d'attention du tableau de bord, uniquement à partir de
/// données déjà chargées (abonnement, compteurs, clôtures). Vide = pas
/// de carte d'attention. Rien d'inventé : sans donnée, pas de signal.
List<String> signauxAttention({
  required Abonnement? abonnement,
  required int demandesATraiter,
  required bool caisseMoisPrecedentNonCloturee,
  required String moisPrecedent,
}) {
  final signaux = <String>[];
  final abo = abonnement;
  if (abo != null) {
    if (abo.lectureSeule) {
      signaux.add('Abonnement expiré : l’application est en lecture seule.');
    } else {
      final jours = abo.joursRestants;
      if (jours != null && jours <= 30) {
        signaux.add(
            'Abonnement : $jours ${jours == 1 ? 'jour restant' : 'jours restants'}.');
      }
    }
  }
  if (demandesATraiter > 0) {
    signaux.add(
        '$demandesATraiter ${demandesATraiter == 1 ? 'élément à traiter' : 'éléments à traiter'}.');
  }
  if (caisseMoisPrecedentNonCloturee) {
    signaux.add('Caisse de $moisPrecedent non clôturée.');
  }
  return signaux;
}

/// « AAAA-MM-JJ » pour une date seule.
String _aaaammjj(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _DashboardData {
  final int membresTotal;
  final int presencesJour;
  final int presencesPrecedentes;
  final int visiteursJour;
  final int visiteursPrecedents;
  /// Vrai quand la liste des visiteurs a été tronquée à la limite
  /// demandée : la variation des visiteurs n'est alors pas fiable,
  /// elle n'est pas affichée.
  final bool visiteursTronques;
  final int nouveauxMembres;
  final int nouveauxMembresPrecedents;
  /// Vrai quand le mois précédent a eu des mouvements de caisse et
  /// aucune clôture : signal d'attention, jamais deviné sans données.
  final bool caisseMoisPrecedentNonCloturee;
  final int cotisationsMois;
  final int entreesJour;
  final int sortiesJour;
  final int caisse;
  final int prieresEnAttente;
  final int liaisonsEnAttente;
  final int rapportsRecus;
  final int transfertsRattachements;
  final int absencesASuivre;
  final int anniversairesJour;
  final String? mereNom;
  final String? mereCode;
  final RapportConsolide? rapport;
  final List<Announcement> annonces;
  final List<Culte> cultes;

  const _DashboardData({
    required this.membresTotal,
    required this.presencesJour,
    required this.presencesPrecedentes,
    required this.visiteursJour,
    required this.visiteursPrecedents,
    required this.visiteursTronques,
    required this.nouveauxMembres,
    required this.nouveauxMembresPrecedents,
    required this.caisseMoisPrecedentNonCloturee,
    required this.cotisationsMois,
    required this.entreesJour,
    required this.sortiesJour,
    required this.caisse,
    required this.prieresEnAttente,
    required this.liaisonsEnAttente,
    required this.rapportsRecus,
    required this.transfertsRattachements,
    required this.absencesASuivre,
    required this.anniversairesJour,
    required this.mereNom,
    required this.mereCode,
    required this.rapport,
    required this.annonces,
    required this.cultes,
  });
}

/// Tableau de bord (maquette Membres Finances, écrans 19 et 36, le même
/// écran pour la mère et pour l'annexe) : carte violet profond
/// « Aujourd'hui » avec le prochain culte dedans, « Chiffres de mon
/// église », groupe « Contributions du jour », « Demandes en attente »
/// (mère) ou « À traiter » (annexe), « Membres à suivre », « Mes
/// annexes » (mère) ou « Mon église mère » (annexe), actions rapides
/// (Nouveau culte, Nouvelle annonce) et annonces récentes. Rien
/// d'inventé : que des données réelles, et des états vides quand il
/// n'y a rien. L'espace fidèle ne s'ouvre pas depuis l'admin
/// (périmètres étanches) : pas d'aperçu fidèle ici. La Plateforme
/// (super admin) ne s'ouvre pas depuis une église (maquette,
/// écran 33 : « Rien ici ne s'ouvre depuis une église ») : aucune
/// carte « Toute la plateforme » ici.
class DashboardScreen extends StatefulWidget {
  final ValueChanged<int> onAller;

  const DashboardScreen({super.key, required this.onAller});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;
  var _periode = PeriodeTableauBord.aujourdHui;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final state = context.read<AppState>();
    final api = state.api;
    final membres = await api.getMembers();
    // Cotisations du mois en cours : le même suivi que l'écran
    // Finances complètes (`GET /cotisations/suivi`, mois en cours),
    // total payé, pas le total de tous les temps.
    int cotisationsMois = 0;
    if (state.canReadFinances) {
      try {
        final suivi = await api.getCotisationsSuivi();
        cotisationsMois = suivi.totaux.totalPayeFcfa;
      } catch (_) {
        cotisationsMois = 0;
      }
    }
    RapportConsolide? rapport;
    if (state.isAdmin) {
      try {
        rapport = await api.getRapport();
      } catch (_) {
        rapport = null; // Une sous-église admin n'a pas de réseau : on ignore.
      }
    }
    final maintenant = DateTime.now();
    final fenetres = fenetresPeriodeTableauBord(_periode, maintenant);
    final debut = _aaaammjj(fenetres.debut);
    final fin = _aaaammjj(fenetres.fin);
    final debutPrec = _aaaammjj(fenetres.debutPrec);
    final finPrec = _aaaammjj(fenetres.finPrec);
    // Présences de la période et de la période précédente équivalente
    // (GET /presences/stats, lecture seule, fenêtres arbitraires).
    int presencesJour = 0;
    int presencesPrecedentes = 0;
    try {
      final stats = await api.getPresenceStats(from: debut, to: fin);
      presencesJour = stats.presents;
      final statsPrec =
          await api.getPresenceStats(from: debutPrec, to: finPrec);
      presencesPrecedentes = statsPrec.presents;
    } catch (_) {
      presencesJour = 0; // Sans statistiques lisibles, la carte reste à 0.
      presencesPrecedentes = 0;
    }
    // Nouveaux membres : créés dans la période (GET /membres,
    // created_from / created_to, lecture seule, seul le total sert),
    // et dans la période précédente pour la variation.
    int nouveauxMembres = 0;
    int nouveauxMembresPrecedents = 0;
    try {
      nouveauxMembres = (await api.getMembers(
              limit: 1, createdFrom: debut, createdTo: fin))
          .total;
      nouveauxMembresPrecedents = (await api.getMembers(
              limit: 1, createdFrom: debutPrec, createdTo: finPrec))
          .total;
    } catch (_) {
      nouveauxMembres = 0;
      nouveauxMembresPrecedents = 0;
    }
    // Tableau du jour (maquette, écrans 19 et 36) : visiteurs,
    // demandes, membres à suivre, rapports reçus. Chaque compteur
    // vient d'une vraie lecture serveur ; un échec ne bloque pas le
    // tableau, le compteur reste à 0.
    int visiteursJour = 0;
    int visiteursPrecedents = 0;
    bool visiteursTronques = false;
    int entreesJour = 0;
    int sortiesJour = 0;
    int caisse = 0;
    bool caisseMoisPrecedentNonCloturee = false;
    int prieresEnAttente = 0;
    int liaisonsEnAttente = 0;
    int rapportsRecus = 0;
    int transfertsRattachements = 0;
    int absencesASuivre = 0;
    int anniversairesJour = 0;
    if (state.canReadFinances) {
      try {
        final mouvements = await api.getCaisseMouvements();
        final aujourdHui =
            DateTime(maintenant.year, maintenant.month, maintenant.day);
        // Dernier mois terminé, pour le signal « caisse non clôturée » :
        // il ne se déclenche que s'il y a eu des mouvements ce mois-là.
        final moisPrecedent = dernierMoisTermine(maintenant);
        var mouvementsMoisPrecedent = 0;
        for (final m in mouvements) {
          final date = m.createdAt?.toLocal();
          if (date == null) continue;
          if (date.year == aujourdHui.year &&
              date.month == aujourdHui.month &&
              date.day == aujourdHui.day) {
            if (m.type == 'entree') {
              entreesJour += m.montantFcfa;
            } else {
              sortiesJour += m.montantFcfa;
            }
          }
          if (periodeMois(date) == moisPrecedent) {
            mouvementsMoisPrecedent++;
          }
        }
        caisse = (await api.getCaisseSolde()).solde;
        if (mouvementsMoisPrecedent > 0) {
          try {
            final clotures = await api.getCloturesCaisse();
            caisseMoisPrecedentNonCloturee =
                !clotures.any((c) => c.periode == moisPrecedent);
          } catch (_) {
            // Sans clôtures lisibles, pas de signal inventé.
            caisseMoisPrecedentNonCloturee = false;
          }
        }
      } catch (_) {
        entreesJour = 0;
        sortiesJour = 0;
        caisse = 0;
      }
    }
    if (state.isAdmin) {
      try {
        // Demandes d'adhésion : il n'existe pas de notion
        // d'adhésion côté serveur ; les demandes de rattachement
        // en attente sont la notion réelle la plus proche.
        final demandes = await api.getDemandesLiaison();
        liaisonsEnAttente =
            demandes.where((d) => d.status == 'en_attente').length;
      } catch (_) {
        liaisonsEnAttente = 0;
      }
    }
    if (state.canManageMembers) {
      try {
        // Les 100 visiteurs les plus récents (date_venue décroissante
        // côté serveur) : la variation n'est fiable que si la liste
        // n'est pas tronquée, sinon elle n'est pas affichée.
        final visiteurs = await api.getVisiteurs(limit: 100);
        visiteursTronques = visiteurs.length >= 100;
        bool dansFenetre(String date, DateTime debutF, DateTime finF) =>
            date.compareTo(_aaaammjj(debutF)) >= 0 &&
            date.compareTo(_aaaammjj(finF)) <= 0;
        visiteursJour = visiteurs
            .where(
                (v) => dansFenetre(v.dateVenue, fenetres.debut, fenetres.fin))
            .length;
        visiteursPrecedents = visiteurs
            .where((v) => dansFenetre(
                v.dateVenue, fenetres.debutPrec, fenetres.finPrec))
            .length;
      } catch (_) {
        visiteursJour = 0;
        visiteursPrecedents = 0;
        visiteursTronques = false;
      }
      try {
        final demandes = await api.getDemandesPriere();
        prieresEnAttente = demandes
            .where((d) => d.statut == 'nouvelle' || d.statut == 'en_cours')
            .length;
      } catch (_) {
        prieresEnAttente = 0;
      }
      try {
        final radar = await api.getRadarAbsences();
        absencesASuivre = radar.length;
      } catch (_) {
        absencesASuivre = 0;
      }
      try {
        final anniversaires = await api.getAnniversaires();
        anniversairesJour =
            anniversaires.where((a) => a.joursRestants == 0).length;
      } catch (_) {
        anniversairesJour = 0;
      }
    }
    if (state.isAdmin && (state.church?.isMere ?? false)) {
      try {
        final recus = await api.getRapportsRecus();
        rapportsRecus = recus.length;
      } catch (_) {
        rapportsRecus = 0;
      }
      try {
        final transferts = await api.getTransferts();
        final rattachements = await api.getRattachements();
        transfertsRattachements = transferts.aTraiter.length +
            rattachements.recues
                .where((r) => r.status == 'en_attente')
                .length;
      } catch (_) {
        transfertsRattachements = 0;
      }
    }
    // Église mère d'une annexe (maquette, écran 36) : nom et code.
    // Le code vient des églises de l'état quand l'admin est aussi
    // membre de sa mère ; sinon, GET /moi/mere ne donne que le nom
    // (pas de route par identifiant pour retrouver le code), la
    // ligne s'affiche alors sans code, jamais inventé.
    String? mereNom;
    String? mereCode;
    if (state.isAdmin && !(state.church?.isMere ?? false)) {
      final parentId = state.church?.parentChurchId;
      if (parentId != null) {
        for (final m in state.eglises) {
          if (m.church.id == parentId) {
            mereNom = m.church.name;
            mereCode = m.church.code;
            break;
          }
        }
      }
      if (mereNom == null) {
        try {
          mereNom = (await api.getMaMere()).nom;
        } catch (_) {
          mereNom = null;
        }
      }
    }
    final annonces = await api.getAnnonces();
    List<Culte> cultes = [];
    try {
      cultes = await api.getCultes();
    } catch (_) {
      cultes = []; // Sans culte lisible, la carte « Aujourd'hui » reste vide.
    }
    return _DashboardData(
      membresTotal: membres.total,
      presencesJour: presencesJour,
      presencesPrecedentes: presencesPrecedentes,
      visiteursJour: visiteursJour,
      visiteursPrecedents: visiteursPrecedents,
      visiteursTronques: visiteursTronques,
      nouveauxMembres: nouveauxMembres,
      nouveauxMembresPrecedents: nouveauxMembresPrecedents,
      caisseMoisPrecedentNonCloturee: caisseMoisPrecedentNonCloturee,
      cotisationsMois: cotisationsMois,
      entreesJour: entreesJour,
      sortiesJour: sortiesJour,
      caisse: caisse,
      prieresEnAttente: prieresEnAttente,
      liaisonsEnAttente: liaisonsEnAttente,
      rapportsRecus: rapportsRecus,
      transfertsRattachements: transfertsRattachements,
      absencesASuivre: absencesASuivre,
      anniversairesJour: anniversairesJour,
      mereNom: mereNom,
      mereCode: mereCode,
      rapport: rapport,
      annonces: annonces,
      cultes: cultes,
    );
  }

  /// Libellé d'une carte de chiffres selon la période : « Présences
  /// du jour » pour aujourd'hui, « Présences · 7 jours » sinon.
  String _libelleCartePeriode(String base) {
    if (_periode == PeriodeTableauBord.aujourdHui) return '$base du jour';
    return '$base · ${joursPeriodeTableauBord(_periode)} jours';
  }

  /// Prochain culte : le premier dont la date n'est pas passée.
  Culte? _prochainCulte(List<Culte> cultes) {
    final maintenant = DateTime.now();
    final futurs = cultes.where((c) {
      final d = c.date;
      return d != null && !d.isBefore(maintenant);
    }).toList();
    futurs.sort((a, b) => a.date!.compareTo(b.date!));
    return futurs.isEmpty ? null : futurs.first;
  }

  /// Annonces récentes : les 3 dernières, date la plus récente d'abord.
  List<Announcement> _annoncesRecentes(List<Announcement> annonces) {
    final triees = List<Announcement>.of(annonces);
    triees.sort((a, b) {
      final da = a.createdAt;
      final db = b.createdAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return triees.take(3).toList();
  }

  void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ecran),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final church = state.church;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _future = _load());
        await _future;
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // En-tête de l'espace connecté : nom et logo de
                // l'église (règle d'Axel, 14 novembre 2026), pas le
                // logo e-System Church en grand. Pour une annexe,
                // l'en-tête montre aussi le rôle, le badge « Annexe »
                // et l'église mère (maquette, écran 36).
                if (state.isAdmin && !(church?.isMere ?? false))
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF8EA),
                      border: Border.all(
                        color: const Color(0xFFECD27A),
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: EnteteEspace(eglise: church),
                  )
                else
                  EnteteEspace(eglise: church),
                const SizedBox(height: AppSpacing.md),
                // Sélecteur de période (pastilles, modèle Facebook) :
                // il pilote les chiffres et leurs variations.
                _PastillesPeriode(
                  periode: _periode,
                  onChoisir: (periode) {
                    if (periode == _periode) return;
                    setState(() {
                      _periode = periode;
                      _future = _load();
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                FutureBuilder<_DashboardData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: AppLoading(),
                      );
                    }
                    if (snapshot.hasError) {
                      return AppError(
                        message: snapshot.error.toString(),
                        onRetry: () =>
                            setState(() => _future = _load()),
                      );
                    }
                    final data = snapshot.data!;
                    final prochain = _prochainCulte(data.cultes);
                    final recentes = _annoncesRecentes(data.annonces);
                    // Signaux d'attention, uniquement à partir de données
                    // déjà chargées : la carte ne s'affiche que s'il y
                    // en a au moins un.
                    final signaux = signauxAttention(
                      abonnement: state.abonnement,
                      demandesATraiter: data.prieresEnAttente +
                          data.liaisonsEnAttente +
                          data.rapportsRecus +
                          data.transfertsRattachements,
                      caisseMoisPrecedentNonCloturee:
                          data.caisseMoisPrecedentNonCloturee,
                      moisPrecedent:
                          libellePeriodeMois(dernierMoisTermine()),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (signaux.isNotEmpty) ...[
                          _CarteAttention(signaux: signaux),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        // Aujourd'hui (maquette, écrans 19 et 36) :
                        // carte claire quand aucun culte n'est programmé,
                        // violet profond quand un culte est programmé.
                        // Aucun chiffre inventé.
                        Container(
                          decoration: prochain == null
                              ? BoxDecoration(
                                  color: AppTheme.fondPapier,
                                  borderRadius: BorderRadius.circular(AppRadii.lg),
                                )
                              : BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppTheme.violetProfond,
                                      AppTheme.violetSecondaire,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(AppRadii.lg),
                                ),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Aujourd’hui',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      // Maquette, écrans 19 et 36 : 16 px.
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              color: prochain == null
                                                  ? AppTheme.violetProfond
                                                  : Colors.white,
                                              fontSize: AppFontSizes.s16),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.or,
                                      borderRadius:
                                          BorderRadius.circular(AppRadii.pill),
                                    ),
                                    child: const Text(
                                      'Prochain culte',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: AppFontSizes.s11_5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.violetProfond,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              if (prochain == null) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.calendar_today_outlined,
                                      color: AppTheme.violetProfond,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Aucun culte programmé aujourd’hui',
                                            // Maquette, écrans 19 et 36 : 13,5 px.
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(fontSize: AppFontSizes.s13_5),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            (church?.isMere ?? false)
                                                ? 'Le culte du jour s’affichera ici dès qu’il sera créé, avec l’heure et le lieu.'
                                                : 'Le prochain culte de l’annexe s’affichera ici dès qu’il sera créé, avec l’heure et le lieu.',
                                            // Maquette, écrans 19 et 36 : 11,5 px.
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(fontSize: AppFontSizes.s11_5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _MiniStatJour(
                                        libelle: 'Présences du jour',
                                        valeur: '${data.presencesJour}',
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: _MiniStatJour(
                                        libelle: 'Visiteurs du jour',
                                        valeur: '${data.visiteursJour}',
                                      ),
                                    ),
                                  ],
                                ),
                              ] else
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.white.withValues(
                                            alpha: 0.25)),
                                    borderRadius: BorderRadius.circular(AppRadii.md),
                                  ),
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    children: [
                                      Text(
                                        prochain.titre,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        // Maquette, écrans 19 et 36 : 13,5 px.
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                color: Colors.white,
                                                fontSize: AppFontSizes.s13_5),
                                      ),
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(
                                        '${formatDateTimeSansDecalage(prochain.date)}'
                                        '${prochain.lieu == null || prochain.lieu!.isEmpty ? '' : ' · ${prochain.lieu}'}'
                                        '${prochain.orateur == null || prochain.orateur!.isEmpty ? '' : ' · ${prochain.orateur}'}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        // Maquette, écrans 19 et 36 : 11,5 px.
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Colors.white70,
                                                fontSize: AppFontSizes.s11_5),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // Chiffres de mon église (maquette, écrans 19
                        // et 36) : compteurs réels, rien d'inventé.
                        // L'aide sous un compteur est son texte vide
                        // du HTML quand il est à 0.
                        const SectionTitle(title: 'Chiffres de mon église'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Maquette, écran 19 : 4 cartes, Membres,
                            // Présences du jour, Visiteurs du jour,
                            // Nouveaux membres. « Contributions du
                            // mois » est retirée (décision d'Axel) ;
                            // Visiteurs du jour est la 4e carte,
                            // choisie par Muse sur délégation d'Axel.
                            return _GrilleCartes(
                              colonnes: constraints.maxWidth > 600 ? 4 : 2,
                              enfants: [
                                StatCard(
                                  label: 'Membres',
                                  value: '${data.membresTotal}',
                                  icon: Icons.people_outline,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                  // Variation du total = nouveaux de la
                                  // période contre nouveaux de la
                                  // précédente (pas d'historique du total
                                  // côté serveur).
                                  variation: texteVariation(
                                      data.nouveauxMembres,
                                      data.nouveauxMembresPrecedents),
                                ),
                                StatCard(
                                  label: _libelleCartePeriode('Présences'),
                                  value: '${data.presencesJour}',
                                  icon: Icons.how_to_reg_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.vertFonce,
                                  variation: texteVariation(
                                      data.presencesJour,
                                      data.presencesPrecedentes),
                                ),
                                StatCard(
                                  label: _libelleCartePeriode('Visiteurs'),
                                  value: '${data.visiteursJour}',
                                  icon: Icons.person_outline,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                  // Liste tronquée à 100 : la variation
                                  // ne serait pas fiable, on ne l'affiche
                                  // pas plutôt qu'un faux chiffre.
                                  variation: data.visiteursTronques
                                      ? null
                                      : texteVariation(data.visiteursJour,
                                          data.visiteursPrecedents),
                                ),
                                StatCard(
                                  label: 'Nouveaux membres',
                                  value: '${data.nouveauxMembres}',
                                  icon: Icons.person_add_outlined,
                                  tailleValeur: 22,
                                  color: AppTheme.violetProfond,
                                  variation: texteVariation(
                                      data.nouveauxMembres,
                                      data.nouveauxMembresPrecedents),
                                  aide: data.nouveauxMembres == 0
                                      ? 'Aucun nouveau membre'
                                      : null,
                                  onTap: () => widget.onAller(1),
                                ),
                              ],
                            );
                          },
                        ),
                        // Contributions du jour (maquette, écran 19) :
                        // entrées, sorties, cotisations du mois et
                        // caisse.
                        if (state.canReadFinances) ...[
                          const SectionTitle(
                              title: 'Contributions du jour'),
                          SoftCard(
                            child: Column(
                              children: [
                                _LigneChiffre(
                                  titre: 'Entrées du jour',
                                  valeur: formatFcfa(data.entreesJour),
                                  tailleValeur: 17,
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Sorties du jour',
                                  valeur: formatFcfa(data.sortiesJour),
                                  tailleValeur: 17,
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Cotisations du mois',
                                  valeur: formatFcfa(data.cotisationsMois),
                                  tailleValeur: 17,
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Caisse',
                                  valeur: formatFcfa(data.caisse),
                                  tailleValeur: 17,
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Demandes en attente (mère, écran 19) ou
                        // À traiter (annexe, écran 36) : 4 compteurs
                        // pour la mère, 2 pour l'annexe.
                        if (state.isAdmin || state.canManageMembers) ...[
                          SectionTitle(
                              title: (church?.isMere ?? false)
                                  ? 'Demandes en attente'
                                  : 'À traiter'),
                          SoftCard(
                            child: Column(
                              children: [
                                if (state.canManageMembers)
                                  _LigneChiffre(
                                    titre: 'Demandes de prière',
                                    sousTitre:
                                        'Reçues des membres, à traiter',
                                    valeur: '${data.prieresEnAttente}',
                                    onTap: () => _ouvrir(
                                        context, const PrieresScreen()),
                                  ),
                                if (state.canManageMembers &&
                                    state.isAdmin)
                                  const Divider(),
                                if (state.isAdmin)
                                  _LigneChiffre(
                                    titre: 'Demandes d’adhésion',
                                    sousTitre:
                                        'Visiteurs et nouveaux à valider',
                                    valeur: '${data.liaisonsEnAttente}',
                                    onTap: () => _ouvrir(
                                        context, const MonEgliseScreen()),
                                  ),
                                if (state.isAdmin &&
                                    (church?.isMere ?? false)) ...[
                                  const Divider(),
                                  _LigneChiffre(
                                    titre: 'Rapports d’annexe reçus',
                                    sousTitre:
                                        'Envoyés par les annexes, à lire',
                                    valeur: '${data.rapportsRecus}',
                                    onTap: () => _ouvrir(context,
                                        const RapportsRecusScreen()),
                                  ),
                                  const Divider(),
                                  _LigneChiffre(
                                    titre: 'Transferts et rattachements',
                                    sousTitre:
                                        'Entre l’église mère et ses annexes',
                                    valeur:
                                        '${data.transfertsRattachements}',
                                    onTap: () => _ouvrir(
                                        context, const TransfertsScreen()),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        // Membres à suivre (maquette, écran 19) :
                        // absences à relancer, anniversaires du jour,
                        // nouveaux à accueillir.
                        if (state.canManageMembers) ...[
                          const SectionTitle(title: 'Membres à suivre'),
                          SoftCard(
                            child: Column(
                              children: [
                                _LigneChiffre(
                                  titre: 'Absences à relancer',
                                  sousTitre: data.absencesASuivre == 0
                                      ? 'Aucune absence signalée'
                                      : 'Absents plusieurs cultes de suite',
                                  valeur: '${data.absencesASuivre}',
                                  onTap: () => _ouvrir(
                                      context, const PastoralScreen()),
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Anniversaires du jour',
                                  sousTitre: data.anniversairesJour == 0
                                      ? 'Aucun anniversaire aujourd’hui'
                                      : null,
                                  valeur: '${data.anniversairesJour}',
                                  onTap: () => widget.onAller(1),
                                ),
                                const Divider(),
                                _LigneChiffre(
                                  titre: 'Nouveaux à accueillir',
                                  sousTitre: data.nouveauxMembres == 0
                                      ? 'Aucun nouveau membre'
                                      : null,
                                  valeur: '${data.nouveauxMembres}',
                                  onTap: () => widget.onAller(1),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (data.rapport != null) ...[
                          const SectionTitle(title: 'Mes annexes'),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (data.rapport!.sousEglises.isEmpty) ...[
                                  if (church?.isMere ?? false) ...[
                                    // État vide de la maquette, écran 19.
                                    const Center(
                                      child: Text(
                                        'Aucun établissement relié',
                                        textAlign: TextAlign.center,
                                        // Maquette, écrans 19 et 36 : 13 px.
                                        style: TextStyle(fontSize: AppFontSizes.s13),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    const Center(
                                      child: Text(
                                        'Aucune alerte d’annexe.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: AppFontSizes.s13),
                                      ),
                                    ),
                                  ] else
                                    const Text(
                                      'Votre église est une annexe : elle ne peut pas avoir de sous-église.',
                                    ),
                                ] else ...[
                                  Text(
                                    'Total de mes églises',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  // Design couleurs messagerie (16 nov.
                                  // 2026) : compteurs du réseau en
                                  // pastille or clair, texte violet.
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.orClair,
                                      borderRadius:
                                          BorderRadius.circular(AppRadii.md),
                                    ),
                                    child: Text(
                                        '${pluriel(data.rapport!.totauxReseau.membresActifs, 'membre actif', 'membres actifs')} · '
                                        '${pluriel(data.rapport!.totauxReseau.nombreContributions, 'contribution')} · '
                                        '${formatFcfa(data.rapport!.totauxReseau.totalFcfa)}',
                                        style: const TextStyle(
                                          fontSize: AppFontSizes.s12_5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.violetProfond,
                                        )),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  const Divider(),
                                  ...data.rapport!.sousEglises.map(
                                    (s) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.account_tree_outlined,
                                        color: AppTheme.orFonce,
                                      ),
                                      title: Text(
                                        s.egliseNom,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: AppFontSizes.s13_5),
                                      ),
                                      subtitle: Text(
                                          '${s.membresActifs} membres · ${formatFcfa(s.totalFcfa)}'
                                          '${s.niveau == 1 ? '' : ' · niveau ${s.niveau}'}',
                                          style: const TextStyle(fontSize: AppFontSizes.s11_5)),
                                      trailing: Text(
                                        '${s.nombreContributions} contributions',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        // Actions rapides (maquette, écran 19) : Nouveau culte
                        // et Nouvelle annonce seulement. Ajouter un membre se
                        // fait depuis l'onglet Membres, les finances depuis
                        // l'onglet Finances : pas de doublon. Seulement celles
                        // que le rôle permet ; sans aucune action permise, rien
                        // ne s'affiche.
                        if (state.canManageMembers || state.isAdmin) ...[
                          const SectionTitle(title: 'Actions rapides'),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return _GrilleCartes(
                                colonnes: constraints.maxWidth > 600 ? 4 : 2,
                                enfants: [
                                  if (state.canManageMembers)
                                    _ActionRapide(
                                      icone: Icons.church_outlined,
                                      titre: 'Nouveau culte',
                                      sousTitre: (church?.isMere ?? false)
                                          ? 'Créer le prochain culte de l’église'
                                          : 'Créer le prochain culte de l’annexe',
                                      onTap: () => ouvrirNouveauCulte(context),
                                    ),
                                  if (state.isAdmin)
                                    _ActionRapide(
                                      icone: Icons.campaign_outlined,
                                      titre: 'Nouvelle annonce',
                                      sousTitre: (church?.isMere ?? false)
                                          ? 'Informer les membres de l’église'
                                          : 'Informer les membres de l’annexe',
                                      onTap: () => _ouvrir(
                                          context, const AnnoncesScreen()),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                        // Mon église mère (annexe, maquette, écran 36) :
                        // nom et code de la mère, bouton d'envoi du
                        // rapport. Pour une mère, c'est la section
                        // « Mes annexes » ci-dessus qui s'affiche.
                        if (state.isAdmin &&
                            !(church?.isMere ?? false)) ...[
                          const SectionTitle(title: 'Mon église mère'),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (data.mereNom != null) ...[
                                  Text(
                                    'Église mère ${data.mereNom}',
                                    // Maquette, écran 36 : 13 px.
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontSize: AppFontSizes.s13),
                                  ),
                                  if (data.mereCode != null) ...[
                                    const SizedBox(height: AppSpacing.xxs),
                                    // Maquette, écran 36 : 13 px. Pastille
                                    // or clair (design couleurs messagerie).
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: AppSpacing.xxs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.orClair,
                                        borderRadius:
                                            BorderRadius.circular(AppRadii.md),
                                      ),
                                      child: Text(
                                        'Code ${data.mereCode}',
                                        style: const TextStyle(
                                          fontSize: AppFontSizes.s13,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.violetProfond,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Le rapport part à ${data.mereNom}'
                                    '${data.mereCode != null ? ' · ${data.mereCode}' : ''}.',
                                    // Maquette, écran 36 : 11,5 px.
                                    style:
                                        const TextStyle(fontSize: AppFontSizes.s11_5),
                                  ),
                                ] else
                                  const Text(
                                    'Contactez votre église mère et envoyez '
                                    'vos rapports par e-mail, directement '
                                    'depuis votre espace.',
                                  ),
                                const SizedBox(height: AppSpacing.sm),
                                BoutonDoux(
                                  label:
                                      'Envoyer un rapport à mon église mère',
                                  icon: Icons.email_outlined,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const RapportsMereScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SectionTitle(title: 'Annonces récentes'),
                        if (recentes.isEmpty)
                          SoftCard(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                // État vide de la projection, mot pour mot.
                                Text(
                                  'Aucune annonce',
                                  // Maquette, écrans 19 et 36 : 14 px.
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontSize: AppFontSizes.s14),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                const Text(
                                  'Les annonces publiées pour l’église s’afficheront ici.',
                                  // Maquette, écrans 19 et 36 : 11,5 px.
                                  style: TextStyle(fontSize: AppFontSizes.s11_5),
                                ),
                              ],
                            ),
                          )
                        else
                          SoftCard(
                            child: Column(
                              children: [
                                ...recentes.map(
                                  (a) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.campaign_outlined),
                                    title: Text(
                                      a.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: AppFontSizes.s13_5),
                                    ),
                                    subtitle: Text(
                                      '${a.body}'
                                      '${a.createdAt == null ? '' : ' · ${formatDate(a.createdAt)}'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: AppFontSizes.s11_5),
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AnnoncesScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => _ouvrir(
                                        context, const AnnoncesScreen()),
                                    icon: const Icon(
                                        Icons.campaign_outlined),
                                    label: const Text('Toutes les annonces', style: TextStyle(fontSize: AppFontSizes.s13_5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },                ),
                const SizedBox(height: AppSpacing.md),
                // Rapports reçus, pour une mère (la carte « Mon
                // église mère » de l'annexe est dans le FutureBuilder,
                // elle a besoin des données chargées).
                if (state.isAdmin &&
                    (church?.isMere ?? false)) ...[
                  const SectionTitle(title: 'Rapports reçus'),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rapports reçus',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Lisez les rapports envoyés par vos '
                          'églises annexes.',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        BoutonDoux(
                          label: 'Ouvrir les rapports reçus',
                          icon: Icons.inbox_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RapportsRecusScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastilles de sélection de la période (modèle Facebook) : la
/// pastille choisie est violet profond, les autres sont bordurées.
class _PastillesPeriode extends StatelessWidget {
  final PeriodeTableauBord periode;
  final ValueChanged<PeriodeTableauBord> onChoisir;

  const _PastillesPeriode({required this.periode, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    // Wrap plutôt que Row : sur un petit écran les pastilles passent
    // à la ligne au lieu de déborder.
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final p in PeriodeTableauBord.values)
          InkWell(
            onTap: () => onChoisir(p),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: p == periode
                    ? AppTheme.violetProfond
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: p == periode
                    ? null
                    : Border.all(
                        color:
                            AppTheme.violetProfond.withValues(alpha: 0.4)),
              ),
              child: Text(
                libellePeriodeTableauBord(p),
                style: TextStyle(
                  fontSize: AppFontSizes.s12_5,
                  fontWeight:
                      p == periode ? FontWeight.bold : FontWeight.normal,
                  color: p == periode
                      ? Colors.white
                      : AppTheme.violetProfond,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Carte d'attention : un signal par ligne, sur fond or clair.
/// Ne s'affiche que s'il y a au moins un signal réel.
class _CarteAttention extends StatelessWidget {
  final List<String> signaux;

  const _CarteAttention({required this.signaux});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.orClair,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_outlined,
                color: AppTheme.orFonce,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'À surveiller',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: AppFontSizes.s13_5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.violetProfond,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final signal in signaux)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                '• $signal',
                style: const TextStyle(fontSize: AppFontSizes.s12_5),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grille à hauteurs intrinsèques : chaque rangée prend la hauteur
/// de sa carte la plus haute, sans ratio fixe. Un childAspectRatio
/// fige la hauteur depuis la largeur : il laisse un vide blanc quand
/// le contenu est court et tronque quand il grandit (l'ancien 0,85,
/// puis 1,25, ne faisaient que déplacer le problème). Ici chaque
/// carte s'adapte à son contenu.
class _GrilleCartes extends StatelessWidget {
  final int colonnes;
  final List<Widget> enfants;

  const _GrilleCartes({required this.colonnes, required this.enfants});

  @override
  Widget build(BuildContext context) {
    const espacement = AppSpacing.sm;
    final rangees = <Widget>[];
    for (var debut = 0; debut < enfants.length; debut += colonnes) {
      final fin = debut + colonnes > enfants.length
          ? enfants.length
          : debut + colonnes;
      final rangee = enfants.sublist(debut, fin);
      rangees.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < colonnes; i++) ...[
                if (i > 0) const SizedBox(width: espacement),
                Expanded(
                  child: i < rangee.length
                      ? rangee[i]
                      : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rangees.length; i++) ...[
          if (i > 0) const SizedBox(height: espacement),
          rangees[i],
        ],
      ],
    );
  }
}

/// Une action rapide : carte avec icône or, titre et sous-titre
/// (projection, IMG_4030). Toute la carte est cliquable.
class _ActionRapide extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  const _ActionRapide({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: AppTheme.orFonce, size: 28),
              const SizedBox(height: AppSpacing.xs),
              Text(
                titre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // Maquette, écrans 19 et 36 : 13,5 px.
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                        fontWeight: FontWeight.bold, fontSize: AppFontSizes.s13_5),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                sousTitre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // Maquette, écrans 19 et 36 : 11,5 px.
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: AppFontSizes.s11_5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne de chiffres dans un groupe du tableau de bord
/// (maquette, écrans 19 et 36) : titre, sous-titre facultatif et
/// valeur à droite, cliquable quand un écran la détaille.
class _LigneChiffre extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final String valeur;
  final VoidCallback? onTap;
  // Maquette : compteurs 11,5 px (Demandes, Membres à suivre),
  // montants 17 px (Contributions du jour).
  final double tailleValeur;

  const _LigneChiffre({
    required this.titre,
    this.sousTitre,
    required this.valeur,
    this.onTap,
    this.tailleValeur = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final sousTitre = this.sousTitre;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        titre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSizes.s13_5),
      ),
      subtitle: sousTitre == null
          ? null
          : Text(
              sousTitre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppFontSizes.s11_5),
            ),
      trailing: Text(
        valeur,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.styleCode.copyWith(
          fontSize: tailleValeur,
          fontWeight: FontWeight.bold,
          color: AppTheme.violetProfond,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Mini-stat dans la carte « Aujourd'hui » (maquette, écrans 19 et
/// 36) : libellé en capitales, valeur en grand, sur fond blanc.
class _MiniStatJour extends StatelessWidget {
  final String libelle;
  final String valeur;

  const _MiniStatJour({required this.libelle, required this.valeur});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libelle.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppFontSizes.s10,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            valeur,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
