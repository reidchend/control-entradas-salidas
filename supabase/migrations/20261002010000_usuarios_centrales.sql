-- =====================================================================
-- Migración: usuarios centralizados
-- =====================================================================
-- Unifica los dos sistemas de usuarios que existían:
--   - pos_usuarios        (POS: PIN sha256, es_admin/es_desarrollador)
--   - dispositivo_usuario (inventario: PIN texto plano, atado al equipo)
--
-- Queda un directorio central `usuarios` con:
--   - nivel global: basico | admin | desarrollador
--   - usuario_modulos: a qué apps entra (inventario | pos | hosteleria)
--   - usuario_dispositivos: auto-login de equipos fijos (antes dispositivo_usuario)
--
-- El renombre pos_usuarios -> usuarios conserva los ids, así que las FKs de
-- pos_sesiones/pos_cierres/pos_ventas siguen válidas.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Directorio central ------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.pos_usuarios') IS NOT NULL
     AND to_regclass('public.usuarios') IS NULL THEN
    ALTER TABLE pos_usuarios RENAME TO usuarios;
  END IF;
END $$;

-- Nivel global de privilegios.
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS nivel TEXT NOT NULL DEFAULT 'basico';

-- Backfill desde las banderas viejas (si todavía existen).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'usuarios' AND column_name = 'es_desarrollador'
  ) THEN
    UPDATE usuarios SET nivel = 'desarrollador' WHERE es_desarrollador = 1;
    UPDATE usuarios SET nivel = 'admin'
     WHERE nivel = 'basico' AND es_admin = 1;
  END IF;
END $$;

-- Las banderas viejas se reemplazan por `nivel`.
ALTER TABLE usuarios DROP COLUMN IF EXISTS es_admin;
ALTER TABLE usuarios DROP COLUMN IF EXISTS es_desarrollador;

-- 2. Membresías por módulo ---------------------------------------------------
CREATE TABLE IF NOT EXISTS usuario_modulos (
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    modulo     TEXT NOT NULL,
    PRIMARY KEY (usuario_id, modulo)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_usuario_modulos_modulo'
  ) THEN
    ALTER TABLE usuario_modulos
      ADD CONSTRAINT chk_usuario_modulos_modulo
      CHECK (modulo IN ('inventario', 'pos', 'hosteleria'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_usuario_modulos_modulo
    ON usuario_modulos (modulo);

-- 3. Equipos vinculados (auto-login) -----------------------------------------
CREATE TABLE IF NOT EXISTS usuario_dispositivos (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id     INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    device_id      TEXT,
    configurado_en TIMESTAMPTZ DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_usuario_dispositivos_usuario_device
    ON usuario_dispositivos (usuario_id, device_id);
CREATE INDEX IF NOT EXISTS idx_usuario_dispositivos_device
    ON usuario_dispositivos (device_id);

-- 4. Sembrar membresías de los usuarios POS existentes -----------------------
INSERT INTO usuario_modulos (usuario_id, modulo)
SELECT id, 'pos' FROM usuarios
ON CONFLICT DO NOTHING;

-- El desarrollador entra a todos los módulos.
INSERT INTO usuario_modulos (usuario_id, modulo)
SELECT id, m
FROM usuarios
CROSS JOIN (VALUES ('inventario'), ('pos'), ('hosteleria')) AS t(m)
WHERE nivel = 'desarrollador'
ON CONFLICT DO NOTHING;

-- 5. Migrar dispositivo_usuario -> usuarios + usuario_modulos + dispositivos --
DO $$
DECLARE
  r     RECORD;
  uid   INTEGER;
  v_pin TEXT;
BEGIN
  IF to_regclass('public.dispositivo_usuario') IS NULL THEN
    RETURN;
  END IF;

  FOR r IN
    SELECT
      LOWER(TRIM(nombre)) AS clave,
      MIN(nombre)         AS nombre,
      MIN(pin_hash)       AS pin,
      ARRAY_AGG(DISTINCT device_id)
        FILTER (WHERE device_id IS NOT NULL) AS devices
    FROM dispositivo_usuario
    GROUP BY LOWER(TRIM(nombre))
  LOOP
    SELECT id INTO uid FROM usuarios
     WHERE LOWER(TRIM(nombre)) = r.clave
     ORDER BY id LIMIT 1;

    IF uid IS NULL THEN
      v_pin := CASE
        WHEN r.pin IS NULL OR r.pin = '' THEN NULL
        ELSE encode(digest(r.pin, 'sha256'), 'hex')
      END;
      INSERT INTO usuarios (nombre, pin_hash, nivel, activo, creado_en)
      VALUES (r.nombre, v_pin, 'basico', 1, now()::text)
      RETURNING id INTO uid;
    END IF;

    INSERT INTO usuario_modulos (usuario_id, modulo)
    VALUES (uid, 'inventario')
    ON CONFLICT DO NOTHING;

    IF r.devices IS NOT NULL THEN
      INSERT INTO usuario_dispositivos (usuario_id, device_id, configurado_en)
      SELECT uid, d, now() FROM unnest(r.devices) AS d
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END $$;

-- `dispositivo_usuario` queda deprecada (ya migrada). No se borra para poder
-- contrastar datos; el código nuevo ya no la usa.

COMMIT;
