-- Migration 004 — dépenses Budget & caisse dans les statistiques (10 novembre 2026)
-- La vue v_stats_eglise ne comptait que les contributions de type « depense » :
-- le tableau de bord affichait 0 FCFA de dépenses alors que le module Budget &
-- caisse contenait des dépenses. Désormais, depenses_mois_fcfa additionne les
-- deux (dépenses Budget hors refusées, mois courant). CREATE OR REPLACE VIEW :
-- rejouable sans erreur. Le même correctif est appliqué dans db/schema.sql
-- (schéma initial) pour les nouvelles bases.
CREATE OR REPLACE VIEW v_stats_eglise AS
SELECT
    c.id AS eglise_id,
    c.name AS eglise_nom,
    (SELECT count(*) FROM members m WHERE m.church_id = c.id AND m.status = 'actif') AS membres_actifs,
    (SELECT count(*) FROM members m WHERE m.church_id = c.id AND m.status = 'nouveau_converti') AS nouveaux_convertis,
    (SELECT count(*) FROM baptemes b WHERE b.church_id = c.id) AS baptemes,
    (SELECT count(*) FROM cultes cu WHERE cu.church_id = c.id
        AND cu.date_heure >= date_trunc('month', now())
        AND cu.date_heure < date_trunc('month', now()) + interval '1 month') AS cultes_mois,
    (SELECT count(*) FROM presences p WHERE p.church_id = c.id
        AND p.statut = 'present'
        AND p.pointe_at >= date_trunc('month', now())) AS presences_mois,
    (SELECT coalesce(sum(amount_fcfa), 0) FROM contributions co
        WHERE co.church_id = c.id AND co.type IN ('dime','offrande','don')
        AND co.status = 'confirme'
        AND co.created_at >= date_trunc('month', now())) AS recettes_mois_fcfa,
    (SELECT coalesce(sum(amount_fcfa), 0) FROM contributions co
        WHERE co.church_id = c.id AND co.type = 'depense'
        AND co.status = 'confirme'
        AND co.created_at >= date_trunc('month', now())) +
    -- Dépenses du module Budget & caisse (hors refusées) du mois courant :
    -- sans elles, le tableau de bord affichait 0 de dépenses.
    (SELECT coalesce(sum(montant_fcfa), 0) FROM depenses d
        WHERE d.church_id = c.id AND d.statut <> 'refusee'
        AND d.date_depense >= date_trunc('month', now())::date
        AND d.date_depense < (date_trunc('month', now()) + interval '1 month')::date) AS depenses_mois_fcfa
FROM churches c;
