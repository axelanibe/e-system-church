-- Migration 013 — colonne photo_url manquante sur members (Lot B, tranche 1)
-- Le code (server/src/routes/membres.ts, server/src/routes/fidele.ts) lit et
-- écrit members.photo_url, mais ni db/schema.sql ni aucune migration ne
-- créaient la colonne : la création d'un membre échouait (500) sur une base
-- fraîche. Idempotente (IF NOT EXISTS) : sans effet sur une base qui l'a déjà.
ALTER TABLE members ADD COLUMN IF NOT EXISTS photo_url TEXT;
