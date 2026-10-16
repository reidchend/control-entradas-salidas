# Pendientes de migracion - produccion

## Como usar
1. Aplica el pendiente con una conexion **a la base master con permisos de propietario** (usuario `postgres`). El rol de la app (`control_app`) solo hace DML: **no puede alterar tablas**.
2. Al completar el pendiente, **borralo de esta lista**. Cuando no quede ninguno, borra tambien este archivo.

## Contexto
- La base esta en PostgreSQL local (ya no en Neon). La app se conecta con `control_app` via proxy; los DDL corren como `postgres`.
- Este pendiente habilita **categorias de platos anidadas** en el POS: dentro de una categoria de platos (ej. DESAYUNOS) se podran crear sub-categorias. El codigo ya lo usa; **sin esta columna los sub-menus no cargan y guardar una sub-categoria falla**.

## Ordenes basicas
```bash
# Linux (en el servidor o con psql instalado)
DATABASE_URL_MASTER="postgresql://postgres:TU_CONTRASENA@localhost:5432/NOMBRE_BD"
psql "$DATABASE_URL_MASTER" -f supabase/migrations/20261016120000_platos_categorias_anidado.sql
# Windows (PowerShell)
psql -h localhost -U postgres -d NOMBRE_BD -f supabase\migrations\20261016120000_platos_categorias_anidado.sql
```

---

## Pendiente 1 - Categorias de platos anidadas
- [ ] `supabase/migrations/20261016120000_platos_categorias_anidado.sql`

**Que hace:** agrega `platos_categorias.plato_categoria_padre_id` (FK a la propia tabla, `ON DELETE SET NULL`) + indice. Permite que una categoria de platos cuelgue de otra.

**Aplicar:**
```bash
psql "$DATABASE_URL_MASTER" -f supabase/migrations/20261016120000_platos_categorias_anidado.sql
```

**Verificar:**
```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'platos_categorias' AND column_name = 'plato_categoria_padre_id';
SELECT indexname FROM pg_indexes WHERE indexname = 'idx_platos_categorias_plato_padre';
```
Debe devolver una fila en cada consulta.

**Importante:** la app (POS) espera esta columna. Desplegar/aplicar el DDL **antes** de publicar la version del POS que usa sub-categorias anidadas.
