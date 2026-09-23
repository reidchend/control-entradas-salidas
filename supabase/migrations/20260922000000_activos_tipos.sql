-- =====================================================================
-- Migración: catálogo de tipos de activos + unidades individuales
-- =====================================================================
-- El inventario de Activos pasa de una sola tabla plana (nombre/grupo/
-- modelo/categoría/cantidad en cada fila) a dos niveles:
--   - activos_tipos: catálogo maestro de modelos (nombre, grupo, modelo,
--     categoría). Centraliza la identidad/especificación para evitar
--     nombres inconsistentes al agregar existencias.
--   - activos: una fila por unidad física (ubicación, estado, valor,
--     fecha, observaciones) referenciando su tipo (tipo_id).
-- Backfill: cada combinación distinta (nombre + grupo + modelo +
-- categoría) existente se convierte en un tipo; las filas con cantidad > 1
-- se expanden en N unidades.

BEGIN;

-- 1. Catálogo de tipos
CREATE TABLE IF NOT EXISTS activos_tipos (
    id           SERIAL PRIMARY KEY,
    nombre       TEXT NOT NULL,
    grupo        TEXT,
    modelo       TEXT,
    categoria_id INTEGER REFERENCES activos_categorias(id) ON DELETE SET NULL,
    activo       BOOLEAN DEFAULT TRUE,
    created_at   TIMESTAMPTZ DEFAULT now(),
    updated_at   TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_activos_tipos_updated_at ON activos_tipos;
CREATE TRIGGER trg_activos_tipos_updated_at
    BEFORE INSERT OR UPDATE ON activos_tipos
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

-- 2. Backfill de tipos desde los activos actuales
--    Normaliza grupo/modelo: '' y NULL colapsan al mismo tipo.
INSERT INTO activos_tipos (nombre, grupo, modelo, categoria_id)
SELECT DISTINCT COALESCE(a.nombre, ''),
       NULLIF(a.grupo, ''),
       NULLIF(a.modelo, ''),
       a.categoria_id
FROM activos a;

-- 3. Vínculo activo -> tipo
ALTER TABLE activos ADD COLUMN IF NOT EXISTS tipo_id
    INTEGER REFERENCES activos_tipos(id) ON DELETE RESTRICT;

UPDATE activos a
SET tipo_id = t.id
FROM activos_tipos t
WHERE t.nombre = COALESCE(a.nombre, '')
  AND t.grupo IS NOT DISTINCT FROM NULLIF(a.grupo, '')
  AND t.modelo IS NOT DISTINCT FROM NULLIF(a.modelo, '')
  AND t.categoria_id IS NOT DISTINCT FROM a.categoria_id;

-- 3b. Respaldo: filas que no emparejaron por categoría se vinculan por
--     identidad (nombre + grupo + modelo) para no dejar unidades huérfanas.
UPDATE activos a
SET tipo_id = t.id
FROM activos_tipos t
WHERE a.tipo_id IS NULL
  AND t.nombre = COALESCE(a.nombre, '')
  AND t.grupo IS NOT DISTINCT FROM NULLIF(a.grupo, '')
  AND t.modelo IS NOT DISTINCT FROM NULLIF(a.modelo, '');

-- 4. Expandir cantidades: cada fila con cantidad > 1 se convierte en N
--    unidades (la fila original queda como la primera unidad).
--    `nombre` se copia tal cual ya que la columna es NOT NULL en este
--    punto del script (se dropea al final); las filas nuevas la toman de
--    la original vía catálogo.
INSERT INTO activos (tipo_id, nombre, ubicacion, estado, valor, fecha,
                     observaciones, activo, created_at, updated_at)
SELECT a.tipo_id, a.nombre, a.ubicacion, a.estado, a.valor, a.fecha,
       a.observaciones, a.activo, a.created_at, now()
FROM activos a, generate_series(2, a.cantidad)
WHERE a.cantidad > 1;

-- 5. Limpieza: campos que ahora viven en el catálogo o por unidad
ALTER TABLE activos
    DROP COLUMN IF EXISTS nombre,
    DROP COLUMN IF EXISTS categoria_id,
    DROP COLUMN IF EXISTS grupo,
    DROP COLUMN IF EXISTS modelo,
    DROP COLUMN IF EXISTS cantidad;

CREATE INDEX IF NOT EXISTS idx_activos_tipo_id ON activos (tipo_id);
CREATE INDEX IF NOT EXISTS idx_activos_tipos_categoria ON activos_tipos (categoria_id);

-- 6. Trigger de updated_at en activos
DROP TRIGGER IF EXISTS trg_activos_updated_at ON activos;
CREATE TRIGGER trg_activos_updated_at
    BEFORE INSERT OR UPDATE ON activos
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

COMMIT;