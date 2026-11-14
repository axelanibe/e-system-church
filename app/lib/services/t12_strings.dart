/// Chaînes des écrans de la tranche T12 (US15) : français par défaut,
/// anglais au choix. Seuls les nouveaux écrans sont traduits ; le reste
/// de l'application reste en français.
///
/// Les libellés métier (types de don, statuts, catégories) viennent du
/// serveur et restent tels que l'église les a saisis.
class T12Strings {
  final bool estAnglais;

  const T12Strings(this.estAnglais);

  String _t(String fr, String en) => estAnglais ? en : fr;

  // -- Titres ---------------------------------------------------------------
  String get promesses => _t('Promesses de don', 'Giving pledges');
  String get donsNature => _t('Dons en nature', 'In-kind gifts');
  String get visiteurs => _t('Visiteurs', 'Visitors');
  String get evenementsVie => _t('Événements de vie', 'Life events');
  String get transparence => _t('Transparence financière', 'Financial transparency');
  String get cartePortefeuille => _t('Carte dans le portefeuille', 'Card in wallet');
  String get whatsapp => _t('WhatsApp', 'WhatsApp');
  String get alertesMere => _t('Alertes du réseau', 'Network alerts');
  String get listesConfigurables => _t('Listes configurables', 'Configurable lists');
  String get consultations => _t('Consultations sensibles', 'Sensitive views');
  String get langueEtDonnees => _t('Langue et données', 'Language and data');

  // -- Actions ---------------------------------------------------------------
  String get ajouter => _t('Ajouter', 'Add');
  String get enregistrer => _t('Enregistrer', 'Save');
  String get annuler => _t('Annuler', 'Cancel');
  String get fermer => _t('Fermer', 'Close');
  String get confirmer => _t('Confirmer', 'Confirm');
  String get retour => _t('Retour', 'Back');
  String get recharger => _t('Recharger', 'Reload');
  String get traiter => _t('Marquer traitée', 'Mark as handled');

  // -- États -----------------------------------------------------------------
  String get chargement => _t('Chargement…', 'Loading…');
  String get vide => _t('Rien pour le moment.', 'Nothing yet.');
  String get erreurChargement => _t('Chargement impossible.', 'Could not load.');
  String get enregistre => _t('Enregistré.', 'Saved.');
  String get montantInvalide => _t('Montant invalide.', 'Invalid amount.');
  String get champObligatoire => _t('Ce champ est obligatoire.', 'This field is required.');

  // -- Promesses (US4) --------------------------------------------------------
  String get nouvellePromesse => _t('Nouvelle promesse', 'New pledge');
  String get montantTotal => _t('Montant total (FCFA)', 'Total amount (FCFA)');
  String get nbVersements => _t('Nombre de versements', 'Number of instalments');
  String get dateDebut => _t('Date de début', 'Start date');
  String get recu => _t('Reçu', 'Received');
  String get reste => _t('Reste', 'Remaining');
  String get echeances => _t('Échéances', 'Instalments');
  String get verser => _t('Enregistrer le versement', 'Record the payment');
  String get versementEgal => _t(
      'Le versement doit égaler le montant de l’échéance.',
      'The payment must equal the instalment amount.');
  String get promesseAnnulee => _t('Promesse annulée.', 'Pledge cancelled.');
  String get promesseTerminee => _t('Terminée', 'Completed');
  String get promesseEnCours => _t('En cours', 'In progress');
  String get versementEnAttente => _t(
      'Versement enregistré, en attente de confirmation.',
      'Payment recorded, awaiting confirmation.');
  String get choisirMembre => _t('Choisir le membre', 'Choose the member');
  String get moyenPaiement => _t('Moyen de paiement', 'Payment method');

  // -- Dons en nature (US5) ---------------------------------------------------
  String get nouveauDonNature => _t('Nouveau don en nature', 'New in-kind gift');
  String get description => _t('Description', 'Description');
  String get quantite => _t('Quantité', 'Quantity');
  String get typeDon => _t('Type de don', 'Gift type');
  String get materiel => _t('Matériel', 'Goods');
  String get nourriture => _t('Nourriture', 'Food');
  String get temps => _t('Temps', 'Time');
  String get heures => _t('Heures', 'Hours');
  String get anonyme => _t('Don anonyme', 'Anonymous gift');
  String get donHorsFinances => _t(
      'Les dons en nature ne comptent pas dans les totaux financiers.',
      'In-kind gifts never count in financial totals.');

  // -- Visiteurs (US6) ---------------------------------------------------------
  String get nouveauVisiteur => _t('Nouveau visiteur', 'New visitor');
  String get nom => _t('Nom', 'Name');
  String get dateVenue => _t('Date de venue', 'Visit date');
  String get telephone => _t('Téléphone', 'Phone');
  String get devenirMembre => _t('Devenu membre', 'Became a member');
  String get visiteurDevenuMembre => _t('Visiteur devenu membre.', 'Visitor became a member.');

  // -- Événements de vie (US7) -------------------------------------------------
  String get prochainsJours => _t('Prochains jours', 'Coming days');
  String get anniversaire => _t('Anniversaire', 'Birthday');
  String get mariage => _t('Mariage', 'Wedding');
  String get conversion => _t('Conversion', 'Conversion');
  String get bapteme => _t('Baptême', 'Baptism');
  String get joursRestants => _t('jours restants', 'days left');
  String get aujourdhui => _t('aujourd’hui', 'today');
  String get masquer => _t('Ne pas rappeler', 'Do not remind');
  String get masquesEnregistres => _t('Choix enregistrés.', 'Choices saved.');

