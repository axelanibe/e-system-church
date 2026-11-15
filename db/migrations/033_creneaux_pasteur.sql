-- Migration 033 — créneaux de rendez-vous définis par le pasteur
-- (corrections audit 63, tranche 3, E-RV1, 15 novembre 2026).
-- Le pasteur définit ses créneaux (libellé libre, sans horaire
-- inventé) par période : matin, après-midi, soir. Le fidèle choisit
-- un libellé parmi les créneaux actifs de son église quand il demande
-- un rendez-vous (migration 022, colonne rendez_vous.creneau).
-- Aucun créneau pré-créé, aucune période pré-remplie.
-- Idempotente (IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS creneaux_pasteur (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id  UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    periode    TEXT NOT NULL CHECK (periode IN ('matin', 'apres-midi', 'soir')),
    libelle    TEXT NOT NULL CHECK (char_length(libelle) BETWEEN 1 AND 50),
    actif      BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_creneaux_pasteur_eglise
    ON creneaux_pasteur (church_id, periode, created_at);
