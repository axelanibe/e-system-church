-- Migration 023 — rapports d'une annexe à son église mère (tranche
-- P5, 12 novembre 2026). L'annexe choisit le type de rapport, l'ap-
-- plication le génère depuis ses vraies données et l'envoie par
-- e-mail à son église mère, en pièce jointe PDF. L'envoi par e-mail
-- passe par mailer.ts (Lot B) : en attendant, le rapport est enre-
-- gistré avec le statut `en_attente_envoi`, visible par la mère dans
-- « Rapports reçus », et l'envoi est marqué en attente du Lot B.
-- Le statut passe à `envoye` quand le Lot B branchera l'envoi.
-- Aucune adresse e-mail inventée ici : celle de la mère se lit dans
-- churches.email, nulle tant qu'elle n'est pas renseignée.
-- Miroir à reprendre dans db/schema.sql pour les nouvelles bases
-- (Lot B), comme pour les migrations 019, 020 et 021. Idempotente
-- (IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS rapports_annexe (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    eglise_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    eglise_mere_id UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    type           TEXT NOT NULL CHECK (type IN ('bilan_annuel', 'bilan_activite', 'rapport_financier')),
    message        TEXT,
    membres        INTEGER NOT NULL DEFAULT 0 CHECK (membres >= 0),
    recettes_fcfa  INTEGER NOT NULL DEFAULT 0 CHECK (recettes_fcfa >= 0),
    depenses_fcfa  INTEGER NOT NULL DEFAULT 0 CHECK (depenses_fcfa >= 0),
    solde_fcfa     INTEGER NOT NULL DEFAULT 0,
    statut         TEXT NOT NULL DEFAULT 'en_attente_envoi'
                   CHECK (statut IN ('en_attente_envoi', 'envoye')),
    cree_le        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rapports_annexe_mere
    ON rapports_annexe (eglise_mere_id, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_rapports_annexe_eglise
    ON rapports_annexe (eglise_id, cree_le DESC);
