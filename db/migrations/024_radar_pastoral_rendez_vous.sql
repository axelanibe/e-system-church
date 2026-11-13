-- Migration 024 — Radar pastoral et rendez-vous, partie serveur (tranche T6, 13 novembre 2026)
-- (1) Radar des absences consécutives (3 et +) : VUE CALCULÉE v_radar_absences,
--     pas une table — depuis les présences (presences) et les cultes (cultes).
--     Un culte compte comme une absence quand le membre n'y a pas de
--     pointage « present ». La série s'arrête à la dernière présence ; on
--     ne compte pas les cultes d'avant l'arrivée du membre (members.created_at),
--     ni les cultes à venir (date_heure > now()). Les membres « inactif »
--     sont exclus. La route GET /radar-absences filtre absences >= 3.
-- (2) Visites pastorales typées : type (domicile / hopital) + lieu.
-- (3) Accompagnements : rencontres datées (table rencontres_accompagnement)
--     + priorité des cas (colonne priorite sur accompagnements).
-- (4) Rendez-vous : AUCUNE table — rendez_vous existe déjà (migration 022) ;
--     la gestion côté admin est une route (pastoral.ts).
-- Idempotente (IF NOT EXISTS / OR REPLACE). Miroir dans db/schema.sql.
-- Miroir à reprendre dans db/schema.sql pour les nouvelles bases (Lot B).

-- -- Visites pastorales typées ---------------------------------------------
ALTER TABLE visites_pastorales
  ADD COLUMN IF NOT EXISTS type TEXT CHECK (type IN ('domicile', 'hopital')),
  ADD COLUMN IF NOT EXISTS lieu TEXT;

-- -- Accompagnements : priorité des cas -------------------------------------
ALTER TABLE accompagnements
  ADD COLUMN IF NOT EXISTS priorite TEXT NOT NULL DEFAULT 'normale'
    CHECK (priorite IN ('basse', 'normale', 'haute', 'urgente'));

-- -- Rencontres d'accompagnement datées --------------------------------------
CREATE TABLE IF NOT EXISTS rencontres_accompagnement (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    accompagnement_id UUID NOT NULL REFERENCES accompagnements (id) ON DELETE CASCADE,
    date_rencontre   DATE NOT NULL,
    note             TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rencontres_accompagnement
    ON rencontres_accompagnement (accompagnement_id, date_rencontre);

-- -- Radar des absences consécutives (vue calculée) -------------------------
CREATE OR REPLACE VIEW v_radar_absences AS
SELECT
  m.church_id,
  m.id AS member_id,
  m.full_name AS membre_nom,
  m.matricule AS membre_matricule,
  m.phone AS membre_telephone,
  m.email AS membre_email,
  m.status AS membre_statut,
  (
    SELECT count(*)::int
      FROM cultes c
     WHERE c.church_id = m.church_id
       AND c.date_heure <= now()
       AND c.date_heure > COALESCE(derniere_presence.date_heure, m.created_at)
  ) AS absences_consecutives,
  derniere_presence.date_heure AS derniere_presence
FROM members m
LEFT JOIN LATERAL (
  SELECT max(c2.date_heure) AS date_heure
    FROM cultes c2
    JOIN presences p
      ON p.culte_id = c2.id
     AND p.member_id = m.id
     AND p.statut = 'present'
   WHERE c2.church_id = m.church_id
) derniere_presence ON true
WHERE m.status <> 'inactif';
