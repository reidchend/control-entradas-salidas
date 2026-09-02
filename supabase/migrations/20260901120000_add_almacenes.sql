-- =====================================================================
-- Migración: catálogo de almacenes
-- =====================================================================
-- Los almacenes ya no son strings libres dentro de existencias/movimientos:
-- pasan a tener su propia tabla (CRUD desde Configuración → Sistema).
-- El seed registra los almacenes que existen hoy en la BD.

CREATE TABLE IF NOT EXISTS almacenes (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(50) NOT NULL UNIQUE,
    descripcion TEXT,
    activo      BOOLEAN DEFAULT TRUE,
    orden       INTEGER DEFAULT 0,
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- Seed con los almacenes presentes en los datos actuales.
INSERT INTO almacenes (nombre, descripcion, activo, orden) VALUES
    ('principal', 'Almacén principal: existencias sin uso', TRUE, 1),
    ('restaurante', 'Almacén de consumo y operación', TRUE, 2)
ON CONFLICT (nombre) DO NOTHING;