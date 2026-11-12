-- Migration 012 — connexion par téléphone (11 novembre 2026)
-- Normalise les téléphones existants avec la même règle que
-- `normalizePhone` côté serveur : espaces, tirets, points et parenthèses
-- retirés ; `0XXXXXXXXX` devient `+225XXXXXXXXX` ; `225XXXXXXXXX` devient
-- `+225XXXXXXXXX` ; le 0 après l'indicatif est retiré aussi (`+2250...`
-- et `2250...` deviennent `+225...`) ; un numéro international `+...`
-- est gardé tel quel.
-- Si deux comptes se retrouvent avec le même numéro normalisé, la
-- migration s'arrête en nommant les numéros en double : il faut les
-- traiter avant de relancer (fusionner les comptes ou corriger le numéro).
-- Puis unicité sur users.phone (les NULL restent autorisés, plusieurs
-- comptes sans téléphone restent possibles).

UPDATE users SET phone = n.tel
  FROM (
    SELECT id,
           CASE
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^\+2250[0-9]{7,9}$'
               THEN '+225' || substr(regexp_replace(phone, '[\s\-\.\(\)]', '', 'g'), 6)
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^2250[0-9]{7,9}$'
               THEN '+225' || substr(regexp_replace(phone, '[\s\-\.\(\)]', '', 'g'), 5)
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^0[0-9]{7,9}$'
               THEN '+225' || substr(regexp_replace(phone, '[\s\-\.\(\)]', '', 'g'), 2)
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^225[0-9]{7,9}$'
               THEN '+' || regexp_replace(phone, '[\s\-\.\(\)]', '', 'g')
             ELSE regexp_replace(phone, '[\s\-\.\(\)]', '', 'g')
           END AS tel
      FROM users WHERE phone IS NOT NULL
  ) n
 WHERE users.id = n.id;

UPDATE members SET phone = n.tel
  FROM (
    SELECT id,
           CASE
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^\+2250[0-9]{7,9}$'
               THEN '+225' || substr(regexp_replace(phone, '[\s\-\.\(\)]', '', 'g'), 6)
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^2250[0-9]{7,9}$'
               THEN '+225' || substr(regexp_replace(phone, '[\s\-\.\(\)]', '', 'g'), 5)
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^0[0-9]{7,9}$'
               THEN '+225' || substr(regexp_replace(phone, '[\s\-\.\(\)]', '', 'g'), 2)
             WHEN regexp_replace(phone, '[\s\-\.\(\)]', '', 'g') ~ '^225[0-9]{7,9}$'
               THEN '+' || regexp_replace(phone, '[\s\-\.\(\)]', '', 'g')
             ELSE regexp_replace(phone, '[\s\-\.\(\)]', '', 'g')
           END AS tel
      FROM members WHERE phone IS NOT NULL
  ) n
 WHERE members.id = n.id;

DO $$
DECLARE
  doublons text;
BEGIN
  SELECT string_agg(phone, ', ') INTO doublons
    FROM (SELECT phone FROM users WHERE phone IS NOT NULL GROUP BY phone HAVING count(*) > 1) d;
  IF doublons IS NOT NULL THEN
    RAISE EXCEPTION 'Téléphones en double après normalisation : %. Traiter les doublons avant de relancer la migration.', doublons;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_phone_unique') THEN
    ALTER TABLE users ADD CONSTRAINT users_phone_unique UNIQUE (phone);
  END IF;
END $$;
