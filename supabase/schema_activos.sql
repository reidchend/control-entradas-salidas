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
-- NOTA: esta base es local y no usa RLS (en Neon el acceso va por el proxy
-- con usuario de servicio). Las políticas RLS de `schema.sql` son inertes
-- sin `supabase` en el search_path, pero se conservan por portabilidad.

BEGIN;

-- ---------------------------------------------------------------------
-- Categorías
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activos_categorias (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    color       VARCHAR(20) DEFAULT '#2196F3',
    activo      BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT now(),
    updated_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_categorias_nombre
    ON activos_categorias (lower(nombre));

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
    valor         DOUBLE PRECISION,
    fecha         DATE,
    observaciones TEXT,
    activo        BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_activos_tipo_id ON activos (tipo_id);
CREATE INDEX IF NOT EXISTS idx_activos_ubicacion ON activos (ubicacion);
CREATE INDEX IF NOT EXISTS idx_activos_activo ON activos (activo);

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
