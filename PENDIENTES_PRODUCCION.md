# Pendientes de producción

**Regla obligatoria:** Requieren permisos de propietario (`postgres`), no `control_app`. No ejecutar por cuenta propia.

## Pendientes sin completar

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