-- =====================================================================
-- Migración: estados de habitación + modalidad por horas (OP)
-- =====================================================================
-- 1. Las habitaciones pasan a ser dominio de Hostelería: se renombran las
--    tablas `pos_habitaciones` -> `habitaciones` y
--    `pos_tipos_habitacion` -> `tipos_habitacion` (las FK y los ids se
--    conservan; el POS de restaurante las sigue usando para comandas).
-- 2. Estado operativo de la habitación (independiente de las reservas):
--    libre | aseo | mantenimiento.
-- 3. Modalidad de estancia: por noche o por horas ("Operativa" OP, 3 h por
--    defecto) con hora límite para avisos.

BEGIN;

-- 1. Renombrar tablas al dominio Hostelería --------------------------------
ALTER TABLE IF EXISTS pos_habitaciones RENAME TO habitaciones;
ALTER TABLE IF EXISTS pos_tipos_habitacion RENAME TO tipos_habitacion;

-- 2. Estado operativo de la habitación -------------------------------------
ALTER TABLE habitaciones
    ADD COLUMN IF NOT EXISTS estado TEXT NOT NULL DEFAULT 'libre',
    ADD COLUMN IF NOT EXISTS estado_notas TEXT,
    ADD COLUMN IF NOT EXISTS estado_actualizado_en TIMESTAMPTZ;

DO $$ BEGIN
    ALTER TABLE habitaciones ADD CONSTRAINT habitaciones_estado_check
        CHECK (estado IN ('libre', 'aseo', 'mantenimiento'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. Modalidad y hora límite en las reservas -------------------------------
ALTER TABLE hosteleria_reservas
    ADD COLUMN IF NOT EXISTS modalidad TEXT NOT NULL DEFAULT 'noche',
    ADD COLUMN IF NOT EXISTS bloque_horas INTEGER,
    ADD COLUMN IF NOT EXISTS hora_limite TIMESTAMPTZ;

DO $$ BEGIN
    ALTER TABLE hosteleria_reservas ADD CONSTRAINT hosteleria_reservas_modalidad_check
        CHECK (modalidad IN ('noche', 'horas'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_habitaciones_estado ON habitaciones (estado);

COMMIT;
