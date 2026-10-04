-- =====================================================================
-- Migración: borrar `dispositivo_usuario`
-- =====================================================================
-- La tabla quedó deprecada en 20261002010000_usuarios_centrales.sql y sus PIN
-- se hashearon en 20261004170000. Ya no la lee nadie: el único archivo de lib/
-- que la nombraba era un comentario de `device_id_service`, y
-- `tool/verificar_legacy_dispositivo.py` confirma que su información está en
-- `usuarios` + `usuario_dispositivos`.
--
-- Antes de borrarla se conservan dos cosas:
--
-- 1. El PIN de los operadores que están en `usuarios` pero llegaron sin
--    `pin_hash`. Hoy es solo "Desarrollador" (id=1), que está desactivado: el
--    PIN no habilita nada, pero tampoco se pierde.
--
-- 2. Una lista explícita de los operadores que están en esta tabla y NO en
--    `usuarios`. No es un olvido de la migración 2: se borraron a propósito,
--    y volver a crearlos sería resucitar cuentas que alguien eliminó.
--
--      - "desarrollador web" (era el id=9): aparece en el respaldo
--        pre_fusion_20261002_232338.json y hoy no está en `usuarios`. Se borró
--        junto con la limpieza del 2026-10-02. Sus dos equipos (00064367…,
--        cfdc0953…) no quedaron vinculados a nadie, que es lo que corresponde
--        si la cuenta ya no existe.
--
--      - "Reidched" (era el id=13): lo borró
--        `tool/fusionar_usuario_duplicado.py` al fusionarlo con "Reidchend"
--        (id=2), que tiene exactamente el mismo pin_hash. Es el mismo usuario
--        escrito mal, y su equipo (c287299f…) ya apunta al bueno.
--
--    El guard de abajo aborta si aparece un operador que no esté en `usuarios`
--    ni en esta lista, así que un dato nuevo nunca se pierde en silencio.
--
-- Los PIN de esta tabla ya venían hasheados desde la migración anterior: un
-- dump de la base posterior a esto no lleva credenciales de operario.

BEGIN;

-- El guard solo compara nombres, así que no necesita pgcrypto. Se repite el
-- CREATE EXTENSION para que la migración sea aplicable sola.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Los operadores que se descartan, con el motivo. Vive en la migración a
-- propósito: dentro de tres meses, cuando alguien lea esto, tiene que saber
-- que son dos cuentas borradas a mano y no dos datos que se perdieron.
CREATE TEMP TABLE _descartados (nombre TEXT PRIMARY KEY, motivo TEXT) ON COMMIT DROP;
INSERT INTO _descartados (nombre, motivo) VALUES
  ('desarrollador web', 'borrado de usuarios el 2026-10-02 (era el id=9); sus equipos quedaron sin vincular'),
  ('reidched',         'fusionado con Reidchend (id=2) por tool/fusionar_usuario_duplicado.py; mismo pin_hash');

-- 1. Conservar el PIN de los que están en `usuarios` pero llegaron sin hash.
--    `usuarios_centrales` no lo copiaba cuando la fila ya existía, así que
--    quedó a medias. Se toma una sola fila por operador (la de menor id) para
--    que el UPDATE sea determinista.
UPDATE usuarios u
   SET pin_hash = d.pin_hash
  FROM dispositivo_usuario d
 WHERE LOWER(TRIM(d.nombre)) = LOWER(TRIM(u.nombre))
   AND (u.pin_hash IS NULL OR u.pin_hash = '')
   AND d.pin_hash IS NOT NULL
   AND d.pin_hash <> ''
   AND d.id = (SELECT min(d2.id)
                 FROM dispositivo_usuario d2
                WHERE LOWER(TRIM(d2.nombre)) = LOWER(TRIM(u.nombre)));

-- 2. Guard: no se borra nada que no esté accounted for.
DO $$
DECLARE
  perdidos TEXT;
BEGIN
  IF to_regclass('public.dispositivo_usuario') IS NULL THEN
    RAISE NOTICE 'dispositivo_usuario no existe: nada que borrar';
    RETURN;
  END IF;

  SELECT string_agg(t.nombre, ', ' ORDER BY t.nombre) INTO perdidos
    FROM (SELECT min(nombre) AS nombre
            FROM dispositivo_usuario
           GROUP BY lower(trim(nombre))) t
   WHERE lower(trim(t.nombre)) NOT IN (SELECT lower(trim(nombre)) FROM usuarios)
     AND lower(trim(t.nombre)) NOT IN (SELECT nombre FROM _descartados);

  IF perdidos IS NOT NULL THEN
    RAISE EXCEPTION
      'no se borra dispositivo_usuario: estos operadores no estan en `usuarios` ni en la lista de descartados: %',
      perdidos;
  END IF;

  RAISE NOTICE 'guard ok: todos los operadores estan en `usuarios` o en la lista de descartados';
END $$;

DROP TABLE dispositivo_usuario;

COMMIT;

-- Verificar despues:
--   SELECT to_regclass('public.dispositivo_usuario');   -- debe dar NULL
--   SELECT nombre, activo, pin_hash FROM usuarios ORDER BY id;