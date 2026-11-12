-- Migration 021 — abonnements et codes promo (tranche P3, 12 novembre 2026)
-- Abonnement annuel de l'église mère, 200 000 FCFA par an, couvrant
-- l'église mère et toutes ses annexes ; durées 1, 3 et 10 ans avec
-- remise dégressive ; essai gratuit 30 jours ; grâce 30 jours avant
-- la lecture seule. Les codes promo sont réservés au lancement, avec
-- une date de fin ; aucune interface admin de création des codes pour
-- l'instant (point ouvert). Aucun moyen de paiement stocké ici, il
-- n'est pas décidé. Idempotente (IF NOT EXISTS).
-- Miroir à reprendre dans db/schema.sql pour les nouvelles bases
-- (Lot B), comme pour les migrations 019 et 020.

CREATE TABLE IF NOT EXISTS codes_promo (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code           TEXT NOT NULL UNIQUE,
    type_reduction TEXT NOT NULL CHECK (type_reduction IN ('pourcentage', 'montant')),
    valeur         INTEGER NOT NULL CHECK (valeur > 0),
    date_debut     DATE,
    date_fin       DATE,
    actif          BOOLEAN NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS abonnements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id       UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    plan            TEXT NOT NULL DEFAULT 'annuel',
    duree_annees    INTEGER NOT NULL DEFAULT 1 CHECK (duree_annees IN (1, 3, 10)),
    montant_fcfa    INTEGER NOT NULL DEFAULT 200000 CHECK (montant_fcfa >= 0),
    statut          TEXT NOT NULL DEFAULT 'actif'
                    CHECK (statut IN ('essai', 'actif', 'grace', 'expire')),
    date_debut      DATE,
    date_expiration DATE,
    code_promo_id   UUID REFERENCES codes_promo (id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (church_id)
);
CREATE INDEX IF NOT EXISTS idx_abonnements_church
    ON abonnements (church_id);
