-- 039_activites_a_venir.sql — Activités à venir (V1)
--
-- Table `activites` : une activité a un titre, une description
-- facultative, une date et une heure, un lieu, un responsable (nom
-- libre) et un statut brouillon ou publié. Les brouillons ne sont
-- jamais visibles côté fidèle : la route /moi/activites ne renvoie
-- que les publiées à venir, et le readScope de /activites cache les
-- brouillons aux membres.
-- Pas de présence, pas de notification, pas de récurrence, pas de
-- pièce jointe en V1.
--
-- Numéro 038 volontairement sauté : réservé à la phase 3 du module
-- identité (modèles de carte, émissions, modèles de document,
-- documents générés). Le test test-migrations-t13.mjs documente
-- ce trou avec le 017.
CREATE TABLE IF NOT EXISTS activites (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    titre       TEXT NOT NULL,
    description TEXT,
    date_heure  TIMESTAMPTZ NOT NULL,
    lieu        TEXT,
    responsable TEXT,
    statut      TEXT NOT NULL DEFAULT 'brouillon'
                  CHECK (statut IN ('brouillon', 'publié')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_activites_church ON activites (church_id, date_heure);
