-- =====================================================================
-- Migración: marca de impresión para cocina en pos_comandas
-- =====================================================================
-- `impresa_en` guarda el momento (ISO8601, hora local del equipo que imprime)
-- en que la comanda se imprimió para llevarla a cocina.
--
--   NULL      = todavía no se imprimió -> el home la resalta como "Nueva"
--   no NULL   = ya se imprimió        -> el home la muestra "En cocina"
--
-- Si después de imprimir se agregan/quitan productos o cambia el total, la
-- app vuelve a dejar `impresa_en = NULL` para que la comanda se reimprima.
--
-- Requiere rol propietario (`postgres`), no `control_app`.

BEGIN;

ALTER TABLE pos_comandas
    ADD COLUMN IF NOT EXISTS impresa_en TEXT;

COMMIT;
