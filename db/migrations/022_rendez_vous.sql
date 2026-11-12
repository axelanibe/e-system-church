-- Migration 022 — demandes de rendez-vous du fidèle (tranche P4, 12 novembre 2026)
-- Le fidèle demande un rendez-vous auprès du pasteur de son église :
-- date souhaitée, créneau à compléter, motif. La demande est lue par
-- l'église depuis son espace ; la gestion des rendez-vous côté admin
-- et le radar restent la tranche T6 (Phoenix). Idempotente (IF NOT EXISTS).
-- Miroir à reprendre dans db/schema.sql pour les nouvelles bases
-- (Lot B), comme pour les migrations 019 et 020.

CREATE TABLE IF NOT EXISTS rendez_vous (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id      UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    date_souhaitee DATE NOT NULL,
    creneau        TEXT CHECK (creneau IS NULL OR char_length(creneau) BETWEEN 1 AND 50),
    motif          TEXT NOT NULL CHECK (char_length(motif) BETWEEN 1 AND 1000),
    statut         TEXT NOT NULL DEFAULT 'en_attente'
                   CHECK (statut IN ('en_attente', 'confirme', 'refuse', 'annule')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rendez_vous_membre
    ON rendez_vous (church_id, member_id, created_at);
