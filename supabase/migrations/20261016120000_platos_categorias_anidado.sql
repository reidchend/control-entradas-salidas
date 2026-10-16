-- =====================================================================
-- Migracion: categorias de platos anidadas (POS)
-- =====================================================================
-- Agrega plato_categoria_padre_id a platos_categorias para permitir que
-- una categoria de platos cuelgue de otra categoria de platos (sub-categoria
-- dentro de una categoria). Las categorias sin padre (todas las columnas de
-- padre NULL) son "raiz" y se muestran directamente en la raiz del POS.

BEGIN;

ALTER TABLE platos_categorias
    ADD COLUMN IF NOT EXISTS plato_categoria_padre_id integer;

-- FK a la propia tabla: al borrar un padre, sus hijas quedan en la raiz
-- (no se borran en cascada para no perder platos).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'platos_categorias_plato_categoria_padre_id_fkey'
    ) THEN
        ALTER TABLE platos_categorias
            ADD CONSTRAINT platos_categorias_plato_categoria_padre_id_fkey
            FOREIGN KEY (plato_categoria_padre_id)
            REFERENCES platos_categorias (id)
            ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_platos_categorias_plato_padre
    ON platos_categorias (plato_categoria_padre_id);

COMMIT;
