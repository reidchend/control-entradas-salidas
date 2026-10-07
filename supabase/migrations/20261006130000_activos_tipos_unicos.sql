-- =====================================================================
-- Migración: unicidad de catálogo en Activos (tipos y categorías)
-- =====================================================================
-- Evita que vuelva a aparecer tipos duplicados (misma categoría + grupo +
-- nombre, sin importar mayúsculas ni espacios), como los que se fusionaron
-- el 2026-10-06. La app ya deduplica y reutiliza la escritura canónica al
-- crear; estos índices son la garantía de fondo a nivel de base de datos.

BEGIN;

-- Tipos: una sola fila por (categoría, grupo, nombre). Los NULLs se colapsan
-- con COALESCE porque en un índice único los NULLs no chocan entre sí.
CREATE UNIQUE INDEX IF NOT EXISTS uq_activos_tipos_cat_grupo_nombre
    ON activos_tipos (
        COALESCE(categoria_id, 0),
        LOWER(TRIM(COALESCE(grupo, ''))),
        LOWER(TRIM(nombre))
    );

-- Categorías: una sola por nombre, insensible a mayúsculas.
CREATE UNIQUE INDEX IF NOT EXISTS uq_activos_categorias_nombre
    ON activos_categorias (LOWER(TRIM(nombre)));

COMMIT;