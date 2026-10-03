-- =====================================================================
-- Migración: check-in de Hostelería
-- =====================================================================
-- Amplía el módulo Hostelería para el registro real de huéspedes:
--   - Catálogo de tipos de habitación con capacidad máxima de personas.
--   - Datos completos del huésped (documento, nacimiento, estado civil,
--     nacionalidad, profesión, procedencia, destino).
--   - Acompañantes: cada persona es un huésped completo vinculado a la
--     estancia con rol titular/acompañante.
--   - Vehículos por estancia (placa + modelo, varios por reserva).
--   - Hora de entrada (check-in) y de salida (check-out).

BEGIN;

-- 1. Catálogo de tipos de habitación ----------------------------------------
CREATE TABLE IF NOT EXISTS pos_tipos_habitacion (
    id         SERIAL PRIMARY KEY,
    nombre     TEXT NOT NULL UNIQUE,
    capacidad  INTEGER NOT NULL DEFAULT 1,
    activo     INTEGER NOT NULL DEFAULT 1,
    creado_en  TEXT NOT NULL,
    updated_at TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_pos_tipos_habitacion_updated_at ON pos_tipos_habitacion;
CREATE TRIGGER trg_pos_tipos_habitacion_updated_at
    BEFORE INSERT OR UPDATE ON pos_tipos_habitacion
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

-- Referencia opcional de cada habitación a su tipo del catálogo.
ALTER TABLE pos_habitaciones
    ADD COLUMN IF NOT EXISTS tipo_id INTEGER
        REFERENCES pos_tipos_habitacion(id) ON DELETE SET NULL;

-- Sembrar el catálogo con los tipos ya existentes (texto libre) y enlazarlos.
INSERT INTO pos_tipos_habitacion (nombre, capacidad, activo, creado_en)
SELECT DISTINCT TRIM(tipo), 2, 1, now()::text
FROM pos_habitaciones
WHERE tipo IS NOT NULL AND TRIM(tipo) <> ''
ON CONFLICT (nombre) DO NOTHING;

UPDATE pos_habitaciones h
SET tipo_id = t.id
FROM pos_tipos_habitacion t
WHERE h.tipo_id IS NULL
  AND h.tipo IS NOT NULL
  AND TRIM(h.tipo) = t.nombre;

-- 2. Huéspedes: datos completos ------------------------------------------
ALTER TABLE hosteleria_huespedes
    ADD COLUMN IF NOT EXISTS apellido         TEXT,
    ADD COLUMN IF NOT EXISTS tipo_documento   TEXT,
    ADD COLUMN IF NOT EXISTS numero_documento TEXT,
    ADD COLUMN IF NOT EXISTS fecha_nacimiento DATE,
    ADD COLUMN IF NOT EXISTS estado_civil     TEXT,
    ADD COLUMN IF NOT EXISTS nacionalidad     TEXT,
    ADD COLUMN IF NOT EXISTS profesion        TEXT,
    ADD COLUMN IF NOT EXISTS procedencia      TEXT,
    ADD COLUMN IF NOT EXISTS destino          TEXT;

-- 3. Reservas: hora de entrada/salida ------------------------------------
ALTER TABLE hosteleria_reservas
    ADD COLUMN IF NOT EXISTS hora_entrada TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS hora_salida  TIMESTAMPTZ;

-- 4. Personas por estancia (titular + acompañantes) ----------------------
CREATE TABLE IF NOT EXISTS hosteleria_reserva_personas (
    id         SERIAL PRIMARY KEY,
    reserva_id INTEGER NOT NULL REFERENCES hosteleria_reservas(id) ON DELETE CASCADE,
    huesped_id INTEGER NOT NULL REFERENCES hosteleria_huespedes(id) ON DELETE CASCADE,
    rol        TEXT NOT NULL DEFAULT 'acompanante'
        CHECK (rol IN ('titular', 'acompanante')),
    creado_en  TIMESTAMPTZ DEFAULT now(),
    UNIQUE (reserva_id, huesped_id)
);
CREATE INDEX IF NOT EXISTS idx_hosteleria_reserva_personas_reserva
    ON hosteleria_reserva_personas (reserva_id);

-- 5. Vehículos por estancia ----------------------------------------------
CREATE TABLE IF NOT EXISTS hosteleria_vehiculos (
    id         SERIAL PRIMARY KEY,
    reserva_id INTEGER NOT NULL REFERENCES hosteleria_reservas(id) ON DELETE CASCADE,
    placa      TEXT NOT NULL,
    modelo     TEXT,
    creado_en  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hosteleria_vehiculos_reserva
    ON hosteleria_vehiculos (reserva_id);

COMMIT;
