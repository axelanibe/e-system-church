-- Migration 020 — messages fidèle et confirmation de présence au culte
-- (tranche P1, 12 novembre 2026)
-- Fil privé du fidèle avec son église mère ou sa tutelle, dans
-- l'application, pas par e-mail. Le fil vit par membre et par église :
-- un message de l'église est écrit par un administrateur de l'église
-- du membre (ou de son église mère, qui voit les fils de ses annexes).
-- Confirmation « Je serai présent » au prochain culte : une simple
-- annonce de présence, sans toucher aux présences pointées (T5 garde
-- le pointage QR et les statistiques). Un seul RSVP par membre et par
-- culte. Idempotente (IF NOT EXISTS).
-- Miroir à reprendre dans db/schema.sql pour les nouvelles bases
-- (Lot B), comme pour la migration 019.

CREATE TABLE IF NOT EXISTS messages_fidele (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    auteur     TEXT NOT NULL CHECK (auteur IN ('membre', 'eglise')),
    corps      TEXT NOT NULL CHECK (char_length(corps) BETWEEN 1 AND 5000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_fidele_fil
    ON messages_fidele (church_id, member_id, created_at);

CREATE TABLE IF NOT EXISTS culte_rsvp (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    culte_id   UUID NOT NULL REFERENCES cultes (id) ON DELETE CASCADE,
    member_id  UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (member_id, culte_id)
);
CREATE INDEX IF NOT EXISTS idx_culte_rsvp_culte
    ON culte_rsvp (culte_id, created_at);
