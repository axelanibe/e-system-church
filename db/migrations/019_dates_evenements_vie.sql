-- Migration 019 — dates d'événements de vie du membre (tranche T4, 12 novembre 2026)
-- US7 (parcours) : la date de baptême vit déjà dans `baptemes`, les dates de
-- conversion et de mariage n'existaient nulle part. Elles restent NULL tant
-- qu'elles ne sont pas renseignées, jamais inventées.
-- Statut « ancien » distinct : les statuts riches vivent dans
-- `membre_statuts` ; « ancien » s'ajoute à la liste. Un ancien membre reste
-- « inactif » dans members.status, l'enum simple ne change pas.
-- Miroir repris dans db/schema.sql pour les nouvelles bases.
-- Idempotente (IF NOT EXISTS / DROP CONSTRAINT IF EXISTS).

ALTER TABLE members ADD COLUMN IF NOT EXISTS date_mariage DATE;
ALTER TABLE members ADD COLUMN IF NOT EXISTS date_conversion DATE;

ALTER TABLE membre_statuts DROP CONSTRAINT IF EXISTS membre_statuts_statut_check;
ALTER TABLE membre_statuts ADD CONSTRAINT membre_statuts_statut_check
  CHECK (statut IN ('membre','sympathisant','nouveau_converti','en_formation','suspendu','parti','ancien'));
