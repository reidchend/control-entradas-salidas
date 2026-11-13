-- =====================================================================
-- Migración: turnos compartidos del POS
-- =====================================================================
-- Cambia el modelo de "un turno por cajero" a "un turno con varios
-- participantes":
--   * pos_sesiones sigue siendo el turno. `usuario_id` = quién lo abrió
--     (aperturista) y `cerrada_en IS NULL` = turno abierto.
--   * pos_turno_participantes registra qué usuarios entraron al turno.
--   * pos_comandas.usuario_id atribuye quién creó/actualizó la comanda.
--   * pos_cierres.cerrado_por_usuario_id registra quién ejecutó el cierre.
--   * Un índice único parcial garantiza UN SOLO turno abierto a la vez.
--
-- IMPORTANTE: la migración NO cierra turnos automáticamente. Si hay más de
-- un turno abierto (modelo viejo multi-cajero), aborta y pide cerrarlos
-- manualmente para no generar cierres falsos.
--
-- Ejecutar con un rol propietario (postgres), no con control_app.
-- =====================================================================

BEGIN;

-- 1. Metadatos del turno compartido -----------------------------------------
ALTER TABLE pos_sesiones
    ADD COLUMN IF NOT EXISTS cerrada_por_usuario_id INTEGER REFERENCES usuarios(id),
    ADD COLUMN IF NOT EXISTS origen_apertura TEXT,   -- 'pc' | 'android' | 'web'
    ADD COLUMN IF NOT EXISTS nota_cierre TEXT;

-- 2. Participantes del turno -------------------------------------------------
CREATE TABLE IF NOT EXISTS pos_turno_participantes (
    id                  SERIAL PRIMARY KEY,
    sesion_id           INTEGER NOT NULL REFERENCES pos_sesiones(id) ON DELETE CASCADE,
    usuario_id          INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    unido_en            TEXT NOT NULL,
    ultima_actividad_en TEXT,
    salio_en            TEXT,
    created_at          TEXT NOT NULL,
    updated_at          TEXT,
    UNIQUE (sesion_id, usuario_id)
);

CREATE INDEX IF NOT EXISTS idx_pos_turno_part_sesion
    ON pos_turno_participantes (sesion_id);
CREATE INDEX IF NOT EXISTS idx_pos_turno_part_usuario
    ON pos_turno_participantes (usuario_id);

-- Trigger para updated_at (reutiliza la función existente).
DROP TRIGGER IF EXISTS trg_pos_turno_part_updated_at ON pos_turno_participantes;
CREATE TRIGGER trg_pos_turno_part_updated_at
    BEFORE INSERT OR UPDATE ON pos_turno_participantes
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

-- 3. Autoría de comandas -----------------------------------------------------
ALTER TABLE pos_comandas
    ADD COLUMN IF NOT EXISTS usuario_id INTEGER REFERENCES usuarios(id);

UPDATE pos_comandas c
   SET usuario_id = s.usuario_id
  FROM pos_sesiones s
 WHERE c.sesion_id = s.id
   AND c.usuario_id IS NULL;

-- 4. Cierre: quién cerró -----------------------------------------------------
ALTER TABLE pos_cierres
    ADD COLUMN IF NOT EXISTS cerrado_por_usuario_id INTEGER REFERENCES usuarios(id);

-- 5. Backfill de participantes para el turno abierto existente --------------
INSERT INTO pos_turno_participantes
    (sesion_id, usuario_id, unido_en, ultima_actividad_en, created_at)
SELECT s.id, s.usuario_id, s.abierta_en, s.abierta_en, s.abierta_en
  FROM pos_sesiones s
 WHERE s.cerrada_en IS NULL
ON CONFLICT (sesion_id, usuario_id) DO NOTHING;

-- 6. Un solo turno abierto ---------------------------------------------------
DO $$
DECLARE
  abiertos INTEGER;
BEGIN
  SELECT count(*) INTO abiertos FROM pos_sesiones WHERE cerrada_en IS NULL;
  IF abiertos > 1 THEN
    RAISE EXCEPTION
      'Hay % turnos abiertos. Ciérrelos manualmente antes de aplicar esta migración (el nuevo modelo solo permite uno).',
      abiertos;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_pos_sesiones_turno_unico_abierto
    ON pos_sesiones ((1))
    WHERE cerrada_en IS NULL;

COMMIT;
