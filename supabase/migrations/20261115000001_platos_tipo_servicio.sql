-- =====================================================================
-- Migración: tipo de elemento en platos (plato | servicio)
-- =====================================================================
-- Permite crear "servicios" (ej. delivery, cargo por servicio) además de
-- platos normales. Un servicio pertenece a cualquier categoria de platos
-- igual que un plato y, al agregarse a una comanda, el usuario puede
-- editar su precio manualmente (no tiene precio fijo).
--
--   'plato'     = producto de cocina normal (precio fijo del catalogo)
--   'servicio'  = servicio/adicional (precio editable al agregarlo)
--
-- Requiere rol propietario (`postgres`), no `control_app`.

BEGIN;

ALTER TABLE platos
    ADD COLUMN IF NOT EXISTS tipo TEXT DEFAULT 'plato';

-- Valor por defecto para filas existentes
UPDATE platos SET tipo = 'plato' WHERE tipo IS NULL;

-- Columna NOT NULL con default para nuevas inserciones
ALTER TABLE platos
    ALTER COLUMN tipo SET NOT NULL,
    ALTER COLUMN tipo SET DEFAULT 'plato';

COMMIT;
