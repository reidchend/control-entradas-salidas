# Pendientes de migracion - produccion

## Como usar
1. Aplica el pendiente con una conexion **a la base master con permisos de propietario** (usuario `postgres`). El rol de la app (`control_app`) solo hace DML: **no puede alterar tablas**.
2. Al completar el pendiente, marcalo como completado abajo. Cuando no quede ninguno pendiente, borra tambien este archivo.

## Contexto
- La base esta en PostgreSQL local (ya no en Neon). La app se conecta con `control_app` via proxy; los DDL corren como `postgres`.

---

## Pendientes

- [ ] **Motivos de no validación de entradas** (nota por entrada pendiente + catálogo de motivos frecuentes).
  - **Migracion:** `supabase/migrations/20261019000000_motivos_no_validacion.sql`
  - **Que hace:** agrega la columna `movimientos.motivo_no_validacion` (y su espejo en `movimientos_archivo`, que el archivado copia fila completa), crea la tabla `motivos_no_validacion` y da GRANT a `control_app`.
  - **Como:** correr el archivo con `psql` como `postgres` en `localhost:5432/control_entradas` (el rol `control_app` solo hace DML y no puede hacer DDL).
  - **Importante:** correrlo **antes de probar** la pantalla de Validación. Sin la migración, "Validar" sigue funcionando, pero no se pueden guardar notas y el catálogo de motivos sale vacío.

---

## Completados

### [x] Categorias de platos anidadas — aplicado
- **Fecha:** 2026-10-16
- **Migracion:** `supabase/migrations/20261016120000_platos_categorias_anidado.sql`
- **Ejecutado con:** `psql` v18.6 como `postgres` en `localhost:5432/control_entradas`.
- **Resultado:** `ALTER TABLE`, constraint FK (`platos_categorias_plato_categoria_padre_id_fkey`, ON DELETE SET NULL) e indice `idx_platos_categorias_plato_padre` creados.
- **Verificado:** columna `platos_categorias.plato_categoria_padre_id` existe e indice existe (`ok_col=t, ok_idx=t`).
- Habilita sub-categorias dentro de una categoria de platos en el POS.
