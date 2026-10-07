# Pendientes de migración — producción

## Cómo usar
1. Aplica cada pendiente **en orden** del 1 al 2.
2. Necesitas una conexión **a la base master con permisos de propietario** (usuario `postgres`). El rol de la app (`control_app`) solo hace DML: **no puede crear tablas, índices ni restricciones** (migraciones y typo: "debe ser dueño de la tabla").
3. Al completar un pendiente, **bórralo de esta lista**. Cuando no quede ninguno, borra también este archivo.

## Contexto
- La base está en PostgreSQL local (ya no en Neon). La app se conecta con `control_app` vía proxy; los DDL corren como `postgres`.
- El 2026-10-06 se limpiaron **77 tipos duplicados** (quedan 185 tipos, 986 activos) y se normalizó la capitalización de grupos/modelos. Respaldos disponibles: `respaldo_limpieza_tipos_20261006` y `respaldo_limpieza_activos_20261006`.
- Los dos pendientes de abajo quedaron sin aplicar porque requieren ser propietario de las tablas.

## Órdenes básicas
```bash
# Linux (en el servidor o con psql instalado)
DATABASE_URL_MASTER="postgresql://postgres:TU_CONTRASENA@localhost:5432/NOMBRE_BD"
psql "$DATABASE_URL_MASTER" -f supabase/migrations/<archivo>.sql
# Windows (PowerShell)
psql -h localhost -U postgres -d NOMBRE_BD -f supabase\migrations\<archivo>.sql
```

---

## Pendiente 1 — Código de inventario + estados de catálogo
- [ ] `supabase/migrations/20261006120000_activos_codigo_estados.sql`

**Qué hace:** crea `activos_estados` (estados con color/orden), agrega `prefijo` a `activos_categorias`, crea `activos_codigos` (contador por prefijo), agrega `activos.codigo` y **backfill** numerando todos los activos existentes (`TELE-00001`, ...), y conecta `activos.estado` a una FK con `ON UPDATE CASCADE`.

**Aplicar:**
```bash
psql "$DATABASE_URL_MASTER" -f supabase/migrations/20261006120000_activos_codigo_estados.sql
```

**Verificar:**
```sql
SELECT COUNT(*) FROM activos_estados;          -- al menos 5 (Activo, Mantenimiento, ...)
SELECT COUNT(*) FROM activos WHERE codigo IS NULL;  -- debe ser 0
SELECT COUNT(*) FROM activos_codigos;          -- 1 por cada prefijo de categoría (ej: TELE, TV)
```

**Importante:** la migración deja numerados los 986 activos existentes. Las unidades nuevas reciben su placa desde la app sobre `activos_codigos`.

---

## Pendiente 2 — Tipos y categorías únicos (evita duplicados futuros)
- [ ] `supabase/migrations/20261006130000_activos_tipos_unicos.sql`

**Qué hace:** crea dos índices únicos funcionales:
- `uq_activos_tipos_cat_grupo_nombre` sobre `(categoría, grupo, nombre)` — insensible a mayúsculas y espacios. Rechaza crear otro `televisor` en `Televisores`, o volver a partir `neveras ejecutivas` / `Neveras ejecutivas`.
- `uq_activos_categorias_nombre` sobre el nombre de categoría, insensible a mayúsculas.

Es la garantía de fondo: la app ya deduplica y reutiliza la escritura canónica, pero si algo intenta insertar un duplicado, la base lo rechaza.

> Nota: si en el futuro aparece un error al guardar un tipo con mensaje tipo `duplicate key value violates unique constraint "uq_activos_tipos_cat_grupo_nombre"`, significa que el dedupe de la app no alcanzó: es la red de seguridad actuando, no un bug que corregir borrando el índice.

**Aplicar:**
```bash
psql "$DATABASE_URL_MASTER" -f supabase/migrations/20261006130000_activos_tipos_unicos.sql
```

**Verificar:**
```sql
SELECT indexname FROM pg_indexes
WHERE indexname IN ('uq_activos_tipos_cat_grupo_nombre', 'uq_activos_categorias_nombre');
```
Debe devolver las dos filas. Prueba de fuego (debe fallar con error de clave duplicada):
```sql
INSERT INTO activos_tipos (nombre, grupo) VALUES ('televisor', 'Televisores');
```

---

## Al terminar
1. Borra las casillas (`- [ ] ...`) que ya completaste.
2. Cuando no queden pendientes, borra este archivo `PENDIENTES_PRODUCCION.md`.
3. Si la app se va a desplegar después de la migración de códigos, recuerda desplegarla **después** de aplicar el Pendiente 1.