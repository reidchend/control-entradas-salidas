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
```