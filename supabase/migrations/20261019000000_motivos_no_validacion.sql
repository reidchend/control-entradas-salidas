-- Motivos de no validación de entradas pendientes (Validación de Entradas).
--
-- 1) movimientos.motivo_no_validacion: nota del usuario con el motivo por el
--    que la entrada pendiente todavía no se valida. Se limpia sola al
--    vincular la entrada a su factura.
--    Espejo obligatorio en movimientos_archivo: `archivarMovimientos` copia
--    la fila completa (SELECT * -> upsert), así que ambas tablas deben
--    tener las mismas columnas si no el archivado revienta.
-- 2) motivos_no_validacion: catálogo de motivos frecuentes para elegirlos
--    con un toque; el usuario también puede escribir el motivo a mano.
--
-- Correr como postgres (owner) en localhost:5432/control_entradas: el archivo
-- es DDL y el rol de la app (control_app) solo hace DML, no puede alterar
-- tablas. Los GRANT de abajo dejan a control_app con los mismos permisos que
-- el resto de las tablas (patron "postgres duena, control_app recibe GRANT").

ALTER TABLE movimientos
  ADD COLUMN IF NOT EXISTS motivo_no_validacion TEXT;

COMMENT ON COLUMN movimientos.motivo_no_validacion IS
  'Motivo por el que la entrada pendiente aun no se ha validado. Se limpia al vincular la factura.';

ALTER TABLE movimientos_archivo
  ADD COLUMN IF NOT EXISTS motivo_no_validacion TEXT;

COMMENT ON COLUMN movimientos_archivo.motivo_no_validacion IS
  'Espejo de movimientos.motivo_no_validacion al archivar.';

CREATE TABLE IF NOT EXISTS motivos_no_validacion (
  id         SERIAL PRIMARY KEY,
  texto      TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE motivos_no_validacion IS
  'Motivos frecuentes de no validacion, elegibles con un toque desde la pantalla de Validacion.';

-- Mismo motivo con distinta capitalizacion no debe repetirse.
CREATE UNIQUE INDEX IF NOT EXISTS motivos_no_validacion_texto_unico
  ON motivos_no_validacion (lower(texto));

GRANT ALL ON TABLE motivos_no_validacion TO control_app;
GRANT USAGE, SELECT ON SEQUENCE motivos_no_validacion_id_seq TO control_app;
