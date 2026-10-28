-- Añade precio de referencia desde MercadoLibre Venezuela a activos_tipos
ALTER TABLE activos_tipos
  ADD COLUMN IF NOT EXISTS precio_referencia NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS precio_origen TEXT,
  ADD COLUMN IF NOT EXISTS precio_actualizado_at TIMESTAMPTZ;
