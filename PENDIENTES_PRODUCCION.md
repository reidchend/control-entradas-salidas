# Pendientes de migracion - produccion

## Como usar
1. Aplica el pendiente con una conexion **a la base master con permisos de propietario** (usuario `postgres`). El rol de la app (`control_app`) solo hace DML: **no puede alterar tablas**.
2. Al completar el pendiente, marcalo como completado abajo. Cuando no quede ninguno pendiente, borra tambien este archivo.

## Contexto
- La base esta en PostgreSQL local (ya no en Neon). La app se conecta con `control_app` via proxy; los DDL corren como `postgres`.

---

## Pendientes

_(ninguno pendiente)_

---

## Completados

### [x] Categorias de platos anidadas — aplicado
- **Fecha:** 2026-10-16
- **Migracion:** `supabase/migrations/20261016120000_platos_categorias_anidado.sql`
- **Ejecutado con:** `psql` v18.6 como `postgres` en `localhost:5432/control_entradas`.
- **Resultado:** `ALTER TABLE`, constraint FK (`platos_categorias_plato_categoria_padre_id_fkey`, ON DELETE SET NULL) e indice `idx_platos_categorias_plato_padre` creados.
- **Verificado:** columna `platos_categorias.plato_categoria_padre_id` existe e indice existe (`ok_col=t, ok_idx=t`).
- Habilita sub-categorias dentro de una categoria de platos en el POS.
