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
    code             TEXT NOT NULL UNIQUE,          -- ex. ESC-G-2026, code d'invitation
    name             TEXT NOT NULL,                 -- ex. « Grâce Divine — Yopougon »
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

CREATE TABLE rattachements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    parent_church_id UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    status          rattachement_status NOT NULL DEFAULT 'en_attente',
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
    password_hash TEXT NOT NULL,                     -- argon2id
    full_name     TEXT NOT NULL,
    phone         TEXT,
    totp_secret   TEXT,                             -- 2FA, NULL = non activée
    failed_logins INT NOT NULL DEFAULT 0,
    locked_until  TIMESTAMPTZ,
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
    matricule   TEXT NOT NULL,                      -- unique PAR église, pas global
    full_name   TEXT NOT NULL,
    phone       TEXT,
    email       TEXT,
    birth_date  DATE,
    department  TEXT,                              -- ex. Louange, Intercession, Jeunesse
    cell_group  TEXT,                              -- cellule / groupe de maison
    status      member_status NOT NULL DEFAULT 'actif',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id, matricule)
);
CREATE INDEX idx_members_church ON members (church_id);
CREATE INDEX idx_members_name ON members (church_id, full_name);

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
-- Vues consolidées pour l'église mère (agrégats uniquement, jamais le détail
-- nominatif d'une antenne sans autorisation explicite)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_rapports_consolides AS
SELECT
    c.parent_church_id AS eglise_mere_id,
    c.id               AS eglise_id,
    c.name             AS eglise_nom,
    (SELECT count(*) FROM members m WHERE m.church_id = c.id AND m.status = 'actif') AS membres_actifs,
    (SELECT count(*) FROM contributions co
      WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme') AS nombre_contributions,
    (SELECT coalesce(sum(amount_fcfa), 0) FROM contributions co
      WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme') AS total_fcfa
FROM churches c
WHERE c.parent_church_id IS NOT NULL;
