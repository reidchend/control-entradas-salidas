-- =====================================================================
-- Migración: hashear los PIN en texto plano de `dispositivo_usuario`
-- =====================================================================
-- Contexto:
--
-- `dispositivo_usuario` quedó deprecada en 20261002010000_usuarios_centrales.sql:
-- sus datos se migraron a `usuarios` (con el PIN ya hasheado) y a
-- `usuario_dispositivos`. El código nuevo ya no la lee: el único archivo de
-- lib/ que la nombraba era `device_id_service.dart`, y solo en un comentario.
-- Se conservaba, según el comentario de aquella migración, "para poder
-- contrastar datos".
--
-- El problema es el PIN: ahí está en texto plano, y son credenciales reales de
-- operarios. Mientras la tabla exista, un dump de la base (los respaldos de
-- tool/respaldos/) lleva los PIN legibles. Hashearlos en el lugar los vuelve
-- ilegibles como credencial.
--
-- Por qué hashear y no borrar:
--
--   - No se pierde nada. La fila, el nombre y el `device_id` siguen ahí, así
--     que el contraste de datos que justificaba conservar la tabla sigue
--     sirviendo. Con un DROP ese contraste desaparece.
--   - Todavía hay operadores en esta tabla que NO están en `usuarios`
--     (`tool/verificar_legacy_dispositivo.py` los detaila uno por uno:
--     "desarrollador web" y "Reidched" no existen en el directorio central, y
--     "desarrollador" existe pero sin pin_hash). Borrar ahora perdería sus PIN
--     para siempre, y son justo los que hay que revisar antes de decidir.
--
-- El hash es el mismo que usa `usuarios.pin_hash`
-- (encode(digest(pin, 'sha256'), 'hex')), asi que los dos lados se pueden
-- comparar con `=` y dan igual: sirve para contrastar sin poder leer el PIN.

BEGIN;

-- pgcrypto hace falta para digest(). Ya la creaba 20261002010000, pero esta
-- migracion se podria aplicar sola, y sin la extension aborta en el UPDATE.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  n INT;
BEGIN
  IF to_regclass('public.dispositivo_usuario') IS NULL THEN
    RAISE NOTICE 'dispositivo_usuario no existe: nada que hashear';
    RETURN;
  END IF;

  -- Solo filas cuyo pin_hash no sea ya un sha256. Un sha256 son 64 caracteres
  -- hex en minuscula; un PIN de 4 digitos nunca entra en ese patron, asi que
  -- la condicion no deja pasar ningun PIN sin hashear y hace la migracion
  -- idempotente (aplicarla dos veces no cambia nada).
  UPDATE dispositivo_usuario
     SET pin_hash = encode(digest(pin_hash, 'sha256'), 'hex')
   WHERE pin_hash IS NOT NULL
     AND pin_hash <> ''
     AND pin_hash !~ '^[0-9a-f]{64}$';

  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'dispositivo_usuario: % fila(s) con PIN en texto plano hasheada(s)', n;
END $$;

COMMIT;

-- Verificar despues:
--   SELECT count(*) FROM dispositivo_usuario
--    WHERE pin_hash IS NOT NULL AND pin_hash <> ''
--      AND pin_hash !~ '^[0-9a-f]{64}$';   -- debe dar 0