-- =====================================================================
-- Esquema de Activos — catálogo de tipos + unidades individuales
-- =====================================================================
-- Complementa `supabase/schema.sql`, que no incluye estas tablas (se habían
-- creado directamente en la base). Al bootstrap de una base local hay que
-- correr los dos archivos, en este orden:
--
--   psql -d control_entradas -f supabase/schema.sql
--   psql -d control_entradas -f supabase/schema_activos.sql
--
-- Estructura de dos niveles:
--   - activos_categorias: categorías de activos (TV, Mobiliario...).
--   - activos_tipos: catálogo maestro. Centraliza la identidad del bien
--     (nombre + grupo + modelo + categoría) para que agregar existencias no
--     genere nombres inconsistentes.
--   - activos: una fila por unidad física y ubicación, con tipo_id al tipo.
--
-- Idempotente: seguro de ejecutarlo sobre una base ya migrada.
--
-- NOTA: esta base es local y no usa RLS (el acceso va por el proxy o por
-- conexión directa con usuario de servicio). Las políticas RLS de `schema.sql`
-- son inertes sin `supabase` en el search_path, pero se conservan por
-- portabilidad.

BEGIN;

-- ---------------------------------------------------------------------
-- Categorías
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activos_categorias (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    color       VARCHAR(20) DEFAULT '#2196F3',
    prefijo     VARCHAR(8),
    activo      BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT now(),
    updated_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_categorias_nombre
    ON activos_categorias (lower(nombre));

-- ---------------------------------------------------------------------
-- Catálogo de estados (dimensión de las unidades)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activos_estados (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(50) NOT NULL,
    color       VARCHAR(20),
    orden       INTEGER NOT NULL DEFAULT 0,
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT now(),
    updated_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_estados_nombre
    ON activos_estados (lower(nombre));

-- Índice exacto: backing de la FK de `activos.estado`.
CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_estados_nombre_exacto
    ON activos_estados (nombre);

INSERT INTO activos_estados (nombre, color, orden)
SELECT s.nombre, s.color, s.orden
FROM (VALUES
    ('Activo',        '#4CAF50', 0),
    ('Mantenimiento', '#FF9800', 1),
    ('Baja',          '#F44336', 2),
    ('Reservado',     '#2196F3', 3),
    ('Traslado',      '#9C27B0', 4)
) AS s(nombre, color, orden)
WHERE NOT EXISTS (
    SELECT 1 FROM activos_estados e
    WHERE lower(e.nombre) = lower(s.nombre)
);

-- ---------------------------------------------------------------------
-- Contador de códigos de inventario por prefijo
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activos_codigos (
    prefijo     VARCHAR(8) PRIMARY KEY,
    ultimo      INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMPTZ
);

-- ---------------------------------------------------------------------
-- Catálogo de tipos (nivel 1)
-- ---------------------------------------------------------------------
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

CREATE INDEX IF NOT EXISTS idx_activos_tipos_categoria
    ON activos_tipos (categoria_id);

-- Un tipo no se duplica dentro de su categoría: la unicidad ignora mayúsculas
-- y valores vacíos, que se normalizan a NULL en la app.
CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_tipos_identidad
    ON activos_tipos (
        lower(nombre),
        COALESCE(lower(grupo), ''),
        COALESCE(lower(modelo), ''),
        COALESCE(categoria_id, -1)
    );

-- ---------------------------------------------------------------------
-- Unidades físicas (nivel 2)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activos (
    id            SERIAL PRIMARY KEY,
    tipo_id       INTEGER NOT NULL REFERENCES activos_tipos(id) ON DELETE RESTRICT,
    ubicacion     VARCHAR(150),
    estado        VARCHAR(50) DEFAULT 'Activo',
    codigo        TEXT,
    valor         DOUBLE PRECISION,
    fecha         DATE,
    observaciones TEXT,
    activo        BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ
);

-- La placa es única por unidad; se asigna con prefijo de la categoría
-- (formato 'PREFIJO-NNNNN'), ver `prefijo_de_categoria()` en la migración.
CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_codigo ON activos (codigo);
CREATE INDEX IF NOT EXISTS idx_activos_tipo_id ON activos (tipo_id);
CREATE INDEX IF NOT EXISTS idx_activos_ubicacion ON activos (ubicacion);
CREATE INDEX IF NOT EXISTS idx_activos_estado ON activos (estado);
CREATE INDEX IF NOT EXISTS idx_activos_activo ON activos (activo);

-- El estado de una unidad vive en el catálogo `activos_estados`: renombrar el
-- estado en el catálogo aplica por cascada a las unidades.
ALTER TABLE activos DROP CONSTRAINT IF EXISTS fk_activos_estado_nombre;
ALTER TABLE activos ADD CONSTRAINT fk_activos_estado_nombre
    FOREIGN KEY (estado) REFERENCES activos_estados(nombre)
    ON UPDATE CASCADE ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- Triggers de updated_at
-- Reutilizan set_pos_updated_at() de schema.sql; si este archivo se corre
-- standalone (sin schema.sql antes), se usa el fallback local.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_activos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    fn TEXT;
BEGIN
    IF to_regprocedure('set_pos_updated_at()') IS NOT NULL THEN
        fn := 'set_pos_updated_at';
    ELSE
        fn := 'set_activos_updated_at';
    END IF;

    EXECUTE 'DROP TRIGGER IF EXISTS trg_activos_categorias_updated_at ON activos_categorias';
    EXECUTE format('CREATE TRIGGER trg_activos_categorias_updated_at
        BEFORE INSERT OR UPDATE ON activos_categorias
        FOR EACH ROW EXECUTE FUNCTION %s()', fn);

    EXECUTE 'DROP TRIGGER IF EXISTS trg_activos_estados_updated_at ON activos_estados';
    EXECUTE format('CREATE TRIGGER trg_activos_estados_updated_at
        BEFORE INSERT OR UPDATE ON activos_estados
        FOR EACH ROW EXECUTE FUNCTION %s()', fn);

    EXECUTE 'DROP TRIGGER IF EXISTS trg_activos_codigos_updated_at ON activos_codigos';
    EXECUTE format('CREATE TRIGGER trg_activos_codigos_updated_at
        BEFORE INSERT OR UPDATE ON activos_codigos
        FOR EACH ROW EXECUTE FUNCTION %s()', fn);

    EXECUTE 'DROP TRIGGER IF EXISTS trg_activos_tipos_updated_at ON activos_tipos';
    EXECUTE format('CREATE TRIGGER trg_activos_tipos_updated_at
        BEFORE INSERT OR UPDATE ON activos_tipos
        FOR EACH ROW EXECUTE FUNCTION %s()', fn);

    EXECUTE 'DROP TRIGGER IF EXISTS trg_activos_updated_at ON activos';
    EXECUTE format('CREATE TRIGGER trg_activos_updated_at
        BEFORE INSERT OR UPDATE ON activos
        FOR EACH ROW EXECUTE FUNCTION %s()', fn);
END $$;

COMMIT;
