# Pendientes de producción

**Regla obligatoria:** Requieren permisos de propietario (`postgres`), no `control_app`. No ejecutar por cuenta propia.

## Pendientes sin completar

- [ ] **Aplicar migración de marca "En cocina" en pos_comandas**
  Archivo: `supabase/migrations/20261115000000_pos_comandas_impresa_en.sql`
  SQL:
  ```sql
  ALTER TABLE pos_comandas
      ADD COLUMN IF NOT EXISTS impresa_en TEXT;
  ```
  **Para qué:** el home del POS resalta las comandas nuevas (sin imprimir) y las marca "En cocina" cuando se imprime la comanda para llevarla a cocina.
  **Verificación:**
  ```sql
  SELECT column_name, data_type
  FROM information_schema.columns
  WHERE table_name = 'pos_comandas' AND column_name = 'impresa_en';
  ```
  **Nota:** sin esta columna la app sigue funcionando (guardar e imprimir no se rompen), pero todas las comandas se ven como "Nueva" porque la marca no se puede persistir.
