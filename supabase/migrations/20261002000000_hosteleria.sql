-- =====================================================================
-- Migración: módulo Lycoris Hostelería (huéspedes + reservas)
-- =====================================================================
-- Habitaciones: se reutilizan las de `pos_habitaciones` (las que ya usa el
-- POS). Hostelería agrega sus tablas propias:
--   - hosteleria_huespedes: datos del huésped (persona).
--   - hosteleria_reservas: una reserva/estancia vincula a un huésped con una
--     habitación POS + fechas + estado.
-- Estado de reserva (`estado`):
--   reservada  -> con reserva previa, sin ocupar aún
--   ocupada    -> check-in hecho (huésped en habitación)
--   cancelada  -> reserva anulada
--   finalizada -> check-out (habitación liberada)
-- Los vínculos futuros con ventas POS agregarán columnas
-- (p.ej. factura/consumo) sin romper esta base.

BEGIN;

-- 1. Huéspedes
CREATE TABLE IF NOT EXISTS hosteleria_huespedes (
    id         SERIAL PRIMARY KEY,
    nombre     TEXT NOT NULL,
    cedula     TEXT,
    telefono   TEXT,
    correo     TEXT,
    notas      TEXT,
    creado_en  TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_hosteleria_huespedes_updated_at ON hosteleria_huespedes;
CREATE TRIGGER trg_hosteleria_huespedes_updated_at
    BEFORE INSERT OR UPDATE ON hosteleria_huespedes
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

-- 2. Reservas / estancias
CREATE TABLE IF NOT EXISTS hosteleria_reservas (
    id            SERIAL PRIMARY KEY,
    habitacion_id INTEGER NOT NULL REFERENCES pos_habitaciones(id) ON DELETE CASCADE,
    huesped_id    INTEGER NOT NULL REFERENCES hosteleria_huespedes(id) ON DELETE CASCADE,
    fecha_inicio  DATE NOT NULL,
    fecha_fin     DATE NOT NULL,
    estado        TEXT NOT NULL DEFAULT 'reservada'
        CHECK (estado IN ('reservada', 'ocupada', 'cancelada', 'finalizada')),
    notas         TEXT,
    creado_en     TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_hosteleria_reservas_updated_at ON hosteleria_reservas;
CREATE TRIGGER trg_hosteleria_reservas_updated_at
    BEFORE INSERT OR UPDATE ON hosteleria_reservas
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

CREATE INDEX IF NOT EXISTS idx_hosteleria_reservas_habitacion
    ON hosteleria_reservas (habitacion_id);
CREATE INDEX IF NOT EXISTS idx_hosteleria_reservas_estado
    ON hosteleria_reservas (estado);

COMMIT;