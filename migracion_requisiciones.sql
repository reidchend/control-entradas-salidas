-- =====================================================
-- MIGRACIÓN: Crear tablas de requisiciones
-- Fecha: 2026-04-01
-- =====================================================

-- Tabla: requisiciones
CREATE TABLE IF NOT EXISTS requisiciones (
    id SERIAL PRIMARY KEY,
    numero VARCHAR(50) UNIQUE NOT NULL,
    origen VARCHAR(50) NOT NULL,
    destino VARCHAR(50) NOT NULL,
    estado VARCHAR(20) DEFAULT 'pendiente',
    observaciones TEXT,
    creada_por VARCHAR(100),
    procesada_por VARCHAR(100),
    fecha_procesamiento TIMESTAMPTZ,
    fecha_creacion TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    actualizada TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: requisicion_detalles
CREATE TABLE IF NOT EXISTS requisicion_detalles (
    id SERIAL PRIMARY KEY,
    requisicion_id INTEGER REFERENCES requisiciones(id) ON DELETE CASCADE,
    producto_id INTEGER REFERENCES productos(id) ON DELETE SET NULL,
    ingrediente VARCHAR(200) NOT NULL,
    cantidad FLOAT NOT NULL,
    unidad VARCHAR(50) DEFAULT 'unidad',
    cantidad_surtida FLOAT DEFAULT 0
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_requisiciones_numero ON requisiciones(numero);
CREATE INDEX IF NOT EXISTS idx_requisiciones_estado ON requisiciones(estado);
CREATE INDEX IF NOT EXISTS idx_requisiciones_fecha ON requisiciones(fecha_creacion DESC);
CREATE INDEX IF NOT EXISTS idx_requisicion_detalles_requisicion ON requisicion_detalles(requisicion_id);

-- =====================================================
-- DATOS DE EJEMPLO (opcional)
-- =====================================================

-- INSERT INTO requisiciones (numero, origen, destino, estado, creada_por)
-- VALUES ('REQ-001', 'principal', 'restaurante', 'pendiente', 'Admin');
