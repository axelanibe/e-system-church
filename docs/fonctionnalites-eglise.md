# e-System Church — Toutes les fonctionnalités d'une église

Spécification demandée par Bouf le 10 novembre 2026 : « toutes les
fonctionnalités dont une église aura besoin pour fonctionner, de façon
générale ». Ce document définit le périmètre complet. Chaque module
indique ses tables (PostgreSQL), ses routes API et ses écrans Flutter.

Règles valables pour tous les modules : isolation stricte par église
(chaque requête filtrée par la `church_id` de la session) ; rôles par
église (admin, pasteur, trésorier, secrétaire, responsable, membre) ;
journal d'audit ; la mère voit les totaux consolidés, pas le détail
d'une antenne sauf autorisation.

## Règle absolue : aucune donnée inventée dans l'application

Exigence de Bouf (10/11) : l'application ne contient **aucune donnée
inventée** — pas de membres, de noms, de montants, de statistiques ou
de contenus fictifs présentés comme réels. L'appli n'affiche que les
données réelles de l'église, venues de l'API et de sa base. Quand il
n'y a pas encore de données, l'écran affiche un état vide explicite
(« Aucun membre pour l'instant », « Aucune contribution »), jamais un
exemple inventé.

Conséquence : le mode démo avec les données fictives « Grâce Divine »
(comptes `admin@gracedivine.ci` / `demo1234`, membres, montants et
statistiques d'exemple) est **supprimé** de l'application
(`mock_api_service.dart`, `mock_data.dart` et leurs usages). Les tests
se font désormais contre la vraie API avec une vraie base PostgreSQL
(schéma exécuté, `npm run migrate`). Si un jeu de données de test est
nécessaire, il doit être constitué de données réelles fournies par
Bouf, ou d'exemples explicitement approuvés par lui et marqués comme
tels — jamais inventés par l'implémentation.

Déjà fait (ne pas reconstruire) : inscription / arborescence /
rattachements, membres de base, contributions (dîmes, offrandes, dons),
annonces, rapports consolidés, carte de membre avec vrai QR (Muse,
PR #2), transfert de membre entre branches (Muse, PR #3).

## 1. Membres (compléter)

- Familles : rattacher des membres à une famille, chef de famille.
- Statuts : membre, sympathisant, nouveau converti, en formation,
  suspendu, parti. Historique des changements de statut.
- Baptême : date, lieu, pasteur officiant, certificat.
- Enfants rattachés à leurs parents (lien parent-enfant validé).
- Départements et cellules / groupes de maison : affectation, responsable.
- Tables : `familles`, `membre_statuts` (historique), `baptemes`,
  `liens_parent_enfant` (existe côté Connexion Prophétique, à adapter),
  `departements`, `cellules`, `membre_departements`, `membre_cellules`.
- Routes : CRUD familles, statuts, baptêmes, départements, cellules,
  affectations.
- Écrans : fiche membre enrichie (famille, statut, baptême, département,
  cellule), annuaire avec filtres, liste des familles.

## 2. Cultes et programmes

- Cultes réguliers : types (dimanche matin, mercredi soir, veillée…),
  horaires, lieu / salle.
- Ordre de culte : déroulé (louange, prière, prédication, offrandes…),
  intervenants par partie, durée.
- Événements spéciaux : mariage, baptême d'eau, dédicace d'enfant,
  funérailles, conférence, campagne, jeûne.
- Tables : `culte_types`, `cultes`, `ordre_culte_items`,
  `evenements_speciaux`.
- Routes : CRUD cultes, ordres de culte, événements spéciaux.
- Écrans : planning des cultes, détail d'un culte avec son ordre,
  création d'événement spécial.

## 3. Présences

- Pointage aux cultes et réunions : manuel, par liste, par scan QR
  (carte de membre).
- Présences par département, cellule, classe d'enfants.
- Statistiques : taux de présence par culte, par membre, par période.
- Tables : `presences` (étendre `attendances` : membre, culte /
  événement, mode de pointage, présent / absent / excusé).
- Routes : pointer, liste des présences d'un culte, statistiques.
- Écrans : feuille de présence, scan QR, statistiques de présence.

## 4. Finances (compléter)

- Postes budgétaires : recettes (dîmes, offrandes, dons, collectes
  spéciales) et dépenses (loyer, salaires, missions, œuvres sociales,
  matériel) ; budget annuel par poste, suivi du réalisé.
- Caisse : entrées / sorties, solde, clôture de caisse.
- Dépenses avec justificatif, validation par le trésorier puis le pasteur.
- Reçus automatiques (existant), rapports financiers par période,
  par branche (mère : détail + total, par branche, par mois / trimestre /
  année, par type, export).
- Tables : `postes_budgetaires`, `budgets`, `depenses`, `caisse_mouvements`.
- Routes : CRUD postes, budgets, dépenses (soumission / validation),
  caisse, rapports financiers détaillés.
- Écrans : tableau de bord financier, budget, dépenses, caisse, rapports.

## 5. Communication

- Annonces (existant) : par église, diffusion réseau (mère → antennes).
- Demandes de prière : dépôt, suivi, confidentialité (pasteur seul).
- Notifications dans l'appli (existant : canal push), messages internes.
- Tables : `demandes_priere`, `messages_internes`.
- Routes : CRUD demandes de prière, messages.
- Écrans : demandes de prière, messagerie interne simple.

## 6. Suivi pastoral

- Nouveaux convertis : parcours d'intégration (accueil, formation,
  baptême, intégration à une cellule).
- Visites pastorales : planification, compte rendu, suivi.
- Accompagnement : couples, familles, malades, personnes en difficulté.
- Tables : `parcours_nouveaux` (étapes), `visites_pastorales`,
  `accompagnements`.
- Routes : CRUD parcours, visites, accompagnements.
- Écrans : liste des nouveaux convertis avec leur étape, visites,
  accompagnements.

## 7. Départements et serviteurs

- Départements : chorale, musique, accueil, sécurité, média, intercession,
  nettoyage, enfants, jeunesse, femmes, hommes…
- Serviteurs : affectation à un département, rôle, disponibilité.
- Planning des serviteurs : qui sert à quel culte / événement.
- Tables : `serviteurs` (membre + département + rôle),
  `planning_serviteurs`.
- Routes : CRUD serviteurs, planning.
- Écrans : départements, planning des serviteurs du culte à venir.

## 8. Enfants et jeunesse

- École du dimanche : classes par âge, enseignants, programme.
- Présences enfants, autorisations parentales (sorties).
- Jeunesse : réunions, activités, responsables.
- Tables : `classes_enfants`, `enseignants_classes`,
  `autorisations_sorties`, `activites_jeunesse`.
- Routes : CRUD classes, enseignants, autorisations, activités.
- Écrans : école du dimanche, jeunesse.

## 9. Médias et enseignements

- Prédications : audio / vidéo, orateur, date, culte, série.
- Bible : lecture (Louis Segond), plans de lecture.
- Bibliothèque : livres, prêts.
- Tables : `predications`, `plans_lecture`, `livres`, `prets_livres`.
- Routes : CRUD prédications, plans, livres, prêts.
- Écrans : prédications, bibliothèque.

## 10. Biens et inventaire

- Salles et bâtiments : liste, capacité, réservations.
- Matériel : inventaire (sonorisation, instruments, mobilier…),
  état, responsable, maintenance.
- Tables : `salles`, `reservations_salles`, `materiel`,
  `maintenance_materiel`.
- Routes : CRUD salles, réservations, matériel, maintenance.
- Écrans : salles et réservations, inventaire.

## 11. Rapports et statistiques

- Tableau de bord par église : membres (croissance, nouveaux,
  baptêmes), présences, finances, cultes.
- Consolidation mère : totaux par antenne, comparaisons, exports.
- Tables : vues SQL (`v_stats_eglise`, `v_rapports_consolides` étendue).
- Routes : statistiques globales, exports (CSV).
- Écrans : rapports enrichis, exports.

## 12. Administration

- Rôles et permissions par église (existant : `church_users`).
- Paramètres de l'église : nom, adresse, contacts, logo, comptes
  de paiement (Wave / Orange / MTN).
- Journal d'audit (existant).
- Tables : `eglise_parametres` (ou colonnes sur `churches`).
- Routes : paramètres, gestion des rôles.
- Écrans : réglages enrichis.

## 13. Identité visuelle, présentation et simplicité d'utilisation

Exigence de Bouf (10/11, en cours d'implémentation) : chaque église
— mère comme antenne — doit être immédiatement identifiable, et le
système doit rester simple d'accès pour des églises partout dans le
monde, sans confusion possible entre églises.

- Logo par église : chaque église téléverse son propre logo (PNG/JPG),
  affiché partout (en-tête de l'appli, tableau de bord, carte de membre,
  espace de présentation, reçus). Couleur principale optionnelle par
  église (teinte de l'en-tête).
- Espace de présentation par église : page publique de l'église —
  logo, nom, devise / verset, description, ville et adresse, horaires
  des cultes, contacts, pasteur principal, antennes rattachées.
  Accessible par le code unique de l'église (ex. `GRACE-001`).
- Contexte toujours visible : chaque écran affiche le logo et le nom
  de l'église active ; sélecteur d'église clair pour les utilisateurs
  rattachés à plusieurs églises ; deux codes uniques par église affichés
  dans « Mon église » : code de tutelle permanent (`ESC-0411`, pour rattacher
  une sous-église par `parent_code`) et code fidèle (`ESC-F-0411`, pour inscrire les
  membres dans la bonne église). En plus, la mère peut générer des codes
  de tutelle à usage unique (`ESC-T-XXXXXX`, un seul usage, à l'acceptation
  du rattachement — migration 009). À la saisie, le tiret s'ajoute
  automatiquement : le membre tape seulement les caractères.
- Simplicité : navigation par modules avec icônes et libellés clairs,
  tableau de bord simple, recherche partout, parcours guidé à
  l'inscription (existant, 4 étapes), mode démo (existant).
- Mondial : devise paramétrable par église (FCFA, EUR, USD…),
  fuseau horaire par église, français (autres langues en V2).
- Tables : colonnes `logo_url`, `couleur_principale`, `devise`,
  `fuseau_horaire`, `description`, `horaires_cultes` sur `churches`
  (ou table `eglise_profil`) ; stockage des logos côté serveur.
- Routes : `POST /eglises/:id/logo` (téléversement, image uniquement,
  taille limitée), `GET /eglises/:code/presentation` (profil public),
  `PATCH /eglises/:id/profil` (description, horaires, contacts, devise).
- Écrans : « Mon église » (profil + logo + présentation), en-tête
  avec logo sur tous les écrans, sélecteur d'église.

## 14. Paiements par pays et clés API de chaque église

Exigence de Bouf (10/11) : chaque église utilise les moyens de
paiement de son pays, et peut ajouter elle-même ses identifiants API
de paiement directement dans son espace — sans que la plateforme
(ni Phoenix, ni Muse, ni un administrateur) puisse les voir. Le
serveur les récupère seulement au moment d'exécuter un paiement.

- Catalogue par pays : Côte d'Ivoire (Wave, Orange Money, MTN MoMo),
  Sénégal (Wave, Orange), Kenya (M-Pesa), international (PayPal,
  Stripe), plus virement bancaire et espèces partout. Catalogue
  extensible : ajouter un fournisseur = ajouter une entrée + un
  adaptateur, sans toucher aux autres.
- Configuration par église : dans « Mon église → Paiements », l'admin
  choisit son pays, active ses moyens, et saisit ses identifiants
  (clé API, secret, identifiant marchand — selon le fournisseur).
- Secrets protégés : identifiants chiffrés en base (AES-256-GCM, clé
  serveur en variable d'environnement, KMS plus tard) ; l'API ne les
  renvoie jamais (lecture masquée seulement, ex. `••••1234`) ; jamais
  dans les journaux ; seuls les admins de l'église peuvent les
  saisir, modifier ou supprimer ; journal d'audit sans les valeurs.
- Exécution côté serveur uniquement : quand un don ou un paiement est
  lancé, le serveur déchiffre l'identifiant en mémoire, appelle
  l'API du fournisseur, puis l'oublie. L'application mobile ne voit
  jamais les clés. Bouton « Tester la connexion » (succès / échec
  seulement, sans exposer la clé).
- Limite honnête : le serveur doit déchiffrer pour exécuter — la
  protection vaut contre toute lecture (plateforme, autres églises,
  base volée), pas contre celui qui contrôle physiquement le serveur.
- Tables : `fournisseurs_paiement` (catalogue : code, pays, nom,
  champs requis), `eglise_paiements` (church_id, fournisseur, actif,
  libellé), `eglise_paiement_secrets` (church_id, fournisseur, blob
  chiffré, empreinte, mis à jour le).
- Routes : `GET /paiements/fournisseurs?pays=XX` (catalogue),
  `GET /eglises/:id/paiements` (config masquée),
  `POST /eglises/:id/paiements` (saisie / mise à jour, admin église),
  `DELETE /eglises/:id/paiements/:fournisseur`,
  `POST /eglises/:id/paiements/:fournisseur/tester`,
  `POST /paiements/executer` (serveur : déchiffre, appelle, enregistre).
- Écrans : « Mon église → Paiements » (pays, moyens actifs, saisie
  masquée, test), don avec le moyen de l'église.


## 15. Mot de passe : réinitialisation et initialisation

- Demande de réinitialisation (`POST /auth/mot-de-passe-oublie`) : même
  réponse que l'e-mail existe ou non (pas d'énumération) ; jeton
  `reinitialisation` (32 octets aléatoires, hash SHA-256 stocké, usage
  unique, 24 h) ; e-mail envoyé si le SMTP est configuré (`SMTP_HOST`,
  `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `APP_URL`), sinon
  `email_envoye: false` et l'admin génère le lien
  (`POST /auth/admin/lien-reinitialisation`). Limite : 5 demandes / heure
  / e-mail. Les tentatives sur les jetons comptent comme des échecs
  (5 échecs → 15 min).
- Réinitialisation (`POST /auth/reinitialiser-mot-de-passe`) et
  initialisation (`POST /auth/initialiser-mot-de-passe`, jeton
  `invitation`, 7 jours) : nouveau mot de passe argon2id (8 caractères
  minimum), jeton marqué utilisé, toutes les sessions invalidées
  (`users.token_version`).
- Invitation par l'admin (`POST /auth/inviter`, `admin_eglise`) : crée le
  compte sans mot de passe (`password_hash` NULL) + appartenance à
  l'église, renvoie le lien d'invitation à transmettre (WhatsApp, SMS).
  Un compte invité ne peut pas se connecter avant l'initialisation.
- Changement de mot de passe (`POST /auth/changer-mot-de-passe`,
  connecté) : vérifie l'ancien, invalide les autres sessions.
- Écrans Flutter : « Mot de passe oublié ? » sur la connexion, écran de
  demande, écran de réinitialisation / initialisation (même écran, mode
  selon le jeton ; sur le web, `?token=` lu dans l'URL ; sur mobile,
  collage du lien ou du jeton), « Changer mon mot de passe » dans les
  Réglages et dans l'accueil fidèle.
- Base : `auth_tokens` (hash SHA-256, type, expiration, usage unique),
  `users.member_id`, `users.token_version`, `password_hash` NULL autorisé
  (migration `003_mot_de_passe_acces_fidele.sql`, reprise dans
  `db/schema.sql`).

## 16. Accès fidèle : un membre se connecte pour suivre son église

- Inscription fidèle (`POST /auth/inscription-fidele`, e-mail + mot de
  passe + matricule) : trouve le membre actif par matricule (ambiguïté
  possible pour les anciens numéros — le matricule était unique par
  église — résolue par l'e-mail concordant, sinon refus explicite ; les
  nouveaux matricules sont uniques dans tout le système et ne croisent
  jamais les codes d'église, fidèles ou de tutelle). Champ optionnel
  `code_fidele` (ESC-F-…) : quand il est fourni, la recherche du membre
  est restreinte à l'église de ce code (code inconnu → refus explicite).
  E-mail concordant avec la fiche membre → liaison immédiate + connexion
  immédiate. Sinon
  → compte créé sans église + demande en attente dans
  `member_link_requests` (« demande envoyée, l'administrateur de ton
  église doit la valider ») ; connexion impossible avant validation.
- Validation par l'admin (`GET /membres/demandes-liaison`,
  `POST /membres/demandes-liaison/:id/valider|refuser`) : valider crée
  l'appartenance (`membre`) + `users.member_id` ; un seul « en attente »
  par membre (index unique partiel).
- Profil (`GET /moi`) : utilisateur + église + rôle + `member_id` +
  matricule. Lectures fidèle (`GET /moi/annonces`, `/moi/cultes`,
  `/moi/presences`, `/moi/contributions`, `/moi/carte`) : rôle `membre`
  seulement, son église, ses propres données — jamais celles d'un autre
  membre, jamais les finances globales. La carte réutilise la fiche
  membre existante (MemberDetailScreen), sans la reconstruire.
- Écrans Flutter : « Je suis membre d’une église » sur la connexion ;
  accueil fidèle (mon église, annonces, cultes à venir, ma carte, mes
  présences, mes contributions, mon profil) ; le menu masque tous les
  écrans d'administration pour le rôle `membre`. Côté admin, section
  « Demandes de liaison » + bouton « Inviter » dans « Mon église ».
- Base : `member_link_requests` (membre, utilisateur, statut, décision),
  `users.member_id` UNIQUE (un compte = un fidèle au plus).

## Ordre d'implémentation

1. Schéma : nouvelles tables dans `db/schema.sql` (sans casser
   l'existant).
2. API : nouvelles routes dans `server/src/routes/`, enregistrées
   dans `server/src/index.ts`, avec les mêmes gardes (auth, rôle,
   `church_id`, audit).
3. Application : modèles, services (API + mode démo), écrans, navigation.
4. Vérifications : `npm install` + `npx tsc --noEmit` (0 erreur),
   `flutter analyze` (0 erreur), `flutter build web` (réussi).
5. Poussée sur `main` par Phoenix (texte uniquement) ; Muse est
   prévenue sur l'issue #1 pour ne pas reconstruire en parallèle.

## Hors périmètre (V2)

- Bible hors ligne complète, camps et retraites, boutique / librairie
  en ligne, diffusion en direct (streaming), application iOS / Android
  publiée sur les stores, paiements récurrents (abonnements).
