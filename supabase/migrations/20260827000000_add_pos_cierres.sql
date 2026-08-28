-- =====================================================================
-- Migración: tabla pos_cierres (Fase 2 — Cierre de Caja con Corte de Inventario)
-- =====================================================================
-- Tabla histórica inmutable para el corte de caja/inventario al cerrar sesión.
-- Se inserta una fila por cada cierre de turno (pos_sesiones -> pos_cierres).

BEGIN;

CREATE TABLE IF NOT EXISTS pos_cierres (
    id                      SERIAL PRIMARY KEY,
    sesion_id               INTEGER NOT NULL REFERENCES pos_sesiones(id),
    usuario_id              INTEGER NOT NULL REFERENCES pos_usuarios(id),
    abierta_en              TEXT NOT NULL,          -- ISO8601, heredada de pos_sesiones
    cerrada_en              TEXT NOT NULL,          -- ISO8601, momento del cierre
    caja_inicial            DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_ventas            DOUBLE PRECISION NOT NULL DEFAULT 0,
    caja_final              DOUBLE PRECISION NOT NULL DEFAULT 0,
    reporte_simple_json     TEXT,                   -- JSON: agregado por producto/plato + categoría
    reporte_detallado_json  TEXT,                   -- JSON: desglose por ingrediente + stock final + usos
    sync_uuid               TEXT NOT NULL,          -- UUID único para sincronización/idepotencia
    created_at              TIMESTAMPTZ DEFAULT now(),
    updated_at              TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pos_cierres_sesion ON pos_cierres (sesion_id);
CREATE INDEX IF NOT EXISTS idx_pos_cierres_usuario_fecha ON pos_cierres (usuario_id, cerrada_en DESC);
CREATE INDEX IF NOT EXISTS idx_pos_cierres_sync_uuid ON pos_cierres (sync_uuid);

-- Trigger para updated_at (reutiliza la función existente set_pos_updated_at)
CREATE TRIGGER trg_pos_cierres_updated_at
    BEFORE INSERT OR UPDATE ON pos_cierres
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

COMMIT;