-- 042_chaine_priere.sql — Chaîne de prière (lot 3d, 22 novembre 2026).
--
-- Table `creneaux_priere` : un créneau d'une heure pris par un membre
-- pour un jour donné. 24 créneaux par jour (0 h à 23 h), un membre par
-- créneau, un créneau par membre et par jour — mêmes règles que la
-- chaîne de prière de Connexion Prophétique, adaptées à e-System
-- Church : isolation par `church_id`, comme la messagerie.
--
-- Deux contraintes d'unicité, nommées pour que la route distingue les
-- deux refus (409) : le créneau déjà pris, et le membre qui a déjà un
-- créneau ce jour-là. Le prénom affiché côté client est le premier mot
-- du nom complet du membre en base, jamais inventé : il n'est pas
-- stocké ici, la route le lit dans `members`.
--
-- Numéros 040 et 041 volontairement absents : 040 réservé par la
-- PR #154 ouverte (« Je serai présent », RSVP), 041 par le lot 3c
-- Témoignages (implémenté, pas encore sur main). Voir
-- db/migrations/README.md et server/test-migrations-t13.mjs.
CREATE TABLE IF NOT EXISTS creneaux_priere (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id   UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    member_id   UUID NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    jour        DATE NOT NULL,
    heure       SMALLINT NOT NULL CHECK (heure BETWEEN 0 AND 23),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_creneaux_priere_creneau
        UNIQUE (church_id, jour, heure),
    CONSTRAINT uq_creneaux_priere_membre_jour
        UNIQUE (church_id, member_id, jour)
);
CREATE INDEX IF NOT EXISTS idx_creneaux_priere_church_jour
    ON creneaux_priere (church_id, jour, heure);
