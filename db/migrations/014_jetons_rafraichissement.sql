-- Migration 014 — session gardée : jetons de rafraîchissement (11 novembre 2026)
-- Un jeton par appareil : la session dure jusqu'à déconnexion manuelle, le
-- JWT court (30 min web, 2 h mobile) est renouvelé par rotation du jeton.
-- Seul le hash SHA-256 du jeton est stocké, jamais le jeton en clair (même
-- principe que `auth_tokens`, migration 003). Un jeton déjà utilisé est
-- le signe d'un vol possible : tous les jetons de l'utilisateur sont
-- révoqués. La durée de vie est de 365 jours, renouvelée à chaque rotation.
-- Le changement de mot de passe révoque aussi ces jetons (voir
-- `invalidateSessions` et `setPassword` dans server/src/auth.ts).
-- Miroir repris dans db/schema.sql pour les nouvelles bases.
-- Idempotente (IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash    TEXT NOT NULL UNIQUE,
    church_id     UUID REFERENCES churches (id) ON DELETE CASCADE,
    channel       TEXT NOT NULL CHECK (channel IN ('web', 'mobile')),
    token_version INT NOT NULL DEFAULT 0,
    expires_at    TIMESTAMPTZ NOT NULL,
    used_at       TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens (token_hash);
