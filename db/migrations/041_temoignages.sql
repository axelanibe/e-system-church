-- 041 — Témoignages (lot 3c, 22 novembre 2026).
-- Témoignages texte, photo, vidéo ou audio, publiés par un membre et
-- modérés par l'admin de l'église (statuts en_attente / approuve /
-- rejete). Modèle : Connexion Prophétique (lib/temoignages.dart,
-- server-production/src/temoignages.js), adapté : isolation par
-- church_id comme la messagerie, modération réservée à admin_eglise,
-- médias stockés en base (BYTEA) faute de compartiment objet — les
-- prédications ne stockent que des URL externes. Le statut ne
-- s'affiche que pour l'auteur et l'admin, jamais dans le fil public
-- (seuls les approuvés y sont visibles). Aucune donnée inventée :
-- l'auteur est le compte connecté (nom résolu depuis sa fiche membre,
-- sinon son compte), le texte et le média viennent de la publication.
-- Miroir dans db/schema.sql (section « Migration 041 »).
CREATE TABLE IF NOT EXISTS temoignages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id        UUID NOT NULL REFERENCES churches (id) ON DELETE CASCADE,
    auteur_user_id   UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    auteur_member_id UUID REFERENCES members (id) ON DELETE SET NULL,
    auteur_nom       TEXT NOT NULL,
    texte            TEXT NOT NULL DEFAULT '',
    type_media       TEXT NOT NULL CHECK (type_media IN ('texte', 'photo', 'video', 'audio')),
    type_mime        TEXT,
    media_octets     BYTEA,
    media_nom        TEXT,
    statut           TEXT NOT NULL DEFAULT 'en_attente'
                       CHECK (statut IN ('en_attente', 'approuve', 'rejete')),
    motif_rejet      TEXT,
    cree_le          TIMESTAMPTZ NOT NULL DEFAULT now(),
    modere_le        TIMESTAMPTZ,
    modere_par       UUID REFERENCES users (id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_temoignages_church_statut
    ON temoignages (church_id, statut, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_temoignages_auteur
    ON temoignages (auteur_user_id, cree_le DESC);
