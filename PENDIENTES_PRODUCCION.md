# Pendientes de producción

**Regla obligatoria:** Requieren permisos de propietario (`postgres`), no `control_app`. No ejecutar por cuenta propia.

## Pendientes sin completar

- [ ] **Aplicar migración de turnos compartidos del POS**  
  Archivo: `supabase/migrations/20261113000000_pos_turnos_compartidos.sql`  
  **Qué hace:** agrega `pos_turno_participantes`, `pos_comandas.usuario_id`, `pos_cierres.cerrado_por_usuario_id` y el índice único que permite **un solo turno abierto** a la vez.  
  **⚠️ BACKUP OBLIGATORIO:** Antes de ejecutar, hacer un backup completo de la base maestra (`pg_dump -U postgres -d <base_maestra> > backup_antes_de_migracion.sql` o equivalente). Si algo falla durante la migración (DDL + UPDATE de comandas), se puede restaurar.  
  **Instrucciones:** Ejecutar con usuario propietario (`postgres`) contra la base maestra. Antes, verificar que no haya más de un turno abierto:  
  ```sql
  SELECT id, usuario_id, abierta_en FROM pos_sesiones WHERE cerrada_en IS NULL;
  ```  
  Si hay más de uno, cerrarlos manualmente: la migración aborta a propósito para no generar cierres falsos.  
  **Verificación:**  
  ```sql
  SELECT indexname FROM pg_indexes WHERE tablename='pos_sesiones' AND indexname='uq_pos_sesiones_turno_unico_abierto';
  SELECT column_name FROM information_schema.columns WHERE table_name='pos_comandas' AND column_name='usuario_id';
  SELECT column_name FROM information_schema.columns WHERE table_name='pos_cierres' AND column_name='cerrado_por_usuario_id';
  SELECT to_regclass('public.pos_turno_participantes');
  ```  
  Deben devolver el índice, las 2 columnas y la tabla.

- [ ] **Aplicar migración precios a activos_tipos**  
  Archivo: `supabase/migrations/20251028_activos_tipos_precio_referencia.sql`  
  SQL:
  ```sql
  ALTER TABLE activos_tipos
    ADD COLUMN IF NOT EXISTS precio_referencia NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS precio_origen TEXT,
    ADD COLUMN IF NOT EXISTS precio_actualizado_at TIMESTAMPTZ;
  ```
  **Instrucciones:** Aplicar con usuario propietario (`postgres`) contra la base maestra.  
  **Verificación:** `SELECT column_name FROM information_schema.columns WHERE table_name='activos_tipos' AND column_name IN ('precio_referencia','precio_origen','precio_actualizado_at');` debe devolver las 3 filas.

- [ ] **Asignar precios de referencia desde MercadoLibre Venezuela (Ciudad Guayana)**  
  **Script:** `update_prices_direct.py` (en raíz del proyecto)  
  **Requisitos:** Acceso directo a PostgreSQL con `psycopg` instalado. Conexión: `postgresql://control_app:Reidchendk.11@localhost:5432/control_entradas?sslmode=disable` (ajustar si es otra BD).  
  **Instrucciones:**  
  1. Asegurarse de tener conexión a la BD (PostgreSQL corriendo o accesible).  
  2. Instalar dependencia: `pip install psycopg[binary]`  
  3. Ejecutar: `py update_prices_direct.py` (o `python update_prices_direct.py`)  
  4. El script busca cada `activos_tipos` activo en `https://api.mercadolibre.com/sites/MLV/search` usando nombre/grupo/modelo, toma el precio más bajo como referencia, guarda `precio_referencia`, `precio_origen='mercadolibre_ve'` y `precio_actualizado_at`.  
  5. **Verificación:** `SELECT id, nombre, precio_referencia, precio_origen, precio_actualizado_at FROM activos_tipos WHERE precio_referencia IS NOT NULL ORDER BY id;`  
  **Nota:** Usa rate limiting (2s entre búsquedas). Prioriza resultados de Venezuela. Puede tomar varios minutos dependiendo de la cantidad de tipos.
```