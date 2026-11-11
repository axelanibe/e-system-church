# e-System Church — API (serveur)

API MVP : Fastify + TypeScript + PostgreSQL. Authentification JWT bearer,
argon2id, verrouillage après 5 échecs de connexion (15 min). **Isolation
stricte** : chaque requête est filtrée par la `church_id` de la session.

## Installer

```bash
cd server
npm install
```

Prérequis : Node 20+, PostgreSQL 16.

## Configurer

```bash
cp .env.example .env
# puis remplir .env :
#   DATABASE_URL=postgres://user:password@localhost:5432/esystem
#   JWT_SECRET=<32 caractères minimum, aléatoire>
#   PORT=3000
#   SMTP_HOST / SMTP_PORT / SMTP_USER / SMTP_PASS / SMTP_FROM (optionnels :
#     sans eux, aucun e-mail n'est envoyé et l'admin transmet les liens)
#   APP_URL=http://localhost:8080 (liens ?token=... de l'application web)
```

## Migrations

Applique le schéma de la fondation (`../db/schema.sql`) puis les migrations
numérotées de `../db/migrations/` (s'il y en a) :

```bash
npm run migrate
```

## Démarrer

```bash
npm run dev    # développement (rechargement, tsx)
npm run build && npm start   # production (dist/)
```

Vérifier que le serveur répond :

```bash
curl http://localhost:3000/sante
# {"status":"ok","service":"e-system-church-api","time":"..."}
```

## Tester les routes avec curl

> Remplacer `TOKEN` par le jeton renvoyé par `/auth/login` (ou `/auth/register`).
> Toutes les routes sauf `/auth/*` et `/sante` exigent `Authorization: Bearer TOKEN`.

### 1. Inscrire l'église A comme mère (inscription libre : église créée ACTIVE)

```bash
curl -X POST http://localhost:3000/auth/register \
  -H 'Content-Type: application/json' \
  -d '{
    "eglise": { "name": "<nom de votre église>", "city": "<ville>", "phone": "<téléphone>" },
    "admin": { "full_name": "<votre nom>", "email": "<votre e-mail>", "password": "<mot de passe fort>" }
  }'
# → { "token": "...", "user": {...}, "church": { "id": "...", "code": "ESC-XXXXXX", ... }, "rattachement": null }
```

### 2. Se connecter (et choisir son église si on en a plusieurs)

```bash
curl -X POST http://localhost:3000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{ "email": "<votre e-mail>", "password": "<mot de passe fort>" }'
# → { "token": "...", "church": { "id": "...", "code": "ESC-XXXXXX", "role": "admin_eglise" }, "eglises": [...] }
```

### 3. Voir mon église et mon rôle

```bash
curl http://localhost:3000/moi/eglise -H "Authorization: Bearer TOKEN"
```

### 4. Créer la sous-église de Yopougon (admin de la mère)

```bash
curl -X POST http://localhost:3000/eglises \
  -H "Authorization: Bearer TOKEN" -H 'Content-Type: application/json' \
  -d '{ "name": "<nom de la sous-église>", "city": "<ville>" }'
# → la sous-église, avec son propre code ESC-… ; le créateur en est l'admin initial.
```

### 5. Voir mon arborescence (+ demandes de rattachement en attente)

```bash
curl http://localhost:3000/eglises/arbre -H "Authorization: Bearer TOKEN"
```

### 6. Demander à rejoindre une mère (depuis l'église demanderesse, admin)

```bash
curl -X POST http://localhost:3000/rattachements \
  -H "Authorization: Bearer TOKEN" -H 'Content-Type: application/json' \
  -d '{ "parent_code": "ESC-XXXXXX" }'
# → { "id": "...", "status": "en_attente", ... }
```

### 7. Accepter / refuser une demande (depuis la mère, admin)

```bash
curl -X POST http://localhost:3000/rattachements/<id>/accepter \
  -H "Authorization: Bearer TOKEN"
# ou : .../rattachements/<id>/refuser
# → { "id": "...", "status": "acceptee" }
```

### 8. Ajouter un membre (admin ou responsable de culte — pas le trésorier)

```bash
curl -X POST http://localhost:3000/membres \
  -H "Authorization: Bearer TOKEN" -H 'Content-Type: application/json' \
  -d '{ "full_name": "Awa Koné", "phone": "+2250700000001", "department": "Louange" }'
# → membre créé, matricule généré (M-0001, unique par église).
```

### 9. Lister / chercher des membres

```bash
curl "http://localhost:3000/membres?q=Awa&department=Louange" \
  -H "Authorization: Bearer TOKEN"
```

### 10. Enregistrer une dîme Wave (admin ou trésorier)

```bash
curl -X POST http://localhost:3000/contributions \
  -H "Authorization: Bearer TOKEN" -H 'Content-Type: application/json' \
  -d '{ "type": "dime", "amount_fcfa": 10000, "payment_method": "wave", "payment_ref": "WAVE-123456" }'
# → contribution en_attente.
```

### 11. Confirmer la contribution, puis voir son reçu

```bash
curl -X PATCH http://localhost:3000/contributions/<id>/statut \
  -H "Authorization: Bearer TOKEN" -H 'Content-Type: application/json' \
  -d '{ "status": "confirme" }'

curl http://localhost:3000/contributions/<id> -H "Authorization: Bearer TOKEN"
# → { "recu": { ... } }
```

### 12. Lister les finances + totaux (le rôle « membre » simple est refusé : 403)

```bash
curl "http://localhost:3000/contributions?type=dime&status=confirme" \
  -H "Authorization: Bearer TOKEN"
# → { "contributions": [...], "totaux": { "dime": { "total_fcfa": 10000, "nombre": 1 } } }
```

### 13. Rapport consolidé du réseau (admin de la mère seulement)

```bash
curl http://localhost:3000/rapports/consolide -H "Authorization: Bearer TOKEN"
# → { "eglise": {...}, "propre": {...}, "sous_eglises": [...], "totaux_reseau": {...} }
```

### 14. Publier une annonce diffusée à tout le réseau

```bash
curl -X POST http://localhost:3000/annonces \
  -H "Authorization: Bearer TOKEN" -H 'Content-Type: application/json' \
  -d '{ "title": "Veillée de prière", "body": "Vendredi 19h à Yopougon.", "broadcast": true }'

curl http://localhost:3000/annonces -H "Authorization: Bearer TOKEN"
# → mes annonces + celles diffusées par mes églises mères.
```

### 15. Transférer un membre vers une autre branche (double validation)

Règle : demande par matricule, validation par les deux pasteurs, historique
gardé. L'admin de l'église de départ demande, puis accepte ; l'admin de
l'église d'arrivée accepte ensuite. À la double acceptation, le membre
change d'église et reçoit un nouveau matricule dans l'église d'arrivée ;
l'ancienne branche ne le voit plus. Un refus d'un côté clôt la demande.

```bash
# Depuis l'église de départ (admin), avec le jeton du pasteur de départ :
curl -X POST http://localhost:3000/transferts \
  -H "Authorization: Bearer TOKEN" -H 'Content-Type: application/json' \
  -d '{ "matricule": "M-0001", "eglise_arrivee_code": "ESC-YOP001", "motif": "Déménagement à Yopougon" }'
# → { "id": "...", "status": "en_attente", ... }

# Lister : à traiter par mon église, émises, reçues, historique
curl http://localhost:3000/transferts -H "Authorization: Bearer TOKEN"

# Décider (avec le jeton de l'église concernée) : d'abord le départ, puis l'arrivée
curl -X POST http://localhost:3000/transferts/<id>/accepter -H "Authorization: Bearer TOKEN_DEPART"
curl -X POST http://localhost:3000/transferts/<id>/accepter -H "Authorization: Bearer TOKEN_ARRIVEE"
# → { "id": "...", "status": "accepte", "nouveau_matricule": "M-0004" }

# Refuser (n'importe quel côté, avant la double acceptation) ou annuler (départ seulement, tant que en attente)
curl -X POST http://localhost:3000/transferts/<id>/refuser -H "Authorization: Bearer TOKEN"
curl -X POST http://localhost:3000/transferts/<id>/annuler -H "Authorization: Bearer TOKEN_DEPART"
```

### 16. Finances de la mère en détail (total consolidé + détail par branche)

Règle : admin de l'église mère seulement. Périmètre strict, mon église +
tous ses descendants, récursif (petites-filles comprises, avec leur niveau),
filtré par la `church_id` de la session, jamais une autre mère. Seules les
contributions confirmées comptent. La vue agrégée `/rapports/consolide`
reste pour le tableau de bord ; cette route ajoute le détail, elle ne la
remplace pas. Chaque consultation est journalisée en `audit_logs`
(`rapport.detail_consulte`). La vue `v_rapports_consolides` est récursive
depuis la migration `002_vue_consolidee_recursive.sql` : une petite-fille
compte désormais dans le total de sa grand-mère.

```bash
# Mois en cours (novembre 2026 par défaut si la date serveur est en novembre)
curl "http://localhost:3000/rapports/consolide/detail" -H "Authorization: Bearer TOKEN"
# → { "eglise": {...}, "periode": { "type": "mois", "debut": "2026-11-01", "fin": "2026-12-01", "label": "Novembre 2026" }, "branches": [...], "totaux_reseau": {...} }

# Trimestre et année, ancrés sur novembre 2026
curl "http://localhost:3000/rapports/consolide/detail?periode=trimestre&mois=2026-11" -H "Authorization: Bearer TOKEN"
curl "http://localhost:3000/rapports/consolide/detail?periode=annee&mois=2026-11" -H "Authorization: Bearer TOKEN"
# → chaque branche : niveau (0 = mon église, 1 = sous-église directe,
#   2 = antenne d'une sous-église), totaux par type, entrees_fcfa,
#   depenses_fcfa, solde_fcfa, membres_actifs, et transactions
#   (confirmées, 100 au plus par branche).
# Un trésorier ou un membre simple est refusé : 403.
```

### 17. Chiffres globaux de la plateforme (super_admin seulement)

Règle : `super_admin` seulement. Chiffres globaux seulement, sans détail
nominatif, sans liste de membres, sans gestion des membres au jour le jour.
Chaque consultation est journalisée en `audit_logs`
(`plateforme.chiffres_consultes`). Limite honnête : il n'existe pas encore
de compte super_admin créé par l'API ; un tel compte doit être rattaché
directement en base (ligne `church_users` avec le rôle `super_admin`) avant
le premier appel, l'inscription libre ne crée que des `admin_eglise`.

```bash
curl http://localhost:3000/plateforme/chiffres -H "Authorization: Bearer <redacted>"
# → { "chiffres": { "eglises_meres": 1, "branches": 5, "eglises_total": 6,
#     "membres_actifs": 14, "nombre_contributions": 7,
#     "total_contributions_fcfa": 113000, "depenses_fcfa": 20000 } }
# Un admin_eglise, un trésorier ou un membre simple est refusé : 403.
```

### 18. Mot de passe oublié → réinitialisation → connexion

Règle : la demande renvoie toujours la même réponse, que l'e-mail existe
ou non (pas d'énumération). Si le SMTP est configuré, l'e-mail contient le
lien `APP_URL/reinitialiser?token=...` (valable 24 h) et `email_envoye`
vaut `true` ; sinon `false` et l'admin génère le lien (section 19). Le
jeton est à usage unique ; 5 échecs sur un jeton verrouillent le compte
15 min, comme le login. La réinitialisation invalide toutes les sessions
(`token_version`).

```bash
# Demande (toujours 200, même si l'e-mail n'existe pas)
curl -X POST http://localhost:3000/auth/mot-de-passe-oublie \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@gracedivine.ci"}'
# → { "message": "Si cet e-mail correspond à un compte, ...", "email_envoye": true|false }

# Réinitialisation avec le jeton du lien (8 caractères minimum)
curl -X POST http://localhost:3000/auth/reinitialiser-mot-de-passe \
  -H "Content-Type: application/json" \
  -d '{"token":"<jeton_hex>","mot_de_passe":"nouveau-mot-de-passe"}'
# → { "message": "Mot de passe réinitialisé. Vous pouvez vous connecter." }
# Un jeton invalide ou expiré : 400 { "error": "invalid_token", "message": "Lien invalide ou expiré." }

# Connexion avec le nouveau mot de passe (voir section 2)
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@gracedivine.ci","password":"nouveau-mot-de-passe","channel":"web"}'
```

### 19. Invitation par l'admin → initialisation → connexion

Règle : l'admin de l'église crée le compte sans mot de passe et reçoit le
lien d'invitation (`APP_URL/initialiser?token=...`, valable 7 jours) à
transmettre (WhatsApp, SMS, etc.). Le jeton n'est exposé nulle part
ailleurs. Un compte invité ne peut pas se connecter tant que son mot de
passe n'est pas initialisé (401 « initialisez votre mot de passe via le
lien reçu »). Sans SMTP, l'admin génère aussi les liens de
réinitialisation avec la dernière commande ci-dessous.

```bash
# Inviter (admin, jeton admin) : rôle membre, trésorier, responsable_culte ou admin_eglise
curl -X POST http://localhost:3000/auth/inviter \
  -H "Authorization: Bearer <redacted>" -H "Content-Type: application/json" \
  -d '{"email":"nouveau@membre.ci","role":"membre"}'
# → { "user": {...}, "lien_invitation": "http://localhost:8080/initialiser?token=<jeton_hex>", "expires_at": "..." }

# Initialisation avec le jeton du lien
curl -X POST http://localhost:3000/auth/initialiser-mot-de-passe \
  -H "Content-Type: application/json" \
  -d '{"token":"<jeton_hex>","mot_de_passe":"premier-mot-de-passe"}'
# → { "message": "Mot de passe initialisé. Vous pouvez vous connecter." }

# Changer son mot de passe (connecté) : vérifie l'ancien, invalide les autres sessions
curl -X POST http://localhost:3000/auth/changer-mot-de-passe \
  -H "Authorization: Bearer <redacted>" -H "Content-Type: application/json" \
  -d '{"ancien":"premier-mot-de-passe","nouveau":"mot-de-passe-suivant"}'
# → { "message": "Mot de passe changé. Vos autres sessions ont été déconnectées." }

# Sans SMTP : l'admin génère un lien de réinitialisation pour un compte existant
curl -X POST http://localhost:3000/auth/admin/lien-reinitialisation \
  -H "Authorization: Bearer <redacted>" -H "Content-Type: application/json" \
  -d '{"email":"admin@gracedivine.ci"}'
# → { "lien": "http://localhost:8080/reinitialiser?token=<jeton_hex>", "expires_at": "..." }
```

### 20. Inscription fidèle → liaison → connexion fidèle

Règle : le fidèle s'inscrit avec son e-mail, un mot de passe et son
matricule (carte de membre). Si l'e-mail est celui de sa fiche membre, le
compte est lié immédiatement et la connexion est immédiate. Sinon, une
demande de liaison est créée et l'admin de l'église la valide (ou refuse)
dans « Mon église » ; le fidèle ne peut se connecter qu'après validation.
Le matricule est unique par église, pas global : s'il est ambigu, la
réponse l'indique. Le fidèle (rôle `membre`) ne voit que son église et
ses propres données (`/moi/*`) — jamais les données d'un autre membre,
ni les finances globales.

```bash
# 1. Inscription fidèle (e-mail = celui de la fiche membre → liaison immédiate)
curl -X POST http://localhost:3000/auth/inscription-fidele \
  -H "Content-Type: application/json" \
  -d '{"email":"membre@gracedivine.ci","mot_de_passe":"mot-de-passe-fidele","matricule":"M-0001"}'
# → { "lie": true, "message": "Compte créé et lié à votre fiche membre. Bienvenue !", "token": "...", "user": {...}, "church": {...}, "eglises": [...] }

# 1bis. E-mail différent de la fiche → demande en attente
# → { "lie": false, "demande_id": "...", "message": "Demande envoyée, l'administrateur de ton église doit la valider. ..." }

# 2. L'admin liste les demandes en attente de son église
curl http://localhost:3000/membres/demandes-liaison -H "Authorization: Bearer <redacted>"
# → { "demandes": [{ "id": "...", "matricule": "M-0001", "membre_nom": "...", "user_email": "...", ... }] }

# 3. L'admin valide (ou refuse : .../refuser)
curl -X POST http://localhost:3000/membres/demandes-liaison/<demande_id>/valider -H "Authorization: Bearer <redacted>"
# → { "id": "...", "status": "valide", "message": "Liaison validée : le fidèle peut se connecter." }

# 4. Connexion fidèle, puis lectures /moi/* (jeton du fidèle, rôle membre)
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"membre@gracedivine.ci","password":"mot-de-passe-fidele","channel":"mobile"}'
curl http://localhost:3000/moi -H "Authorization: Bearer <redacted>"
# → { "user": {...,"member_id": "...","matricule": "M-0001"}, "church": {...}, "role": "membre" }
curl http://localhost:3000/moi/annonces -H "Authorization: Bearer <redacted>"
curl http://localhost:3000/moi/cultes -H "Authorization: Bearer <redacted>"
curl http://localhost:3000/moi/presences -H "Authorization: Bearer <redacted>"
curl http://localhost:3000/moi/contributions -H "Authorization: Bearer <redacted>"
curl http://localhost:3000/moi/carte -H "Authorization: Bearer <redacted>"
# → { "member": {...}, "church": {...} } (carte de membre existante)
# Un autre rôle que membre sur /moi/* : 403. Les finances globales restent interdites (403).
```

Recette de test contre une vraie base : lancer PostgreSQL,
`npm run migrate`, créer une mère et une sous-église, enregistrer des
contributions confirmées, rattacher un super_admin en base, puis jouer
l'exemple ci-dessus et vérifier que les chiffres globaux correspondent.

Recette de test contre une vraie base : lancer PostgreSQL,
`npm run migrate`, créer une mère et une sous-église, enregistrer des
contributions confirmées dans les deux églises sur novembre 2026, puis
jouer les exemples ci-dessus et vérifier que les totaux par type, le
solde et les transactions correspondent, et qu'une autre mère ne voit
rien de ce réseau (403 ou 404 selon son rôle).

## Rôles

| Rôle | Droits dans son église |
| --- | --- |
| `admin_eglise` | Tout (églises, rattachements, transferts, membres, finances, rapports, annonces) |
| `tresorier` | Finances (lecture + saisie + confirmation), lecture des membres — **pas de création de membre**, **pas de transfert** |
| `responsable_culte` | Membres (lecture + création), lecture des finances, lecture des transferts — **pas de décision de transfert** |
| `membre` | Lecture des membres, de l'arbre et des annonces — **pas de finances**, **pas de transferts** ; lectures `/moi/*` (son église, ses données, sa carte) |
| `super_admin` | Plateforme : chiffres globaux seulement (`GET /plateforme/chiffres`) — **pas de détail nominatif, pas de gestion des membres** |

## Limites connues du MVP

- Schéma PostgreSQL non encore exécuté contre une base réelle sur cette
  machine (pas de PostgreSQL ici) : lancer `npm run migrate` contre une vraie
  base avant le premier test HTTP. La migration `db/migrations/001_transferts_membre.sql`
  crée la table `transferts_membre` ; le schéma `db/schema.sql` la contient
  aussi pour les nouvelles bases.
- Les routes de transfert n'ont pas été testées contre une vraie base
  PostgreSQL (pas de base sur cette machine) : lancer PostgreSQL,
  `npm run migrate`, puis jouer les exemples curl de la section 15.
- La route de détail consolidé (`GET /rapports/consolide/detail`) n'a pas
  non plus été testée contre une vraie base PostgreSQL : lancer PostgreSQL,
  `npm run migrate`, puis jouer les exemples curl de la section 16. La vue
  est récursive depuis la migration `002_vue_consolidee_recursive.sql`.
- La route de la plateforme (`GET /plateforme/chiffres`) n'a pas non plus
  été testée contre une vraie base PostgreSQL : lancer PostgreSQL,
  `npm run migrate`, rattacher un super_admin en base, puis jouer
  l'exemple curl de la section 17.
- Les routes de mot de passe et d'accès fidèle (sections 18 à 20) n'ont
  pas non plus été testées contre une vraie base PostgreSQL : lancer
  PostgreSQL, `npm run migrate`, puis jouer les exemples curl des
  sections 18, 19 et 20. La migration
  `db/migrations/003_mot_de_passe_acces_fidele.sql` crée `auth_tokens`,
  `users.member_id` et `member_link_requests` ; le schéma `db/schema.sql`
  les contient aussi pour les nouvelles bases. Sans SMTP configuré,
  aucun e-mail n'est envoyé : l'admin transmet les liens (invitation,
  lien de réinitialisation).
- Enregistrement manuel des paiements Mobile Money (référence) ; pas de
  webhook Wave / Orange / MTN (V2).
- Révocation des sessions : un changement de mot de passe invalide les
  jetons émis avant (`users.token_version`, vérifié à chaque requête) ;
  sinon, un jeton reste valide jusqu'à expiration (30 min web, 2 h mobile).
