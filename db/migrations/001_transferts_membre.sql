-- Migration 001 — transferts de membre entre branches (10 novembre 2026)
-- Appliquée par `npm run migrate` (server/src/migrate.ts), dans l'ordre.
-- Idempotente : un schéma déjà créé par db/schema.sql ne la rejoue pas
-- en erreur (types protégés par DO, table par IF NOT EXISTS).
-- Voir db/schema.sql pour le commentaire complet de la table.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transfert_status') THEN
    CREATE TYPE transfert_status AS ENUM ('en_attente', 'accepte', 'refuse', 'annule');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transfert_decision') THEN
    CREATE TYPE transfert_decision AS ENUM ('en_attente', 'accepte', 'refuse');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS transferts_membre (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membre_id           UUID NOT NULL REFERENCES members (id) ON DELETE RESTRICT,
    membre_nom          TEXT NOT NULL,
    ancien_matricule    TEXT NOT NULL,
    nouveau_matricule   TEXT,
    eglise_depart_id    UUID NOT NULL REFERENCES churches (id) ON DELETE RESTRICT,
    eglise_arrivee_id   UUID NOT NULL REFERENCES churches (id) ON DELETE RESTRICT,
    demande_par         UUID REFERENCES users (id) ON DELETE SET NULL,
    motif               TEXT,
    status              transfert_status NOT NULL DEFAULT 'en_attente',
    decision_depart     transfert_decision NOT NULL DEFAULT 'en_attente',
    decision_arrivee    transfert_decision NOT NULL DEFAULT 'en_attente',
    decide_depart_par   UUID REFERENCES users (id) ON DELETE SET NULL,
    decide_depart_at    TIMESTAMPTZ,
    decide_arrivee_par  UUID REFERENCES users (id) ON DELETE SET NULL,
    decide_arrivee_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT no_self_transfert CHECK (eglise_depart_id <> eglise_arrivee_id)
);
CREATE INDEX IF NOT EXISTS idx_transferts_depart ON transferts_membre (eglise_depart_id, created_at);
CREATE INDEX IF NOT EXISTS idx_transferts_arrivee ON transferts_membre (eglise_arrivee_id, created_at);
CREATE INDEX IF NOT EXISTS idx_transferts_membre ON transferts_membre (membre_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_transferts_membre_unique_en_attente
    ON transferts_membre (membre_id) WHERE status = 'en_attente';
