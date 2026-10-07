-- =====================================================================
-- Migración: tablas pos_sesiones y whatsapp_queue
-- =====================================================================
-- Estas dos tablas se crearon directamente en la base y nunca estuvieron
-- definidas en el repo. La definición se reconstruyó desde el código de la app
-- (lib/features/pos, lib/features/whatsapp) siguiendo las convenciones de
-- schema.sql (pos_usuarios/pos_cierres).
--
-- pos_sesiones: turno de caja del POS abierto por cajero. `cerrada_en`
--   NULL = turno abierto. Las fechas viajan como ISO8601 (TEXT), igual
--   que en pos_cierres (abierta_en/cerrada_en).
-- whatsapp_queue: cola de mensajes pendientes para el bot de WhatsApp.

BEGIN;

CREATE TABLE IF NOT EXISTS pos_sesiones (
    id               SERIAL PRIMARY KEY,
    usuario_id       INTEGER NOT NULL REFERENCES pos_usuarios(id),
    abierta_en       TEXT NOT NULL,          -- ISO8601, momento de apertura
    cerrada_en       TEXT,                   -- ISO8601, NULL = turno abierto
    caja_inicial     DOUBLE PRECISION NOT NULL DEFAULT 0,
    caja_final       DOUBLE PRECISION,       -- NULL hasta cerrar
    sync_uuid        TEXT NOT NULL,          -- UUID para sincronización/idepotencia
    created_at       TIMESTAMPTZ DEFAULT now(),
    updated_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pos_sesiones_usuario_fecha
    ON pos_sesiones (usuario_id, abierta_en DESC);
CREATE INDEX IF NOT EXISTS idx_pos_sesiones_cerrada_en
    ON pos_sesiones (cerrada_en);

CREATE TRIGGER trg_pos_sesiones_updated_at
    BEFORE INSERT OR UPDATE ON pos_sesiones
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

CREATE TABLE IF NOT EXISTS whatsapp_queue (
    id             SERIAL PRIMARY KEY,
    tipo           TEXT NOT NULL,           -- text | image | report_simple | report_detail
    mensaje        TEXT,
    imagen_base64  TEXT,
    imagen_path    TEXT,
    estado         TEXT NOT NULL DEFAULT 'pending',  -- pending | sending | sent | failed
    intentos       INTEGER NOT NULL DEFAULT 0,
    max_intentos   INTEGER NOT NULL DEFAULT 5,
    ultimo_error   TEXT,
    created_at     TIMESTAMPTZ DEFAULT now(),
    updated_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_queue_estado
    ON whatsapp_queue (estado, created_at);

CREATE TRIGGER trg_whatsapp_queue_updated_at
    BEFORE INSERT OR UPDATE ON whatsapp_queue
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

COMMIT;