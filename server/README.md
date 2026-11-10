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
    "eglise": { "name": "Grâce Divine — Plateau", "city": "Abidjan", "phone": "+2250700000000" },
    "admin": { "full_name": "Axel N.", "email": "admin@gracedivine.ci", "password": "motdepassefort" }
  }'
# → { "token": "...", "user": {...}, "church": { "id": "...", "code": "ESC-XXXXXX", ... }, "rattachement": null }
```

### 2. Se connecter (et choisir son église si on en a plusieurs)

```bash
curl -X POST http://localhost:3000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{ "email": "admin@gracedivine.ci", "password": "motdepassefort" }'
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
  -d '{ "name": "Grâce Divine — Yopougon", "city": "Abidjan" }'
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

## Rôles

| Rôle | Droits dans son église |
| --- | --- |
| `admin_eglise` | Tout (églises, rattachements, membres, finances, rapports, annonces) |
| `tresorier` | Finances (lecture + saisie + confirmation), lecture des membres — **pas de création de membre** |
| `responsable_culte` | Membres (lecture + création), lecture des finances |
| `membre` | Lecture des membres, de l'arbre et des annonces — **pas de finances** |
| `super_admin` | Plateforme (hors périmètre MVP) |

## Limites connues du MVP

- Schéma PostgreSQL non encore exécuté contre une base réelle sur cette
  machine (pas de PostgreSQL ici) : lancer `npm run migrate` contre une vraie
  base avant le premier test HTTP.
- Enregistrement manuel des paiements Mobile Money (référence) ; pas de
  webhook Wave / Orange / MTN (V2).
- JWT sans table de révocation : un jeton reste valide jusqu'à expiration
  (30 min web, 2 h mobile).
