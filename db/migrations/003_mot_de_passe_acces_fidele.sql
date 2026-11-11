-- Migration 003 — mot de passe (réinitialisation + initialisation) et accès fidèle
-- (10 novembre 2026, modules 15-16 de docs/fonctionnalites-eglise.md,
-- spécification docs/mot-de-passe-et-acces-fideles.md).
-- Appliquée par `npm run migrate` (server/src/migrate.ts), dans l'ordre.
-- Miroir des ajouts repris dans db/schema.sql pour les nouvelles bases.
-- Idempotente (IF NOT EXISTS / gardes DO).

-- ---------------------------------------------------------------------------
-- Jetons à usage unique : invitation (7 jours) et réinitialisation (24 h).
-- Seul le hash SHA-256 du jeton est stocké — jamais le jeton en clair.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    type       TEXT NOT NULL CHECK (type IN ('invitation', 'reinitialisation')),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_user ON auth_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_hash ON auth_tokens (token_hash);

-- ---------------------------------------------------------------------------
-- users : lien vers la fiche membre + mot de passe initialisable plus tard
-- + version de jeton (invalidation des sessions au changement de mot de passe).
-- ---------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS member_id UUID
    REFERENCES members (id) ON DELETE SET NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INT NOT NULL DEFAULT 0;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

-- Un compte = un fidèle au plus ; un fidèle = un compte au plus.
-- (Les NULL multiples restent autorisés : la plupart des comptes n'ont pas
-- de fiche membre liée.)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_member_id_unique'
  ) THEN
    ALTER TABLE users ADD CONSTRAINT users_member_id_unique UNIQUE (member_id);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Demandes de liaison compte ↔ fiche membre (inscription fidèle sans
-- e-mail concordant, en attente de validation par l'admin de l'église).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS member_link_requests (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status     TEXT NOT NULL DEFAULT 'en_attente'
               CHECK (status IN ('en_attente', 'valide', 'refuse')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_by UUID REFERENCES users (id) ON DELETE SET NULL,
    decided_at TIMESTAMPTZ
);
-- Un seul « en attente » par membre (une deuxième demande pour le même
-- membre est refusée tant que la première n'est pas décidée).
CREATE UNIQUE INDEX IF NOT EXISTS idx_link_requests_pending_unique
    ON member_link_requests (member_id) WHERE status = 'en_attente';
CREATE INDEX IF NOT EXISTS idx_link_requests_user ON member_link_requests (user_id);
CREATE INDEX IF NOT EXISTS idx_link_requests_member ON member_link_requests (member_id);
