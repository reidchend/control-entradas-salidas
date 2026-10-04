-- =====================================================================
-- Movimientos: separar la fecha de negocio de la fecha de registro
-- =====================================================================
-- Los traslados de una requisicion se fechaban con DateTime.now() al
-- TOTALIZAR, no al crearla (requisiciones_repository.dart, totalizarRequisicion).
-- Si la requisicion se totaliza dias despues, el traslado aparecia en el
-- historial de stock con la fecha del dia en que se totalizo, no el dia en
-- que se movio la mercancia. Ejemplo: REQ-20260928150024 se creo el 28/09 y
-- se totalizo el 02/10, asi que sus traslados quedaron con fecha 02/10.
--
-- No se puede simplemente cambiar fecha_movimiento, porque hace doble trabajo:
-- ademas de fecha de negocio, es el CURSOR del recalculo de stock
-- (configuracion_repository.dart:266), que por cada producto/almacen toma el
-- movimiento mas reciente por fecha y se cree su cantidad_nueva. Esa cadena
-- cantidad_anterior -> cantidad_nueva se arma al insertar, asi que solo es
-- valida en orden de insercion, que hoy coincide con el orden por fecha
-- precisamente porque fecha_movimiento = now().
--
-- Por eso se agrega fecha_traslado: la fecha en que se pidio el traslado.
-- Las vistas de historial la pintan y ordenan con
-- COALESCE(fecha_traslado, fecha_movimiento). El recalculo sigue usando
-- fecha_movimiento, que queda intacto.
--
-- Nada se pierde: requisiciones.fecha_procesamiento sigue guardando cuando se
-- totalizo, que es el dato de auditoria del operador.
--
-- fecha_traslado es NULL en ventas, ajustes y produccion: esos si ocurren
-- cuando se registran. Solo los traslados tienen fecha de negocio propia.
-- -----------------------------------------------------------------------------

ALTER TABLE movimientos
    ADD COLUMN IF NOT EXISTS fecha_traslado TIMESTAMPTZ;

-- El archivado copia la fila completa con upsertById, asi que la columna
-- tiene que existir en las dos tablas o archivarMovimientos() revienta.
ALTER TABLE movimientos_archivo
    ADD COLUMN IF NOT EXISTS fecha_traslado TIMESTAMPTZ;

COMMENT ON COLUMN movimientos.fecha_traslado IS
    'Fecha de negocio del traslado: fecha_creacion de su requisicion. NULL para ventas, ajustes y produccion. Las vistas de historial usan COALESCE(fecha_traslado, fecha_movimiento). NO usarla como cursor de orden para el recalculo de stock: ese va por fecha_movimiento, porque la cadena cantidad_anterior -> cantidad_nueva solo es valida en orden de insercion.';

COMMENT ON COLUMN movimientos_archivo.fecha_traslado IS
    'Espejo de movimientos.fecha_traslado al archivar.';

-- -----------------------------------------------------------------------------
-- Relleno del historico
-- -----------------------------------------------------------------------------
-- Solo las requisiciones cuyo traslado quedo en OTRO DIA CALENDARIO del que se
-- creo. Son 10 requisiciones y 628 movimientos.
--
-- El filtro es por dia calendario, no por intervalo: un traslado del 28/09 a
-- las 08:00 totalizado el 29/09 a las 07:00 son 23 horas (EXTRACT(DAY) = 0)
-- pero cae en otro dia, y en el historial se ve en el dia equivocado.
--
-- Las otras 2.270 filas con requisicion_id se dejan en NULL a proposito: su
-- traslado quedo el mismo dia en que se creo, asi que
-- COALESCE(fecha_traslado, fecha_movimiento) devuelve la misma fecha que
-- muestra hoy y la historia no se reordena. Rellenarlas tambien seria
-- coherente, pero mezclaria en una misma lista de historial traslados
-- ordenados por un criterio y otros por otro, y reordenaria el intra-dia.
UPDATE movimientos m
   SET fecha_traslado = r.fecha_creacion
  FROM requisiciones r
 WHERE r.id = m.requisicion_id
   AND r.fecha_creacion IS NOT NULL
   AND m.fecha_movimiento::date <> r.fecha_creacion::date
   AND m.fecha_traslado IS DISTINCT FROM r.fecha_creacion;
