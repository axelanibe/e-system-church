-- Migration 008 — attestations annuelles de dons, US3 (11 novembre 2026)
-- Appliquée par `npm run migrate` (server/src/migrate.ts), dans l'ordre.
-- Idempotente (IF NOT EXISTS, ON CONFLICT / index IF NOT EXISTS).
-- Une attestation émise est figée : son contenu (dons, donateur, église)
-- est copié en JSONB au moment de l'émission, jamais recalculé ensuite.
-- Une correction crée une nouvelle attestation (nouveau numéro) et passe
-- l'ancienne en `annulee` (remplace_id pointe vers l'ancienne).
-- Numéro unique par église et année (ex. ATT-2026-0001) ; une seule
-- attestation émise par membre, église et année (index partiel).
-- En Côte d'Ivoire, l'attestation n'a aucune valeur fiscale : reçu
-- justificatif seulement (mention portée sur le PDF, pas en base).

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
-- Une seule attestation émise par membre, église et année : la génération
-- ne régénère pas un doublon, la correction annule l'ancienne d'abord.
CREATE UNIQUE INDEX IF NOT EXISTS idx_attestations_une_emise
    ON attestations (church_id, member_id, annee) WHERE statut = 'emise';
