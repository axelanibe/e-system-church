# Mot de passe (réinitialisation + initialisation) et accès fidèle

Demandé par Bouf le 10/11/2026 : il manque (1) la possibilité de réinitialiser son mot de passe et le chemin pour initialiser le mot de passe d'un nouveau compte, (2) la possibilité pour un membre de l'église (un fidèle) de se connecter pour suivre les informations de son église. Tout manquait aussi dans la base de données.

## 1. Base de données — migration 003

Fichier `db/migrations/003_mot_de_passe_acces_fidele.sql`, exécutée par `npm run migrate` dans l'ordre (vérifier que migrate.ts lit le dossier dans l'ordre numérique ; y brancher 003). Reprendre aussi les ajouts dans `db/schema.sql` pour les nouvelles bases.

- **`auth_tokens`** : `id` uuid PK, `user_id` uuid FK users (cascade delete), `token_hash` text NOT NULL (SHA-256 du token brut — jamais le token en clair en base), `type` text NOT NULL (`invitation` | `reinitialisation`), `expires_at` timestamptz NOT NULL, `used_at` timestamptz NULL, `created_at` timestamptz. Index sur `user_id` et `token_hash`.
- **`users.member_id`** : uuid NULL FK members.id, UNIQUE (un compte = un fidèle au plus ; un fidèle = un compte au plus). Permettre `password_hash` NULL : un compte créé par invitation n'a pas de mot de passe tant qu'il n'est pas initialisé.
- **`member_link_requests`** : `id` uuid PK, `member_id` uuid FK members, `user_id` uuid FK users, `status` text (`en_attente` | `valide` | `refuse`), `created_at`, `decided_by` uuid FK users NULL, `decided_at` NULL. Index unique partiel : un seul `en_attente` par membre.

## 2. API — routes (dans `server/src/routes/auth.ts` ou nouveau fichier, enregistrées dans `index.ts`)

### Mot de passe
- `POST /auth/mot-de-passe-oublie { email }` → toujours 200 avec un message générique et `email_envoye: bool` (même réponse si l'email n'existe pas — pas d'énumération). Si l'utilisateur existe : crée un token (`crypto.randomBytes(32)`, hex), hash SHA-256 stocké, type `reinitialisation`, expiration 24 h. Si le SMTP est configuré (variables `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `APP_URL`) → envoie l'email avec le lien `APP_URL/reinitialiser?token=...` et `email_envoye: true`. Sinon `email_envoye: false` (l'admin génère le lien, voir ci-dessous). Limite : 5 demandes / heure / email.
- `POST /auth/reinitialiser-mot-de-passe { token, mot_de_passe }` → vérifie le hash, le type, l'expiration et `used_at` NULL ; nouveau hash argon2id (min 8 caractères) ; marque le token utilisé ; invalide toutes les sessions de l'utilisateur. Erreur 400 générique si le token est invalide ou expiré.
- `POST /auth/inviter` (admin_eglise, authentifié) `{ email, role, member_id? }` → crée l'utilisateur avec `password_hash` NULL + entrée `church_users` + token `invitation` (expiration 7 jours) ; retourne le lien d'invitation à l'admin, qui le transmet (WhatsApp, SMS, etc.). Le token n'est exposé nulle part ailleurs.
- `POST /auth/initialiser-mot-de-passe { token, mot_de_passe }` → comme la réinitialisation, type `invitation` ; définit le mot de passe ; marque le token utilisé.
- `POST /auth/changer-mot-de-passe` (authentifié) `{ ancien, nouveau }` → vérifie l'ancien mot de passe (argon2), définit le nouveau.
- Login existant : refuser si `password_hash` est NULL, avec le message « initialisez votre mot de passe via le lien reçu ».
- Verrouillage : les tentatives sur les tokens comptent comme des échecs (5 échecs → 15 min, comme le login).

### Accès fidèle
- `POST /auth/inscription-fidele { email, mot_de_passe, matricule }` → trouve le membre actif par matricule. Si le membre a déjà un compte → erreur. Si `members.email` est égal à l'email fourni → crée l'utilisateur + `church_users` (rôle `membre`, église du membre) + `users.member_id`, connexion immédiate. Sinon → crée l'utilisateur SANS `church_users` + demande en attente dans `member_link_requests` ; message clair : « demande envoyée, l'administrateur de ton église doit la valider ».
- `POST /membres/demandes-liaison/:id/valider` et `/refuser` (admin_eglise) → valider : crée `church_users` (rôle `membre`) + `users.member_id` ; refuser : statut `refuse`.
- `GET /membres/demandes-liaison` (admin_eglise) → demandes en attente de son église.
- `GET /moi` (authentifié) → profil + église + rôle + `member_id` + matricule.
- Lectures fidèle (rôle `membre`, limitées à SON église et à SES propres données) :
  - `GET /moi/annonces` (annonces de son église), `GET /moi/cultes` (événements à venir), `GET /moi/presences` (les siennes), `GET /moi/contributions` (les siennes), `GET /moi/carte` (sa carte de membre + QR — réutiliser la carte existante de Muse, ne pas la reconstruire).
- Un fidèle ne voit jamais les données d'un autre membre, ni les finances globales, ni les écrans d'administration.

## 3. Flutter

- Écran de connexion : lien « Mot de passe oublié ? » → écran de demande (email) → message de confirmation ; écran de réinitialisation / initialisation (même écran, mode selon le token ; sur le web, lire le token dans le paramètre `?token=` ; sur mobile, champ pour coller le lien ou le token).
- Inscription fidèle : écran « Je suis membre d'une église » (email, mot de passe, matricule) → succès immédiat ou demande en attente, message explicite dans les deux cas.
- Accueil fidèle (rôle `membre`) : mon église (logo, nom, code), mes annonces, cultes à venir, ma carte (QR), mes présences, mes contributions, mon profil. Le menu masque tous les écrans d'administration.
- Côté admin (écran « Mon église ») : section « Demandes de liaison » (liste en attente, valider / refuser) + bouton « Inviter » (crée un compte et affiche le lien d'invitation à copier).
- Aucune donnée inventée : états vides explicites partout.

## 4. Sécurité

- Tokens : 32 octets aléatoires, stockés hashés SHA-256, usage unique, expiration (réinitialisation 24 h, invitation 7 jours).
- Mots de passe : argon2id (déjà utilisé), minimum 8 caractères.
- Pas d'énumération d'emails : réponses identiques que l'email existe ou non.
- Les tokens ne sont jamais renvoyés par l'API, sauf le lien d'invitation au moment de sa création par l'admin.
- SMTP optionnel : sans SMTP, l'envoi d'email est désactivé et l'admin transmet les liens (documenté dans `server/README.md`).

## 5. Vérification

- `npx tsc --noEmit` 0 erreur ; `flutter analyze` propre ; `flutter build web` OK.
- Exemples curl du cycle complet dans `server/README.md` : oubli → réinitialisation → connexion ; invitation → initialisation → connexion ; inscription fidèle → liaison → connexion fidèle.
- Ajouter un résumé comme modules 15-16 dans `docs/fonctionnalites-eglise.md`.
- Ne pas toucher aux tranches de Muse (carte QR, transfert, plateforme, palette) ; ne pas pousser (Phoenix pousse après relecture) ; ne pas modifier `app/android/` ni `.github/`.
