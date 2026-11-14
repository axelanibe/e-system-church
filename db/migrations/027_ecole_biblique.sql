-- Migration 027 — École biblique (tranche T9, Lot B, 13 novembre 2026).
-- La Bible elle-même ne vit pas en base : le texte Louis Segond 1910
-- (domaine public, source eBible.org/fraLSG — voir
-- server/src/data/bible/SOURCES.md ; le dépôt BibleCorps a été écarté
-- car sans licence explicite) est servi depuis des JSON par livre
-- (server/src/data/bible/lsg1910/, générés par
-- server/scripts/convertir-lsg1910.py). Cette migration ne crée
-- que les tables de l'école biblique : le contenu des cours et des
-- leçons est créé par l'église (admin / responsable de culte), jamais
-- pré-rempli avec du contenu fictif.
--
-- (1) cours_ecole : un cours (titre, description, niveau, actif).
-- (2) lecons_ecole : les leçons d'un cours, dans un ordre (UNIQUE par
--     cours) ; contenu libre + référence biblique (ex. « Jean 3:16 »).
-- (3) inscriptions_ecole : un membre inscrit à un cours (UNIQUE par
--     cours et membre) ; statut inscrit / termine / abandonne.
-- (4) progressions_ecole : une leçon terminée par une inscription
--     (UNIQUE par inscription et leçon) ; le statut 'termine' de
--     l'inscription est posé par le serveur quand toutes les leçons
--     du cours sont terminées.
-- Idempotente (IF NOT EXISTS, gardes DO). Miroir dans db/schema.sql.

CREATE TABLE IF NOT EXISTS cours_ecole (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre       TEXT NOT NULL,
    description TEXT,
    niveau      TEXT CHECK (niveau IN ('debutant', 'intermediaire', 'avance')),
    actif       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cours_ecole_church
    ON cours_ecole (church_id, actif);

CREATE TABLE IF NOT EXISTS lecons_ecole (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id         UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    cours_id          UUID NOT NULL REFERENCES cours_ecole (id) ON DELETE CASCADE,
    ordre             INT NOT NULL CHECK (ordre > 0),
    titre             TEXT NOT NULL,
    contenu           TEXT,
    reference_biblique TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (cours_id, ordre)
);
CREATE INDEX IF NOT EXISTS idx_lecons_ecole_cours
    ON lecons_ecole (cours_id, ordre);

CREATE TABLE IF NOT EXISTS inscriptions_ecole (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    cours_id         UUID NOT NULL REFERENCES cours_ecole (id) ON DELETE CASCADE,
    member_id        UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    statut           TEXT NOT NULL DEFAULT 'inscrit'
                     CHECK (statut IN ('inscrit', 'termine', 'abandonne')),
    date_inscription DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (cours_id, member_id)
);
CREATE INDEX IF NOT EXISTS idx_inscriptions_ecole_cours
    ON inscriptions_ecole (cours_id, member_id);
CREATE INDEX IF NOT EXISTS idx_inscriptions_ecole_membre
    ON inscriptions_ecole (member_id, statut);

CREATE TABLE IF NOT EXISTS progressions_ecole (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id      UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    inscription_id UUID NOT NULL REFERENCES inscriptions_ecole (id) ON DELETE CASCADE,
    lecon_id       UUID NOT NULL REFERENCES lecons_ecole (id) ON DELETE CASCADE,
    termine_le     TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (inscription_id, lecon_id)
);
CREATE INDEX IF NOT EXISTS idx_progressions_ecole_inscription
    ON progressions_ecole (inscription_id, lecon_id);
