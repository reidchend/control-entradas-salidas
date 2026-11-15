# Pendientes de producción

**Regla obligatoria:** Requieren permisos de propietario (`postgres`), no `control_app`. No ejecutar por cuenta propia.

## Pendientes sin completar

- [ ] **Aplicar migración de tipo de elemento en platos**
  Archivo: `supabase/migrations/20261115000001_platos_tipo_servicio.sql`
  SQL:
  ```sql
  ALTER TABLE platos
      ADD COLUMN IF NOT EXISTS tipo TEXT DEFAULT 'plato';
  UPDATE platos SET tipo = 'plato' WHERE tipo IS NULL;
  ALTER TABLE platos ALTER COLUMN tipo SET NOT NULL;
  ALTER TABLE platos ALTER COLUMN tipo SET DEFAULT 'plato';
  ```
  **Para qué:** permite crear "servicios" (delivery, cargo por servicio) además de platos, y al agregarlos a una comanda el usuario puede editar el precio manualmente.
  **Verificación:**
  ```sql
  SELECT column_name, data_type, column_default
  FROM information_schema.columns
  WHERE table_name = 'platos' AND column_name = 'tipo';
  ```
  **Nota:** sin esta columna, los servicios se guardan como platos normales y el precio no es editable al agregar a la comanda.
