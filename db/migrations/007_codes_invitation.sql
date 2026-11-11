-- 007 — Codes d'invitation à deux niveaux (décision de Bouf, 11 nov. 2026).
-- `code` (ESC-XXXXXX) reste le code de tutelle : une église secondaire
-- l'utilise pour se rattacher à sa mère (POST /rattachements).
-- `code_fidele` (ESC-F-XXXXXX) est le code que les membres utilisent pour
-- s'inscrire dans la bonne église (inscription par code fidèle, et
-- inscription par matricule avec code fidèle en option) : il désigne une
-- seule église, sans ambiguïté, pour éviter qu'un fidèle se trompe d'église.
ALTER TABLE churches ADD COLUMN IF NOT EXISTS code_fidele TEXT;

UPDATE churches
   SET code_fidele = 'ESC-F-' || upper(substr(md5(gen_random_uuid()::text), 1, 6))
 WHERE code_fidele IS NULL;

ALTER TABLE churches ALTER COLUMN code_fidele SET NOT NULL;
ALTER TABLE churches ADD CONSTRAINT churches_code_fidele_unique UNIQUE (code_fidele);
CREATE INDEX IF NOT EXISTS idx_churches_code_fidele ON churches (code_fidele);
