-- e-System Church — schéma PostgreSQL (fondation, MVP phase 1)
-- PostgreSQL 16. Appliquer avec : psql "$DATABASE_URL" -f db/schema.sql
-- Règle d'or : TOUTES les requêtes applicatives sont filtrées par church_id
-- (la church de la session). Jamais de lecture inter-églises, sauf les
-- agrégats explicites autorisés pour l'église mère (v_rapports_consolides).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Églises : arborescence mère / sous-églises (auto-référence)
-- ---------------------------------------------------------------------------
CREATE TYPE church_status AS ENUM ('en_attente', 'active', 'suspendue');

CREATE TABLE churches (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code             TEXT NOT NULL UNIQUE,          -- ex. ESC-0411, code d'invitation (tutelle)
    code_fidele      TEXT NOT NULL UNIQUE,          -- ex. ESC-F-0411, code fidèle (inscription des membres)
    name             TEXT NOT NULL,                 -- nom réel de l'église
    parent_church_id UUID REFERENCES churches (id) ON DELETE RESTRICT,
    city             TEXT,
    country          TEXT NOT NULL DEFAULT 'Côte d’Ivoire',
    address          TEXT,
    phone            TEXT,
    email            TEXT,
    status           church_status NOT NULL DEFAULT 'en_attente',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- une église ne peut pas être sa propre mère
    CONSTRAINT no_self_parent CHECK (parent_church_id IS NULL OR parent_church_id <> id)
);
CREATE INDEX idx_churches_parent ON churches (parent_church_id);
CREATE INDEX idx_churches_status ON churches (status);

-- Demandes de rattachement : une église demande à rejoindre une mère.
CREATE TYPE rattachement_status AS ENUM ('en_attente', 'acceptee', 'refusee');

-- Codes de tutelle à usage unique (migration 009) : la mère génère un code
-- ESC-T-XXXXXX pour une église qui veut se rattacher à elle. À l'acceptation
-- du rattachement le code passe à `utilise`, automatiquement. Le code
-- permanent ESC-… de l'église n'est pas touché. Définie avant
-- `rattachements`, qui y fait référence.
CREATE TYPE code_tutelle_status AS ENUM ('actif', 'utilise', 'annule');

CREATE TABLE codes_tutelle (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    code       TEXT NOT NULL UNIQUE,
    status     code_tutelle_status NOT NULL DEFAULT 'actif',
    used_by    UUID REFERENCES churches (id) ON DELETE SET NULL,
    used_at    TIMESTAMPTZ,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT code_tutelle_format CHECK (code ~ '^ESC-T-[A-Z0-9]{6}$')
);
CREATE INDEX idx_codes_tutelle_church ON codes_tutelle (church_id);
CREATE INDEX idx_codes_tutelle_code ON codes_tutelle (code);

CREATE TABLE rattachements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    parent_church_id UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    status          rattachement_status NOT NULL DEFAULT 'en_attente',
    code_tutelle_id UUID REFERENCES codes_tutelle (id) ON DELETE SET NULL,
    decided_by      UUID,                            -- rempli à la décision (voir users)
    decided_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT no_self_rattachement CHECK (church_id <> parent_church_id)
);

-- ---------------------------------------------------------------------------
-- Utilisateurs et rôles (un utilisateur peut appartenir à plusieurs églises,
-- avec un rôle différent dans chacune)
-- ---------------------------------------------------------------------------
CREATE TYPE user_role AS ENUM (
    'super_admin',        -- plateforme e-System Church
    'admin_eglise',       -- admin de sa propre église (mère ou sous-église)
    'tresorier',          -- finances de son église
    'responsable_culte',  -- cultes et présences de son église
    'membre'              -- membre simple
);

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT,                             -- argon2id, NULL tant que le mot
                                                    -- de passe n'est pas initialisé
                                                    -- (compte créé par invitation)
    full_name     TEXT NOT NULL,
    phone         TEXT,
    member_id     UUID,                             -- fiche membre liée (modules 15-16),
                                                    -- FK posée après la table members
    totp_secret   TEXT,                             -- 2FA, NULL = non activée
    failed_logins INT NOT NULL DEFAULT 0,
    locked_until  TIMESTAMPTZ,
    token_version INT NOT NULL DEFAULT 0,           -- invalidations de sessions :
                                                    -- +1 à chaque changement de mot
                                                    -- de passe (jetons plus anciens refusés)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE church_users (
    user_id   UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    church_id UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    role      user_role NOT NULL DEFAULT 'membre',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, church_id)
);
CREATE INDEX idx_church_users_church ON church_users (church_id);

-- ---------------------------------------------------------------------------
-- Membres d'une église (distincts des comptes utilisateurs : un membre peut
-- ne pas avoir de compte ; la carte QR identifie le membre)
-- ---------------------------------------------------------------------------
CREATE TYPE member_status AS ENUM ('actif', 'nouveau_converti', 'inactif');