  // -- Transparence (US8) -------------------------------------------------------
  String get recettes => _t('Recettes', 'Income');
  String get depenses => _t('Dépenses', 'Expenses');
  String get solde => _t('Solde', 'Balance');
  String get parType => _t('Par type', 'By type');
  String get parPoste => _t('Par poste', 'By budget line');
  String get nonActivee => _t(
      'La transparence financière n’est pas activée pour les membres de votre église.',
      'Financial transparency is not enabled for members of your church.');
  String get sansLigneNominative => _t(
      'Totaux seulement, aucune ligne nominative.',
      'Totals only, no personal lines.');

  // -- Portefeuille (US9) ---------------------------------------------------------
  String get exporterPass => _t('Exporter le pass', 'Export the pass');
  String get aucunCompteWallet => _t(
      'Aucun compte Apple Wallet ni Google Wallet n’est branché : l’export est un fichier pass générique, sans coût engagé.',
      'No Apple Wallet or Google Wallet account is connected: the export is a generic pass file, with no cost incurred.');
  String get passCopie => _t('Pass copié.', 'Pass copied.');

  // -- WhatsApp (US10) -------------------------------------------------------------
  String get consentementWhatsapp => _t(
      'Recevoir des messages WhatsApp de mon église',
      'Receive WhatsApp messages from my church');
  String get consentementSms => _t(
      'Recevoir les rappels par SMS si les données sont coupées',
      'Receive reminders by SMS if data is off');
  String get aucunFournisseur => _t(
      'Aucun fournisseur WhatsApp n’est branché : aucun envoi réel n’est possible tant qu’Axel n’a pas choisi le canal.',
      'No WhatsApp provider is connected: no real message can be sent until Axel chooses the channel.');
  String get consentementsEnregistres => _t('Consentements enregistrés.', 'Consents saved.');

  // -- Alertes mère (US11) ------------------------------------------------------------
  String get detecter => _t('Détecter les alertes', 'Detect alerts');
  String get alerteInactive => _t('Antenne inactive', 'Inactive branch');
  String get alerteBaisse => _t('Contributions en baisse', 'Contributions falling');
  String get alerteRapport => _t('Rapport non soumis', 'Report not submitted');
  String get alerteTraitee => _t('Alerte traitée.', 'Alert handled.');
  String get aucuneAlerte => _t('Aucune alerte ouverte.', 'No open alert.');
  String get detectionTerminee => _t('Détection terminée.', 'Detection done.');
  String get ouvertesSeulement => _t('Ouvertes seulement', 'Open only');
  String get toutes => _t('Toutes', 'All');

  // -- Listes configurables (US12, US13) -----------------------------------------------
  String get ajouterLibelle => _t('Ajouter un libellé', 'Add a label');
  String get libelle => _t('Libellé', 'Label');
  String get niveau => _t('Niveau de droits', 'Permission level');
  String get archiver => _t('Archiver', 'Archive');
  String get desarchiver => _t('Rétablir', 'Restore');
  String get archive => _t('Archivé', 'Archived');
  String get roles => _t('Rôles', 'Roles');
  String get categoriesDepense => _t('Catégories de dépense', 'Expense categories');
  String get categoriesRecette => _t('Catégories de recette', 'Income categories');
  String get statutsMembre => _t('Statuts de membre', 'Member statuses');
  String get departements => _t('Départements', 'Departments');

  // -- Seuils et dîme (US14) --------------------------------------------------------------
  String get seuilsEtDime => _t('Seuils et dîme', 'Thresholds and tithe');
  String get dimeSuggeree => _t('Dîme suggérée (FCFA)', 'Suggested tithe (FCFA)');
  String get dimeDesactivee => _t('Vide = désactivée, jamais imposée.', 'Empty = disabled, never imposed.');
  String get seuilInactivite => _t('Inactivité d’une antenne (semaines)', 'Branch inactivity (weeks)');
  String get seuilBaisse => _t('Baisse des contributions (%)', 'Contribution drop (%)');
  String get transparenceMembres => _t(
      'Transparence visible par les membres', 'Transparency visible to members');

  // -- Consultations (US17) ------------------------------------------------------------------
  String get quiAConsulte => _t('Qui a consulté ma fiche', 'Who viewed my record');
  String get lecture => _t('Lecture', 'View');
  String get aucuneConsultation => _t('Aucune consultation.', 'No views.');

  // -- Langue et données (US15, US16) --------------------------------------------------------
  String get langue => _t('Langue des nouveaux écrans', 'Language of new screens');
  String get francais => _t('Français', 'French');
  String get anglais => _t('Anglais', 'English');
  String get modeEconomique => _t('Mode économique', 'Low-data mode');
  String get modeEconomiqueDetail => _t(
      'Coupe le chargement des photos en réseau pour économiser les données.',
      'Stops loading photos over the network to save data.');
  String get repliSmsNote => _t(
      'Le repli SMS dépend d’un fournisseur non choisi : aucun envoi réel, aucun coût.',
      'The SMS fallback needs a provider that has not been chosen: no real sending, no cost.');
}
