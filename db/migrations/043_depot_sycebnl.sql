-- 043_depot_sycebnl.sql — Dépôt SYCEBNL (tranche dépôt SYCEBNL, 22 novembre 2026)
--
-- Quatre registres qui rendent les états SYCEBNL complets (jusqu'ici une
-- synthèse de trésorerie : immobilisations, dettes, créances et notes
-- annexes à 0 par construction), un champ NCC dans l'identité, et le
-- suivi du dépôt annuel par église et par exercice.
--
-- Immobilisations : libellé, date d'acquisition, valeur d'acquisition,
-- amortissement cumulé saisi, valeur nette calculée (valeur moins
-- amortissement). Dettes et créances : libellé, montant, échéance,
-- statut en cours ou soldée. Notes annexes : titre, contenu, exercice.
-- Dépôts SYCEBNL : un suivi par église et par exercice, statut à
-- préparer, prêt ou déposé, date de dépôt et référence libre (par
-- exemple numéro de reçu e-impots).
--
-- Le dépôt lui-même se fait par l'église sur e-impots.gouv.ci avec son
-- NCC : il n'existe pas d'API DGI, l'application prépare, exporte et
-- suit, elle ne dépose pas elle-même. Le statut « déposé » ne se met
-- que par un geste explicite de l'admin, jamais automatiquement.
--
-- Numéro 043 : le plus grand numéro appliqué est 042 (chaîne de
-- prière) ; 038 reste réservé à la phase 3 du module identité.
ALTER TABLE IF EXISTS eglise_parametres
    ADD COLUMN IF NOT EXISTS ncc TEXT;

CREATE TABLE IF NOT EXISTS immobilisations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id           UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    libelle             TEXT NOT NULL,
    date_acquisition    DATE NOT NULL,
    valeur_acquisition  INT NOT NULL CHECK (valeur_acquisition > 0),
    amortissement_cumule INT NOT NULL DEFAULT 0 CHECK (amortissement_cumule >= 0),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_immobilisations_amortissement
        CHECK (amortissement_cumule <= valeur_acquisition)
);
CREATE INDEX IF NOT EXISTS idx_immobilisations_church
    ON immobilisations (church_id, date_acquisition);

CREATE TABLE IF NOT EXISTS dettes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    libelle     TEXT NOT NULL,
    montant     INT NOT NULL CHECK (montant > 0),
    echeance    DATE,
    statut      TEXT NOT NULL DEFAULT 'en_cours'
                  CHECK (statut IN ('en_cours', 'soldee')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dettes_church
    ON dettes (church_id, statut);

CREATE TABLE IF NOT EXISTS creances (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    libelle     TEXT NOT NULL,
    montant     INT NOT NULL CHECK (montant > 0),
    echeance    DATE,
    statut      TEXT NOT NULL DEFAULT 'en_cours'
                  CHECK (statut IN ('en_cours', 'soldee')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_creances_church
    ON creances (church_id, statut);

CREATE TABLE IF NOT EXISTS notes_annexes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre       TEXT NOT NULL,
    contenu     TEXT NOT NULL,
    exercice    INT NOT NULL CHECK (exercice BETWEEN 2000 AND 2100),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notes_annexes_church
    ON notes_annexes (church_id, exercice);

CREATE TABLE IF NOT EXISTS depots_sycebnl (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    exercice    INT NOT NULL CHECK (exercice BETWEEN 2000 AND 2100),
    statut      TEXT NOT NULL DEFAULT 'a_preparer'
                  CHECK (statut IN ('a_preparer', 'pret', 'depose')),
    date_depot  DATE,
    reference   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_depots_sycebnl_church_exercice
        UNIQUE (church_id, exercice)
);
CREATE INDEX IF NOT EXISTS idx_depots_sycebnl_church
    ON depots_sycebnl (church_id, exercice);