CREATE TABLE members (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    user_id     UUID REFERENCES users (id) ON DELETE SET NULL,
    matricule   TEXT NOT NULL,                      -- unique dans tout le système (nouveaux numéros)
    full_name   TEXT NOT NULL,
    phone       TEXT,
    email       TEXT,
    birth_date  DATE,
    department  TEXT,                              -- ex. Louange, Intercession, Jeunesse
    fonction    TEXT,                              -- ex. Pasteur, Chantre… ; NULL = « Aucun »
    poste       TEXT,                              -- ex. Directeur de département, Collaborateur…
    cell_group  TEXT,                              -- cellule / groupe de maison
    status      member_status NOT NULL DEFAULT 'actif',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, matricule)
);
CREATE INDEX idx_members_church ON members (church_id);
CREATE INDEX idx_members_name ON members (church_id, full_name);

-- Lien compte ↔ fiche membre (modules 15-16) : la FK ne peut être posée
-- qu'ici, la table members étant définie après users. Un compte = un
-- fidèle au plus ; un fidèle = un compte au plus (les NULL restent libres).
ALTER TABLE users ADD CONSTRAINT fk_users_member
  FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE SET NULL;
ALTER TABLE users ADD CONSTRAINT users_member_id_unique UNIQUE (member_id);

-- ---------------------------------------------------------------------------
-- Mot de passe et accès fidèle (modules 15-16) : jetons à usage unique et
-- demandes de liaison compte ↔ fiche membre. Miroir de la migration 003.
-- ---------------------------------------------------------------------------
CREATE TABLE auth_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,                       -- SHA-256 du jeton brut,
                                                    -- jamais le jeton en clair
    type       TEXT NOT NULL CHECK (type IN ('invitation', 'reinitialisation')),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_auth_tokens_user ON auth_tokens (user_id);
CREATE INDEX idx_auth_tokens_hash ON auth_tokens (token_hash);

