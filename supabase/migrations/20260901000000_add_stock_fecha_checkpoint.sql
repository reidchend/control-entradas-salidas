-- =====================================================================
-- Migración: recálculo absoluto de stock + archivo sin retención
-- =====================================================================
-- 1) stock_checkpoint.fecha_checkpoint: fecha del snapshot para cálculos
--    en tiempo real (el recálculo ya no usa el checkpoint como base).
-- 2) movimientos_archivo.venta_id / venta_sync_uuid: espejo de
--    movimientos para archivar filas de venta sin perder columnas.

ALTER TABLE stock_checkpoint
    ADD COLUMN IF NOT EXISTS fecha_checkpoint TIMESTAMPTZ DEFAULT now();

ALTER TABLE movimientos_archivo
    ADD COLUMN IF NOT EXISTS venta_id INTEGER,
    ADD COLUMN IF NOT EXISTS venta_sync_uuid TEXT;