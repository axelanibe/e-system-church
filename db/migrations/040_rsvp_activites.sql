-- 040_rsvp_activites.sql — Confirmation « Je serai présent » aux activités
--
-- Table `activite_rsvp` : miroir exact de `culte_rsvp` (migration 020)
-- pour les activités à venir. Une simple annonce de présence du fidèle,
-- sans toucher aux présences pointées (le pointage QR et les
-- statistiques restent sur `presences`). Un seul RSVP par membre et par
-- activité. Le doublon est refusé en 409 par la route
-- POST /moi/activites/:id/present (la route culte, plus ancienne, est
-- restée idempotente) ; l'annulation supprime la ligne, la reprise est
-- donc toujours possible.
-- Pas de miroir dans db/schema.sql (comme la 039) : les nouvelles bases
-- appliquent les migrations après le schéma initial.
CREATE TABLE IF NOT EXISTS activite_rsvp (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    activite_id UUID NOT NULL REFERENCES activites (id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (member_id, activite_id)
);
CREATE INDEX IF NOT EXISTS idx_activite_rsvp_activite
    ON activite_rsvp (activite_id, created_at);