CREATE TABLE member_link_requests (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status     TEXT NOT NULL DEFAULT 'en_attente'
               CHECK (status IN ('en_attente', 'valide', 'refuse')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_by UUID REFERENCES users (id) ON DELETE SET NULL,
    decided_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_link_requests_pending_unique
    ON member_link_requests (member_id) WHERE status = 'en_attente';
CREATE INDEX idx_link_requests_user ON member_link_requests (user_id);
CREATE INDEX idx_link_requests_member ON member_link_requests (member_id);

-- ---------------------------------------------------------------------------
-- Finances : dîmes, offrandes, dons, dépenses (par église, jamais globales)
-- ---------------------------------------------------------------------------
CREATE TYPE contribution_type AS ENUM ('dime', 'offrande', 'don', 'depense');
CREATE TYPE payment_method AS ENUM ('wave', 'orange_money', 'mtn_momo', 'especes', 'virement');
CREATE TYPE contribution_status AS ENUM ('en_attente', 'confirme', 'annule');

CREATE TABLE contributions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id      UUID REFERENCES members (id) ON DELETE SET NULL,
    type           contribution_type NOT NULL,
    amount_fcfa    INT NOT NULL CHECK (amount_fcfa > 0),
    payment_method payment_method NOT NULL,
    payment_ref    TEXT,                           -- référence Wave / Orange / MTN
    status         contribution_status NOT NULL DEFAULT 'en_attente',
    received_by    UUID REFERENCES users (id) ON DELETE SET NULL,
    note           TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_contributions_church ON contributions (church_id, created_at);
CREATE INDEX idx_contributions_type ON contributions (church_id, type, created_at);

-- Campagnes de collecte (US2, migration 007) : objectif FCFA strictement
-- positif, période, statut brouillon, active ou cloturee. Le total collecté
-- est la somme des contributions confirmées affectées, calculée à la lecture.
CREATE TABLE IF NOT EXISTS campagnes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom             TEXT NOT NULL,
    objectif_fcfa   INT NOT NULL CHECK (objectif_fcfa > 0),
    date_debut      DATE NOT NULL,
    date_fin        DATE NOT NULL,
    statut          TEXT NOT NULL DEFAULT 'brouillon'
                    CHECK (statut IN ('brouillon', 'active', 'cloturee')),
    visible_membres BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (date_fin > date_debut)
);
CREATE INDEX IF NOT EXISTS idx_campagnes_church ON campagnes (church_id, statut);
ALTER TABLE contributions
  ADD COLUMN IF NOT EXISTS campagne_id UUID REFERENCES campagnes (id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_contributions_campagne ON contributions (campagne_id);

-- ---------------------------------------------------------------------------
-- Cultes, événements et présences (scan QR par matricule)
-- ---------------------------------------------------------------------------
CREATE TABLE events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    title       TEXT NOT NULL,                      -- ex. « Culte du dimanche »
    description TEXT,
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ,
    location    TEXT,
    created_by  UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_events_church ON events (church_id, starts_at);

CREATE TYPE attendance_status AS ENUM ('present', 'absent', 'excuse');

CREATE TABLE attendances (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    status      attendance_status NOT NULL DEFAULT 'present',
    scanned_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    scanned_by  UUID REFERENCES users (id) ON DELETE SET NULL,
    UNIQUE (event_id, member_id)
);

-- ---------------------------------------------------------------------------
-- Annonces : de l'église mère vers tout son réseau (ou d'une église à ses membres)
-- ---------------------------------------------------------------------------
CREATE TABLE announcements (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    broadcast   BOOLEAN NOT NULL DEFAULT FALSE,     -- TRUE = diffusée aux sous-églises
    created_by  UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_announcements_church ON announcements (church_id, created_at);

-- ---------------------------------------------------------------------------
-- Journal d'audit : qui a fait quoi, dans quelle église (lecture seule)
-- ---------------------------------------------------------------------------
CREATE TABLE audit_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID REFERENCES churches (id) ON DELETE SET NULL,
    user_id     UUID REFERENCES users (id) ON DELETE SET NULL,
    action      TEXT NOT NULL,                      -- ex. 'contribution.confirmee'
    details     JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_church ON audit_logs (church_id, created_at);

-- ---------------------------------------------------------------------------
-- Attestations annuelles de dons (US3) : une attestation émise est figée,
-- son contenu est copié en JSONB à l'émission. Voir db/migrations/
-- 008_attestations.sql (même définition, pour les bases existantes).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attestations (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id      UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    annee          INT NOT NULL CHECK (annee BETWEEN 2000 AND 2100),
    numero         TEXT NOT NULL,
    total_fcfa     INT NOT NULL CHECK (total_fcfa > 0),
    nb_dons        INT NOT NULL CHECK (nb_dons > 0),
    statut         TEXT NOT NULL DEFAULT 'emise' CHECK (statut IN ('emise', 'annulee')),
    remplace_id    UUID REFERENCES attestations (id) ON DELETE SET NULL,
    date_emission  TIMESTAMPTZ NOT NULL DEFAULT now(),
    contenu        JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, annee, numero)
);
CREATE INDEX IF NOT EXISTS idx_attestations_church_annee
    ON attestations (church_id, annee);
CREATE INDEX IF NOT EXISTS idx_attestations_member
    ON attestations (member_id, annee);
CREATE UNIQUE INDEX IF NOT EXISTS idx_attestations_une_emise
    ON attestations (church_id, member_id, annee) WHERE statut = 'emise';

-- ---------------------------------------------------------------------------
-- Vues consolidées pour l'église mère (agrégats uniquement, jamais le détail
-- nominatif d'une antenne sans autorisation explicite). Récursive depuis le
-- 10 novembre 2026 (tranche Plateforme) : une mère voit tous ses
-- descendants, petites-filles comprises, avec leur niveau (1 = sous-église
-- directe, 2 = antenne d'une sous-église, …). eglise_mere_id est la racine
-- du réseau, pas la mère directe.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_rapports_consolides AS
WITH RECURSIVE descendants AS (
    SELECT id AS eglise_id, id AS racine_id, 0 AS niveau
      FROM churches
     UNION ALL
    SELECT c.id, d.racine_id, d.niveau + 1
      FROM churches c
      JOIN descendants d ON c.parent_church_id = d.eglise_id
)
SELECT
    d.racine_id AS eglise_mere_id,
    c.id        AS eglise_id,
    c.name      AS eglise_nom,
    d.niveau    AS niveau,
    (SELECT count(*)::int FROM members m WHERE m.church_id = c.id AND m.status = 'actif') AS membres_actifs,
    (SELECT count(*)::int FROM contributions co
      WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme') AS nombre_contributions,
    (SELECT coalesce(sum(amount_fcfa), 0)::int FROM contributions co
      WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme') AS total_fcfa
FROM churches c
JOIN descendants d ON d.eglise_id = c.id
WHERE d.racine_id <> c.id;

-- ===========================================================================
-- EXTENSION — « Toutes les fonctionnalités d'une église » (10 novembre 2026)
-- Modules 1 à 12 de docs/fonctionnalites-eglise.md. Règles inchangées :
-- isolation stricte par church_id, rôles par église (voir user_role),
-- audit. Les rôles de la spécification se mappent ainsi sur user_role :
-- pasteur / secrétaire → admin_eglise ; responsable → responsable_culte.
-- Les statuts riches d'un membre (sympathisant, en formation, suspendu,
-- parti) vivent dans membre_statuts (historique) ; members.status garde
-- l'enum d'origine (actif / nouveau_converti / inactif) pour ne pas
-- casser le code existant.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Module 1 — Membres (compléter) : familles, statuts, baptêmes, liens,
-- départements, cellules et affectations.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS familles (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom              TEXT NOT NULL,
    chef_famille_id  UUID REFERENCES members (id) ON DELETE SET NULL,
    adresse          TEXT,
    telephone        TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_familles_church ON familles (church_id);

CREATE TABLE IF NOT EXISTS membre_statuts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id     UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    statut        TEXT NOT NULL CHECK (statut IN
                    ('membre','sympathisant','nouveau_converti','en_formation','suspendu','parti')),
    ancien_statut TEXT,
    motif         TEXT,
    change_par    UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_membre_statuts_church ON membre_statuts (church_id, member_id, created_at);

CREATE TABLE IF NOT EXISTS baptemes (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id        UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    date_bapteme     DATE NOT NULL,
    lieu             TEXT,
    pasteur          TEXT,
    certificat_numero TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (member_id)
);
CREATE INDEX IF NOT EXISTS idx_baptemes_church ON baptemes (church_id);

CREATE TABLE IF NOT EXISTS liens_parent_enfant (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id         UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    parent_member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    enfant_member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    lien              TEXT NOT NULL CHECK (lien IN ('pere','mere','tuteur','autre')),
    statut            TEXT NOT NULL DEFAULT 'en_attente'
                      CHECK (statut IN ('en_attente','valide','refuse')),
    valide_par        UUID REFERENCES users (id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (parent_member_id, enfant_member_id),
    CONSTRAINT no_self_lien CHECK (parent_member_id <> enfant_member_id)
);
CREATE INDEX IF NOT EXISTS idx_liens_church ON liens_parent_enfant (church_id, enfant_member_id);

CREATE TABLE IF NOT EXISTS departements (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id             UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom                   TEXT NOT NULL,
    description           TEXT,
    responsable_member_id UUID REFERENCES members (id) ON DELETE SET NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_departements_church ON departements (church_id);

-- Catalogue des fonctions par église (migration 006 ; mêmes listes par
-- défaut que les départements, amorcées à la création de l'église).
CREATE TABLE IF NOT EXISTS fonctions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom        TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_fonctions_church ON fonctions (church_id);

-- Catalogue des postes par église (migration 006 ; postes d'exemple du
-- document d'architecture, §4 : fonction, département et poste sont trois
-- notions séparées, stockées séparément).
CREATE TABLE IF NOT EXISTS postes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom        TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_postes_org_church ON postes (church_id);

CREATE TABLE IF NOT EXISTS cellules (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id             UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom                   TEXT NOT NULL,
    quartier              TEXT,
    responsable_member_id UUID REFERENCES members (id) ON DELETE SET NULL,
    jour_reunion          TEXT,
    heure_reunion         TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cellules_church ON cellules (church_id);

CREATE TABLE IF NOT EXISTS membre_departements (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id      UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    departement_id UUID NOT NULL REFERENCES departements (id) ON DELETE CASCADE,
    role           TEXT NOT NULL DEFAULT 'membre',
    date_debut     DATE,
    date_fin       DATE,
    statut         TEXT NOT NULL DEFAULT 'active' CHECK (statut IN ('active', 'terminee')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (member_id, departement_id)
);
CREATE INDEX IF NOT EXISTS idx_membre_departements_church ON membre_departements (church_id, departement_id);

CREATE TABLE IF NOT EXISTS membre_cellules (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    cellule_id  UUID NOT NULL REFERENCES cellules (id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (member_id, cellule_id)
);
CREATE INDEX IF NOT EXISTS idx_membre_cellules_church ON membre_cellules (church_id, cellule_id);

-- ---------------------------------------------------------------------------
-- Module 2 — Cultes et programmes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS culte_types (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom            TEXT NOT NULL,
    jour_semaine   INT CHECK (jour_semaine BETWEEN 0 AND 6),
    heure_debut    TEXT,
    duree_minutes  INT CHECK (duree_minutes > 0),
    lieu           TEXT,
    actif          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_culte_types_church ON culte_types (church_id);

CREATE TABLE IF NOT EXISTS cultes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    culte_type_id UUID REFERENCES culte_types (id) ON DELETE SET NULL,
    titre         TEXT NOT NULL,
    date_heure    TIMESTAMPTZ NOT NULL,
    lieu          TEXT,
    orateur       TEXT,
    theme         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cultes_church ON cultes (church_id, date_heure);

CREATE TABLE IF NOT EXISTS ordre_culte_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    culte_id      UUID NOT NULL REFERENCES cultes (id) ON DELETE CASCADE,
    ordre         INT NOT NULL DEFAULT 0,
    titre         TEXT NOT NULL,
    description   TEXT,
    intervenant   TEXT,
    duree_minutes INT CHECK (duree_minutes > 0),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ordre_culte_church ON ordre_culte_items (church_id, culte_id, ordre);

CREATE TABLE IF NOT EXISTS evenements_speciaux (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    type        TEXT NOT NULL CHECK (type IN
                  ('mariage','bapteme_eau','dedicace_enfant','funerailles','conference','campagne','jeune','autre')),
    titre       TEXT NOT NULL,
    description TEXT,
    date_debut  TIMESTAMPTZ NOT NULL,
    date_fin    TIMESTAMPTZ,
    lieu        TEXT,
    responsable TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_evenements_speciaux_church ON evenements_speciaux (church_id, date_debut);

-- ---------------------------------------------------------------------------
-- Module 3 — Présences (pointage aux cultes et réunions ; complète
-- attendances qui reste pour les événements génériques)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS presences (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    event_id   UUID REFERENCES events (id) ON DELETE CASCADE,
    culte_id   UUID REFERENCES cultes (id) ON DELETE CASCADE,
    member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    statut     attendance_status NOT NULL DEFAULT 'present',
    mode       TEXT NOT NULL DEFAULT 'manuel'
               CHECK (mode IN ('manuel','liste','scan_qr')),
    pointe_par UUID REFERENCES users (id) ON DELETE SET NULL,
    pointe_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT presence_cible CHECK (event_id IS NOT NULL OR culte_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_presences_church ON presences (church_id, pointe_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_presences_event_unique
    ON presences (member_id, event_id) WHERE event_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_presences_culte_unique
    ON presences (member_id, culte_id) WHERE culte_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Module 4 — Finances (compléter) : postes, budgets, dépenses, caisse
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS postes_budgetaires (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom         TEXT NOT NULL,
    categorie   TEXT NOT NULL CHECK (categorie IN ('recette','depense')),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_postes_church ON postes_budgetaires (church_id);

CREATE TABLE IF NOT EXISTS budgets (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    poste_id       UUID NOT NULL REFERENCES postes_budgetaires (id) ON DELETE CASCADE,
    annee          INT NOT NULL CHECK (annee BETWEEN 2000 AND 2100),
    montant_prevu  INT NOT NULL CHECK (montant_prevu >= 0),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, poste_id, annee)
);
CREATE INDEX IF NOT EXISTS idx_budgets_church ON budgets (church_id, annee);

CREATE TABLE IF NOT EXISTS depenses (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    poste_id       UUID REFERENCES postes_budgetaires (id) ON DELETE SET NULL,
    montant_fcfa   INT NOT NULL CHECK (montant_fcfa > 0),
    motif          TEXT NOT NULL,
    justificatif_ref TEXT,
    statut         TEXT NOT NULL DEFAULT 'soumise'
                   CHECK (statut IN ('soumise','validee_tresorier','validee_pasteur','payee','refusee')),
    demande_par    UUID REFERENCES users (id) ON DELETE SET NULL,
    valide_par     UUID REFERENCES users (id) ON DELETE SET NULL,
    date_depense   DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_depenses_church ON depenses (church_id, date_depense);

CREATE TABLE IF NOT EXISTS caisse_mouvements (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    type         TEXT NOT NULL CHECK (type IN ('entree','sortie')),
    montant_fcfa INT NOT NULL CHECK (montant_fcfa > 0),
    motif        TEXT NOT NULL,
    reference    TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_caisse_church ON caisse_mouvements (church_id, created_at);

-- ---------------------------------------------------------------------------
-- Module 5 — Communication : demandes de prière, messages internes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS demandes_priere (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id     UUID REFERENCES members (id) ON DELETE SET NULL,
    demandeur_nom TEXT,
    sujet         TEXT NOT NULL,
    details       TEXT,
    confidentiel  BOOLEAN NOT NULL DEFAULT FALSE,
    statut        TEXT NOT NULL DEFAULT 'nouvelle'
                  CHECK (statut IN ('nouvelle','en_cours','terminee')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prieres_church ON demandes_priere (church_id, created_at);

CREATE TABLE IF NOT EXISTS messages_internes (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    expediteur_id    UUID REFERENCES users (id) ON DELETE SET NULL,
    destinataire_id  UUID REFERENCES users (id) ON DELETE SET NULL,
    sujet            TEXT NOT NULL,
    corps            TEXT NOT NULL,
    lu               BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_church ON messages_internes (church_id, destinataire_id, created_at);

-- ---------------------------------------------------------------------------
-- Module 6 — Suivi pastoral : parcours des nouveaux convertis, visites,
-- accompagnements
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS parcours_nouveaux (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    etape       TEXT NOT NULL DEFAULT 'accueil'
                CHECK (etape IN ('accueil','formation','bapteme','integration_cellule','integre')),
    date_etape  DATE,
    note        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (member_id)
);
CREATE INDEX IF NOT EXISTS idx_parcours_church ON parcours_nouveaux (church_id, etape);

CREATE TABLE IF NOT EXISTS visites_pastorales (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id    UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    visiteur_id  UUID REFERENCES users (id) ON DELETE SET NULL,
    date_visite  TIMESTAMPTZ NOT NULL,
    motif        TEXT,
    compte_rendu TEXT,
    statut       TEXT NOT NULL DEFAULT 'planifiee'
                 CHECK (statut IN ('planifiee','realisee','annulee')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_visites_church ON visites_pastorales (church_id, date_visite);

CREATE TABLE IF NOT EXISTS accompagnements (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id        UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    type             TEXT NOT NULL CHECK (type IN ('couple','famille','malade','difficulte','autre')),
    accompagnateur_id UUID REFERENCES users (id) ON DELETE SET NULL,
    description      TEXT,
    statut           TEXT NOT NULL DEFAULT 'en_cours' CHECK (statut IN ('en_cours','termine')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_accompagnements_church ON accompagnements (church_id, statut);

-- ---------------------------------------------------------------------------
-- Module 7 — Départements et serviteurs (départements : voir module 1)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS serviteurs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id      UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    departement_id UUID NOT NULL REFERENCES departements (id) ON DELETE CASCADE,
    role           TEXT NOT NULL DEFAULT 'serviteur',
    disponibilite  TEXT,
    actif          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (member_id, departement_id)
);
CREATE INDEX IF NOT EXISTS idx_serviteurs_church ON serviteurs (church_id, departement_id);

CREATE TABLE IF NOT EXISTS planning_serviteurs (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    serviteur_id UUID NOT NULL REFERENCES serviteurs (id) ON DELETE CASCADE,
    culte_id     UUID REFERENCES cultes (id) ON DELETE CASCADE,
    event_id     UUID REFERENCES events (id) ON DELETE CASCADE,
    date_service DATE NOT NULL,
    role_service TEXT,
    statut       TEXT NOT NULL DEFAULT 'prevu'
                 CHECK (statut IN ('prevu','confirme','absent')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_planning_church ON planning_serviteurs (church_id, date_service);

-- ---------------------------------------------------------------------------
-- Module 8 — Enfants et jeunesse
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS classes_enfants (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom        TEXT NOT NULL,
    age_min    INT CHECK (age_min >= 0),
    age_max    INT CHECK (age_max >= age_min),
    salle      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_classes_church ON classes_enfants (church_id);

CREATE TABLE IF NOT EXISTS enseignants_classes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    classe_id  UUID NOT NULL REFERENCES classes_enfants (id) ON DELETE CASCADE,
    member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    role       TEXT NOT NULL DEFAULT 'enseignant' CHECK (role IN ('enseignant','assistant')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (classe_id, member_id)
);
CREATE INDEX IF NOT EXISTS idx_enseignants_church ON enseignants_classes (church_id, classe_id);

CREATE TABLE IF NOT EXISTS autorisations_sorties (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id         UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    enfant_member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    parent_member_id  UUID REFERENCES members (id) ON DELETE SET NULL,
    activite          TEXT NOT NULL,
    date_sortie       DATE NOT NULL,
    statut            TEXT NOT NULL DEFAULT 'en_attente'
                      CHECK (statut IN ('en_attente','autorisee','refusee')),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_autorisations_church ON autorisations_sorties (church_id, date_sortie);

CREATE TABLE IF NOT EXISTS activites_jeunesse (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id             UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre                 TEXT NOT NULL,
    description           TEXT,
    date_activite         TIMESTAMPTZ NOT NULL,
    lieu                  TEXT,
    responsable_member_id UUID REFERENCES members (id) ON DELETE SET NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_activites_jeunesse_church ON activites_jeunesse (church_id, date_activite);

-- ---------------------------------------------------------------------------
-- Module 9 — Médias et enseignements
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS predications (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre          TEXT NOT NULL,
    orateur        TEXT,
    date_predication DATE NOT NULL,
    culte_id       UUID REFERENCES cultes (id) ON DELETE SET NULL,
    serie          TEXT,
    url_audio      TEXT,
    url_video      TEXT,
    duree_minutes  INT CHECK (duree_minutes > 0),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_predications_church ON predications (church_id, date_predication);

CREATE TABLE IF NOT EXISTS plans_lecture (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id    UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom          TEXT NOT NULL,
    description  TEXT,
    duree_jours  INT CHECK (duree_jours > 0),
    actif        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_plans_church ON plans_lecture (church_id);

CREATE TABLE IF NOT EXISTS livres (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre       TEXT NOT NULL,
    auteur      TEXT,
    categorie   TEXT,
    isbn        TEXT,
    exemplaires INT NOT NULL DEFAULT 1 CHECK (exemplaires >= 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_livres_church ON livres (church_id);

CREATE TABLE IF NOT EXISTS prets_livres (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id           UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    livre_id            UUID NOT NULL REFERENCES livres (id) ON DELETE CASCADE,
    member_id           UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    date_pret           DATE NOT NULL DEFAULT CURRENT_DATE,
    date_retour_prevue  DATE,
    date_retour         DATE,
    statut              TEXT NOT NULL DEFAULT 'en_cours'
                        CHECK (statut IN ('en_cours','rendu','en_retard')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prets_church ON prets_livres (church_id, statut);

-- ---------------------------------------------------------------------------
-- Module 10 — Biens et inventaire
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS salles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom         TEXT NOT NULL,
    capacite    INT CHECK (capacite >= 0),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, nom)
);
CREATE INDEX IF NOT EXISTS idx_salles_church ON salles (church_id);

CREATE TABLE IF NOT EXISTS reservations_salles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    salle_id    UUID NOT NULL REFERENCES salles (id) ON DELETE CASCADE,
    titre       TEXT NOT NULL,
    debut       TIMESTAMPTZ NOT NULL,
    fin         TIMESTAMPTZ NOT NULL,
    reserve_par TEXT,
    statut      TEXT NOT NULL DEFAULT 'confirmee' CHECK (statut IN ('confirmee','annulee')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fin_apres_debut CHECK (fin > debut)
);
CREATE INDEX IF NOT EXISTS idx_reservations_church ON reservations_salles (church_id, debut);

CREATE TABLE IF NOT EXISTS materiel (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id             UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    nom                   TEXT NOT NULL,
    categorie             TEXT,
    quantite              INT NOT NULL DEFAULT 1 CHECK (quantite >= 0),
    etat                  TEXT NOT NULL DEFAULT 'bon'
                          CHECK (etat IN ('bon','a_reparer','hors_service')),
    responsable_member_id UUID REFERENCES members (id) ON DELETE SET NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_materiel_church ON materiel (church_id);

CREATE TABLE IF NOT EXISTS maintenance_materiel (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id     UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    materiel_id   UUID NOT NULL REFERENCES materiel (id) ON DELETE CASCADE,
    date_maintenance DATE NOT NULL DEFAULT CURRENT_DATE,
    description   TEXT NOT NULL,
    cout_fcfa     INT CHECK (cout_fcfa >= 0),
    realise_par   TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_maintenance_church ON maintenance_materiel (church_id, materiel_id);

-- ---------------------------------------------------------------------------
-- Module 11 — Rapports et statistiques : vue par église (agrégats)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stats_eglise AS
SELECT
    c.id AS eglise_id,
    c.name AS eglise_nom,
    (SELECT count(*) FROM members m WHERE m.church_id = c.id AND m.status = 'actif') AS membres_actifs,
    (SELECT count(*) FROM members m WHERE m.church_id = c.id AND m.status = 'nouveau_converti') AS nouveaux_convertis,
    (SELECT count(*) FROM baptemes b WHERE b.church_id = c.id) AS baptemes,
    (SELECT count(*) FROM cultes cu WHERE cu.church_id = c.id
        AND cu.date_heure >= date_trunc('month', now())
        AND cu.date_heure < date_trunc('month', now()) + interval '1 month') AS cultes_mois,
    (SELECT count(*) FROM presences p WHERE p.church_id = c.id
        AND p.statut = 'present'
        AND p.pointe_at >= date_trunc('month', now())) AS presences_mois,
    (SELECT coalesce(sum(amount_fcfa), 0) FROM contributions co
        WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme'
        AND co.created_at >= date_trunc('month', now())) AS recettes_mois_fcfa,
    (SELECT coalesce(sum(amount_fcfa), 0) FROM contributions co
        WHERE co.church_id = c.id AND co.type = 'depense'
        AND co.status = 'confirme'
        AND co.created_at >= date_trunc('month', now())) +
    -- Dépenses du module Budget & caisse (hors refusées) du mois courant :
    -- sans elles, le tableau de bord affichait 0 de dépenses.
    (SELECT coalesce(sum(montant_fcfa), 0) FROM depenses d
        WHERE d.church_id = c.id AND d.statut <> 'refusee'
        AND d.date_depense >= date_trunc('month', now())::date
        AND d.date_depense < (date_trunc('month', now()) + interval '1 month')::date) AS depenses_mois_fcfa
FROM churches c;

-- ---------------------------------------------------------------------------
-- Module 12 — Administration : paramètres de l'église
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS eglise_parametres (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL UNIQUE REFERENCES churches (id) ON DELETE CASCADE,
    adresse         TEXT,
    ville           TEXT,
    telephone       TEXT,
    email           TEXT,
    logo_url        TEXT,
    wave_numero     TEXT,
    orange_numero   TEXT,
    mtn_numero      TEXT,
    devise          TEXT NOT NULL DEFAULT 'FCFA',
    fuseau_horaire  TEXT NOT NULL DEFAULT 'Africa/Abidjan',
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_parametres_church ON eglise_parametres (church_id);

-- ---------------------------------------------------------------------------
-- Module 13 — Identité visuelle, présentation et simplicité d'utilisation :
-- logo, couleur principale, devise et fuseau horaire par église, description
-- et horaires des cultes. ALTER TABLE (et non CREATE) car la table
-- churches existe depuis la fondation ; IF NOT EXISTS = idempotent pour
-- les bases déjà créées.
-- ---------------------------------------------------------------------------
ALTER TABLE churches ADD COLUMN IF NOT EXISTS logo_url TEXT;
ALTER TABLE churches ADD COLUMN IF NOT EXISTS couleur_principale TEXT;
ALTER TABLE churches ADD COLUMN IF NOT EXISTS devise TEXT NOT NULL DEFAULT 'FCFA';
ALTER TABLE churches ADD COLUMN IF NOT EXISTS fuseau_horaire TEXT NOT NULL DEFAULT 'Africa/Abidjan';
ALTER TABLE churches ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE churches ADD COLUMN IF NOT EXISTS horaires_cultes JSONB NOT NULL DEFAULT '[]'::jsonb;

-- ---------------------------------------------------------------------------
-- Module 14 — Paiements par pays et clés API de chaque église.
-- Secrets chiffrés (AES-256-GCM, clé serveur PAYMENT_SECRETS_KEY) : la
-- base ne contient que des blobs + une empreinte SHA-256 (pour détecter un
-- changement sans déchiffrer) ; l'API ne renvoie jamais les valeurs,
-- seulement un aperçu masqué (••••1234) stocké à l'écriture.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fournisseurs_paiement (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          TEXT NOT NULL UNIQUE,
    nom           TEXT NOT NULL,
    pays          TEXT[] NOT NULL DEFAULT '{}',  -- ex. {CI,SN} ; {*} = partout
    type          TEXT NOT NULL CHECK (type IN ('mobile_money','carte','virement','especes')),
    champs_requis JSONB NOT NULL DEFAULT '[]'::jsonb,
    actif         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS eglise_paiements (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    fournisseur_id UUID NOT NULL REFERENCES fournisseurs_paiement (id) ON DELETE CASCADE,
    pays           TEXT NOT NULL,
    libelle        TEXT,
    apercu         TEXT,                          -- ex. ••••1234 (jamais la valeur)
    actif          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, fournisseur_id)
);
CREATE INDEX IF NOT EXISTS idx_eglise_paiements_church ON eglise_paiements (church_id);

CREATE TABLE IF NOT EXISTS eglise_paiement_secrets (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    eglise_paiement_id UUID NOT NULL REFERENCES eglise_paiements (id) ON DELETE CASCADE,
    nom_champ         TEXT NOT NULL,
    valeur_chiffree   TEXT NOT NULL,             -- base64 (AES-256-GCM)
    iv                TEXT NOT NULL,             -- hex, 12 octets
    tag               TEXT NOT NULL,             -- hex (authentification GCM)
    empreinte         TEXT NOT NULL,             -- SHA-256 hex de la valeur claire
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (eglise_paiement_id, nom_champ)
);
CREATE INDEX IF NOT EXISTS idx_paiement_secrets_config ON eglise_paiement_secrets (eglise_paiement_id);

-- Catalogue initial (extensible : ajouter une ligne + un adaptateur).
INSERT INTO fournisseurs_paiement (code, nom, pays, type, champs_requis) VALUES
  ('wave', 'Wave', ARRAY['CI','SN'], 'mobile_money',
   '[{"nom":"api_key","label":"Clé API Wave","secret":true}]'::jsonb),
  ('orange_money', 'Orange Money', ARRAY['CI','SN'], 'mobile_money',
   '[{"nom":"client_id","label":"Client ID","secret":false},{"nom":"client_secret","label":"Client secret","secret":true},{"nom":"merchant_key","label":"Clé marchand","secret":true}]'::jsonb),
  ('mtn_momo', 'MTN MoMo', ARRAY['CI'], 'mobile_money',
   '[{"nom":"subscription_key","label":"Clé d’abonnement","secret":true},{"nom":"api_user","label":"Utilisateur API","secret":false},{"nom":"api_key","label":"Clé API","secret":true}]'::jsonb),
  ('mpesa', 'M-Pesa', ARRAY['KE'], 'mobile_money',
   '[{"nom":"consumer_key","label":"Consumer Key","secret":false},{"nom":"consumer_secret","label":"Consumer Secret","secret":true},{"nom":"shortcode","label":"Shortcode","secret":false},{"nom":"passkey","label":"Passkey","secret":true}]'::jsonb),
  ('paypal', 'PayPal', ARRAY['INTL'], 'carte',
   '[{"nom":"client_id","label":"Client ID","secret":false},{"nom":"client_secret","label":"Client secret","secret":true}]'::jsonb),
  ('stripe', 'Stripe', ARRAY['INTL'], 'carte',
   '[{"nom":"cle_publique","label":"Clé publique","secret":false},{"nom":"cle_secrete","label":"Clé secrète","secret":true}]'::jsonb),
  ('virement', 'Virement bancaire', ARRAY['*'], 'virement', '[]'::jsonb),
  ('especes', 'Espèces', ARRAY['*'], 'especes', '[]'::jsonb)
ON CONFLICT (code) DO NOTHING;

-- ===========================================================================
-- US1 — Modules activables par église (11 novembre 2026)
-- Une ligne par église et par module activable, avec son état. Absence de
-- ligne = module inactif : à la création d'une église, seuls le noyau
-- (membres, finances, rapports) est actif. Le noyau n'est jamais stocké
-- ici, il est toujours actif. Désactiver ne supprime aucune donnée.
-- Chaque église décide seule pour elle-même ; la mère ne force pas ses
-- antennes. Voir server/src/modules.ts pour le catalogue des codes.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS eglise_modules (
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    module     TEXT NOT NULL CHECK (module IN
                 ('annonces','familles','cultes','presences','budget',
                  'prieres','pastoral','serviteurs','enfants','medias',
                  'biens','parametres','mon_eglise')),
    actif      BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (church_id, module)
);
CREATE INDEX IF NOT EXISTS idx_eglise_modules_church ON eglise_modules (church_id);
