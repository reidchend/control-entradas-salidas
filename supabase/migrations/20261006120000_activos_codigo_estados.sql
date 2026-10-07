-- =====================================================================
-- Migración: código de inventario + estados de catálogo en Activos
-- =====================================================================
-- 1. activos_estados: catálogo de estados. `activos.estado` pasa a ser una
--    FK al catálogo (renombrar un estado aplica por cascada a las unidades).
-- 2. activos_categorias.prefijo: prefijo de la placa (ej: 'TELE').
-- 3. activos_codigos: contador atómico por prefijo.
-- 4. activos.codigo: placa única por unidad, formato '<PREFIJO>-NNNNN',
--    asignada por la app al insertar (el backfill deja numerados los
--    activos existentes en orden estable).

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Estados de catálogo
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activos_estados (
    id         SERIAL PRIMARY KEY,
    nombre     VARCHAR(50) NOT NULL,
    color      VARCHAR(20),
    orden      INTEGER NOT NULL DEFAULT 0,
    activo     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_estados_nombre
    ON activos_estados (lower(nombre));

DROP TRIGGER IF EXISTS trg_activos_estados_updated_at ON activos_estados;
CREATE TRIGGER trg_activos_estados_updated_at
    BEFORE INSERT OR UPDATE ON activos_estados
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

-- Estados por defecto (solo si no existen todavía).
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

-- Estados que ya existen en los datos: se preservan todos, sin inventario
-- de que la app los conozca (vienen de importaciones o usos anteriores).
INSERT INTO activos_estados (nombre, orden)
SELECT DISTINCT a.estado, 100
FROM activos a
WHERE COALESCE(a.estado, '') <> ''
  AND NOT EXISTS (
      SELECT 1 FROM activos_estados e
      WHERE lower(e.nombre) = lower(a.estado)
  );

-- Los datos pudieron cargar 'Activo' y 'activo' como estados distintos.
-- Antes de la FK se colapsan las variantes (queda la de menor id) para que el
-- catálogo sea único por nombre, sin importar mayúsculas.
UPDATE activos a
SET estado = e.nombre
FROM activos_estados d
JOIN activos_estados e ON lower(e.nombre) = lower(d.nombre) AND e.id < d.id
WHERE a.estado = d.nombre;

DELETE FROM activos_estados d
USING activos_estados e
WHERE lower(e.nombre) = lower(d.nombre) AND e.id < d.id;

-- Vuelve a estado por defecto las unidades sin estado (la FK no aceptaría
-- valores ajenos al catálogo).
UPDATE activos SET estado = 'Activo'
WHERE estado IS NULL OR estado = '';

-- Índice unique exacto: la FK solo puede referenciar una columna cubierta por
-- un índice unique no-expresión; `idx_activos_estados_nombre` es sobre
-- `lower(nombre)` y no sirve de backing.
CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_estados_nombre_exacto
    ON activos_estados (nombre);

ALTER TABLE activos DROP CONSTRAINT IF EXISTS fk_activos_estado_nombre;
ALTER TABLE activos ADD CONSTRAINT fk_activos_estado_nombre
    FOREIGN KEY (estado) REFERENCES activos_estados(nombre)
    ON UPDATE CASCADE ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_activos_estado ON activos (estado);

-- ---------------------------------------------------------------------
-- 2. Prefijo por categoría
-- ---------------------------------------------------------------------
ALTER TABLE activos_categorias ADD COLUMN IF NOT EXISTS prefijo VARCHAR(8);

CREATE OR REPLACE FUNCTION prefijo_de_categoria(nombre TEXT, prefijo_guardado TEXT)
RETURNS TEXT AS $$
DECLARE
    limpio   TEXT;
    palabras TEXT[];
    resultado TEXT := '';
    p        TEXT;
    n        INT := 0;
BEGIN
    -- Un prefijo ya guardado gana: la placa no cambia aunque se renombre la
    -- categoría.
    IF prefijo_guardado IS NOT NULL AND length(prefijo_guardado) >= 2 THEN
        RETURN upper(prefijo_guardado);
    END IF;

    limpio := upper(regexp_replace(coalesce(nombre, ''), '[^A-Za-z0-9 ]', '', 'g'));
    palabras := string_to_array(limpio, ' ');

    FOR p IN SELECT unnest(palabras) LOOP
        IF n >= 3 THEN EXIT; END IF;
        IF length(p) = 0 THEN CONTINUE; END IF;
        resultado := resultado || left(p, 1);
        n := n + 1;
    END LOOP;

    IF length(resultado) >= 2 THEN
        RETURN resultado;
    END IF;
    IF length(limpio) >= 2 THEN
        RETURN left(limpio, 4);
    END IF;
    RETURN 'ACT';
END;
$$ LANGUAGE plpgsql;

UPDATE activos_categorias
SET prefijo = prefijo_de_categoria(nombre, prefijo)
WHERE prefijo IS NULL OR prefijo = '';

-- ---------------------------------------------------------------------
-- 3. Contador de códigos por prefijo
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activos_codigos (
    prefijo VARCHAR(8) PRIMARY KEY,
    ultimo  INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ
);

-- ---------------------------------------------------------------------
-- 4. Código de inventario en las unidades
-- ---------------------------------------------------------------------
ALTER TABLE activos ADD COLUMN IF NOT EXISTS codigo TEXT;

-- Backfill: numeración estable, por prefijo de categoría y luego por id.
DO $$
DECLARE
    fila   RECORD;
    actual TEXT := '';
    cont   INTEGER;
BEGIN
    FOR fila IN
        SELECT a.id,
               COALESCE(NULLIF(c.prefijo, ''), 'ACT') AS pref
        FROM activos a
        JOIN activos_tipos t ON t.id = a.tipo_id
        LEFT JOIN activos_categorias c ON c.id = t.categoria_id
        ORDER BY COALESCE(NULLIF(c.prefijo, ''), 'ACT'), a.id
    LOOP
        IF fila.pref <> actual OR actual = '' THEN
            actual := fila.pref;
            cont := COALESCE(
                (SELECT ultimo FROM activos_codigos WHERE prefijo = actual),
                0
            );
        END IF;
        cont := cont + 1;
        UPDATE activos a
        SET codigo = actual || '-' || lpad(cont::text, 5, '0')
        WHERE a.id = fila.id;
        INSERT INTO activos_codigos (prefijo, ultimo)
        VALUES (actual, cont)
        ON CONFLICT (prefijo) DO UPDATE SET ultimo = EXCLUDED.ultimo;
    END LOOP;
END $$;

ALTER TABLE activos ALTER COLUMN codigo SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_activos_codigo ON activos (codigo);

COMMIT;