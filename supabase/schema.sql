-- =====================================================================
-- Esquema Supabase (PostgreSQL) — Control de Entradas y Salidas + POS
-- Generado a partir de usr/models/*.py, usr/database/sync.py,
-- usr/database/pos_sync.py y usr/database/local_replica.py
-- Idempotente: seguro de ejecutar en el esquema productivo existente.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Tablas del inventario / contabilidad
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS categorias (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL UNIQUE,
    descripcion     VARCHAR(255),
    imagen          TEXT,
    color           VARCHAR(20) DEFAULT '#2196F3',
    activo          BOOLEAN DEFAULT TRUE,
    visible_en_pos  BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS productos (
    id                     SERIAL PRIMARY KEY,
    nombre                 VARCHAR(200) NOT NULL,
    codigo                 VARCHAR(50) UNIQUE,
    descripcion            TEXT,
    categoria_id           INTEGER REFERENCES categorias(id),
    es_pesable             BOOLEAN DEFAULT FALSE,
    requiere_foto_peso     BOOLEAN DEFAULT FALSE,
    peso_unitario          DOUBLE PRECISION,
    precio_venta           DOUBLE PRECISION DEFAULT 0,
    unidad_medida          VARCHAR(20) DEFAULT 'unidad',
    stock_actual           DOUBLE PRECISION DEFAULT 0,
    stock_minimo           DOUBLE PRECISION DEFAULT 0,
    activo                 BOOLEAN DEFAULT TRUE,
    tipo                   VARCHAR(50) DEFAULT 'ninguno' NOT NULL,
    almacen_predeterminado VARCHAR(50) DEFAULT 'principal',
    created_at             TIMESTAMPTZ DEFAULT now(),
    updated_at             TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos (categoria_id);
CREATE INDEX IF NOT EXISTS idx_productos_tipo ON productos (tipo);

CREATE TABLE IF NOT EXISTS proveedores (
    id            SERIAL PRIMARY KEY,
    nombre        VARCHAR(200) NOT NULL UNIQUE,
    rif           VARCHAR(50),
    telefono      VARCHAR(50),
    email         VARCHAR(100),
    direccion     TEXT,
    contacto      VARCHAR(100),
    observaciones TEXT,
    estado        VARCHAR(20) DEFAULT 'Activo',
    created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS existencias (
    id         SERIAL PRIMARY KEY,
    producto_id INTEGER REFERENCES productos(id),
    almacen    VARCHAR(50) NOT NULL,
    cantidad   DOUBLE PRECISION DEFAULT 0,
    unidad     VARCHAR(50) DEFAULT 'unidad',
    UNIQUE (producto_id, almacen)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_existencias_unique ON existencias (producto_id, almacen);

CREATE TABLE IF NOT EXISTS stock_checkpoint (
    producto_id      INTEGER NOT NULL,
    almacen          TEXT NOT NULL,
    cantidad         DOUBLE PRECISION DEFAULT 0,
    fecha_checkpoint TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (producto_id, almacen)
);

CREATE TABLE IF NOT EXISTS movimientos (
    id               SERIAL PRIMARY KEY,
    producto_id      INTEGER NOT NULL REFERENCES productos(id),
    factura_id       INTEGER,
    requisicion_id   INTEGER,
    venta_id         INTEGER,
    venta_sync_uuid  TEXT,
    tipo             VARCHAR(30) NOT NULL, -- entrada, salida, ajuste, tr_salida, tr_entrada
    cantidad         DOUBLE PRECISION NOT NULL,
    cantidad_anterior DOUBLE PRECISION DEFAULT 0,
    cantidad_nueva   DOUBLE PRECISION DEFAULT 0,
    peso_total       DOUBLE PRECISION DEFAULT 0,
    registrado_por   VARCHAR(100),
    observaciones    TEXT,
    almacen          VARCHAR(50),
    fecha_movimiento TIMESTAMPTZ DEFAULT now(),
    created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_movimientos_producto ON movimientos (producto_id, fecha_movimiento DESC);
CREATE INDEX IF NOT EXISTS idx_movimientos_factura ON movimientos (factura_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_requisicion ON movimientos (requisicion_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_tipo_fecha ON movimientos (tipo, fecha_movimiento DESC);

CREATE TABLE IF NOT EXISTS movimientos_archivo (
    id               INTEGER PRIMARY KEY,
    producto_id      INTEGER NOT NULL REFERENCES productos(id),
    factura_id       INTEGER,
    requisicion_id   INTEGER,
    venta_id         INTEGER,
    venta_sync_uuid  TEXT,
    tipo             VARCHAR(30) NOT NULL,
    cantidad         DOUBLE PRECISION NOT NULL,
    cantidad_anterior DOUBLE PRECISION DEFAULT 0,
    cantidad_nueva   DOUBLE PRECISION DEFAULT 0,
    peso_total       DOUBLE PRECISION DEFAULT 0,
    registrado_por   VARCHAR(100),
    observaciones    TEXT,
    almacen          VARCHAR(50),
    fecha_movimiento TIMESTAMPTZ DEFAULT now(),
    created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mov_archivo_producto ON movimientos_archivo (producto_id, fecha_movimiento DESC);
CREATE INDEX IF NOT EXISTS idx_mov_archivo_tipo_fecha ON movimientos_archivo (tipo, fecha_movimiento DESC);
CREATE INDEX IF NOT EXISTS idx_mov_archivo_factura ON movimientos_archivo (factura_id);

CREATE TABLE IF NOT EXISTS periodos (
    id            SERIAL PRIMARY KEY,
    periodo       TEXT NOT NULL UNIQUE,
    fecha_apertura TEXT NOT NULL,
    registrado_por TEXT
);
CREATE INDEX IF NOT EXISTS idx_periodos_periodo ON periodos (periodo DESC);

CREATE TABLE IF NOT EXISTS compras_lista (
    id         SERIAL PRIMARY KEY,
    producto_id INTEGER NOT NULL REFERENCES productos(id),
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_compras_lista_producto ON compras_lista (producto_id);

-- ---------------------------------------------------------------------
-- Facturas y pagos
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS facturas (
    id               SERIAL PRIMARY KEY,
    numero_factura   VARCHAR(50) NOT NULL,
    tipo_documento   VARCHAR(50) DEFAULT 'Factura', -- Factura, Nota de Entrega, Entrada
    proveedor        VARCHAR(200),
    fecha_factura    TIMESTAMPTZ NOT NULL,
    fecha_recepcion  TIMESTAMPTZ DEFAULT now(),
    total_bruto      DOUBLE PRECISION DEFAULT 0,
    total_impuestos  DOUBLE PRECISION DEFAULT 0,
    total_neto       DOUBLE PRECISION DEFAULT 0,
    estado           VARCHAR(20) DEFAULT 'Pendiente', -- Pendiente, Validada, Anulada
    observaciones    TEXT,
    validada_por     VARCHAR(100),
    fecha_validacion TIMESTAMPTZ,
    created_at       TIMESTAMPTZ DEFAULT now(),
    updated_at       TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_facturas_numero ON facturas (numero_factura);

CREATE TABLE IF NOT EXISTS factura_pagos (
    id          SERIAL PRIMARY KEY,
    factura_id  INTEGER NOT NULL REFERENCES facturas(id),
    tipo_pago   VARCHAR(50) NOT NULL, -- efectivo, transferencia, divisas
    monto       DOUBLE PRECISION NOT NULL,
    referencia  VARCHAR(100),
    tasa_cambio DOUBLE PRECISION, -- solo para divisas
    fecha_pago  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_factura_pagos_factura ON factura_pagos (factura_id);

-- ---------------------------------------------------------------------
-- Requisiciones
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS requisiciones (
    id                  SERIAL PRIMARY KEY,
    numero              VARCHAR(50) NOT NULL UNIQUE,
    numero_secuencial   INTEGER NOT NULL,
    origen              VARCHAR(50) NOT NULL,
    destino             VARCHAR(50) NOT NULL,
    estado              VARCHAR(20) DEFAULT 'pendiente',
    observaciones       TEXT,
    creada_por          VARCHAR(100),
    procesada_por       VARCHAR(100),
    fecha_procesamiento TIMESTAMPTZ,
    fecha_creacion      TIMESTAMPTZ DEFAULT now(),
    actualizada         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS requisicion_detalles (
    id              SERIAL PRIMARY KEY,
    requisicion_id  INTEGER NOT NULL REFERENCES requisiciones(id),
    producto_id     INTEGER REFERENCES productos(id),
    ingrediente     VARCHAR(200) NOT NULL,
    cantidad        DOUBLE PRECISION NOT NULL,
    unidad          VARCHAR(50) DEFAULT 'unidad',
    cantidad_surtida DOUBLE PRECISION DEFAULT 0,
    verificado      BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_req_detalles_requisicion ON requisicion_detalles (requisicion_id);

-- ---------------------------------------------------------------------
-- Recetas y producciones
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS recetas (
    id                 SERIAL PRIMARY KEY,
    nombre             VARCHAR(200) NOT NULL,
    tipo               VARCHAR(20) NOT NULL,
    producto_base_id   INTEGER REFERENCES productos(id),
    producto_final_id  INTEGER REFERENCES productos(id),
    cantidad_producida DOUBLE PRECISION DEFAULT 1,
    activo             BOOLEAN DEFAULT TRUE,
    created_at         TIMESTAMPTZ DEFAULT now(),
    updated_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS receta_componentes (
    id             SERIAL PRIMARY KEY,
    receta_id      INTEGER NOT NULL REFERENCES recetas(id),
    producto_id    INTEGER NOT NULL REFERENCES productos(id),
    cantidad       DOUBLE PRECISION NOT NULL,
    unidad         VARCHAR(20) DEFAULT 'unidad',
    tipo_componente VARCHAR(20) NOT NULL,
    peso_variable  INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_receta_componentes_receta ON receta_componentes (receta_id);

CREATE TABLE IF NOT EXISTS producciones (
    id              SERIAL PRIMARY KEY,
    receta_id       INTEGER NOT NULL REFERENCES recetas(id),
    cantidad        DOUBLE PRECISION NOT NULL,
    estado          VARCHAR(20) DEFAULT 'completado',
    usuario         VARCHAR(100),
    observaciones   TEXT,
    cocineros       TEXT,
    fecha_produccion TIMESTAMPTZ DEFAULT now(),
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS produccion_detalles (
    id             SERIAL PRIMARY KEY,
    produccion_id  INTEGER NOT NULL REFERENCES producciones(id),
    producto_id    INTEGER NOT NULL REFERENCES productos(id),
    tipo           VARCHAR(10) NOT NULL,
    cantidad       DOUBLE PRECISION NOT NULL,
    unidad         VARCHAR(20) DEFAULT 'unidad',
    movimiento_id  INTEGER
);
CREATE INDEX IF NOT EXISTS idx_prod_detalles_produccion ON produccion_detalles (produccion_id);

-- ---------------------------------------------------------------------
-- Módulo POS
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS pos_categorias (
    id         SERIAL PRIMARY KEY,
    nombre     TEXT NOT NULL,
    color      TEXT DEFAULT '#FF6F00',
    icono      TEXT,
    activo     INTEGER DEFAULT 1,
    sync_uuid  TEXT,
    created_at TEXT,
    updated_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_pos_categorias_sync_uuid ON pos_categorias (sync_uuid);

CREATE OR REPLACE FUNCTION set_pos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS pos_mesas (
    id         SERIAL PRIMARY KEY,
    numero     TEXT NOT NULL,
    nombre     TEXT,
    zona       TEXT,
    activo     INTEGER DEFAULT 1,
    creado_en  TEXT NOT NULL,
    updated_at TIMESTAMPTZ
);
CREATE TRIGGER trg_pos_mesas_updated_at
    BEFORE INSERT OR UPDATE ON pos_mesas
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

CREATE TABLE IF NOT EXISTS pos_habitaciones (
    id         SERIAL PRIMARY KEY,
    numero     TEXT NOT NULL,
    piso       TEXT,
    tipo       TEXT,
    activo     INTEGER DEFAULT 1,
    creado_en  TEXT NOT NULL,
    updated_at TIMESTAMPTZ
);
CREATE TRIGGER trg_pos_habitaciones_updated_at
    BEFORE INSERT OR UPDATE ON pos_habitaciones
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

CREATE TABLE IF NOT EXISTS pos_usuarios (
    id               SERIAL PRIMARY KEY,
    nombre           TEXT NOT NULL,
    pin_hash         TEXT,
    es_admin         INTEGER DEFAULT 0,
    es_desarrollador INTEGER DEFAULT 0,
    activo           INTEGER DEFAULT 1,
    creado_en        TEXT NOT NULL,
    updated_at       TIMESTAMPTZ
);
CREATE TRIGGER trg_pos_usuarios_updated_at
    BEFORE INSERT OR UPDATE ON pos_usuarios
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

-- Usuario de desarrollo: inicia sesión SIN aperturar turno/caja. Se sincroniza
-- a los dispositivos y puede desactivarse desde Configuración → Cajeros.
INSERT INTO pos_usuarios (nombre, es_admin, es_desarrollador, activo, creado_en)
SELECT 'Desarrollador', 1, 1, 1, now()::text
WHERE NOT EXISTS (SELECT 1 FROM pos_usuarios WHERE nombre = 'Desarrollador');

CREATE TABLE IF NOT EXISTS pos_settings (
    key   TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS pos_comandas (
    id           SERIAL PRIMARY KEY,
    sesion_id    INTEGER,
    mesa_id      INTEGER,
    habitacion_id INTEGER,
    estado       TEXT DEFAULT 'abierta',
    total        DOUBLE PRECISION DEFAULT 0,
    items_json   TEXT,
    sync_uuid    TEXT,
    created_at   TEXT NOT NULL,
    updated_at   TEXT
);
CREATE INDEX IF NOT EXISTS idx_pos_comandas_sync_uuid ON pos_comandas (sync_uuid);

CREATE TABLE IF NOT EXISTS pos_ventas (
    id                  SERIAL PRIMARY KEY,
    comanda_id          INTEGER,
    correlativo         INTEGER,
    total               DOUBLE PRECISION DEFAULT 0,
    items_json          TEXT,
    mesa_id             INTEGER,
    habitacion_id       INTEGER,
    usuario_id          INTEGER,
    sesion_id           INTEGER,
    estado              TEXT DEFAULT 'vigente',
    venta_anula_id      INTEGER,
    motivo_anulacion    TEXT,
    anulada_por         TEXT,
    anulada_en          TEXT,
    tasa_bs             DOUBLE PRECISION,
    sync_uuid           TEXT,
    comanda_sync_uuid   TEXT,
    venta_anula_sync_uuid TEXT,
    created_at          TEXT NOT NULL,
    updated_at          TEXT
);
CREATE INDEX IF NOT EXISTS idx_pos_ventas_sync_uuid ON pos_ventas (sync_uuid);

-- ---------------------------------------------------------------------
-- Carta / platos (módulo POS extendido)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS platos_categorias (
    id                   SERIAL PRIMARY KEY,
    nombre               TEXT NOT NULL,
    color                TEXT DEFAULT '#FF6F00',
    activo               INTEGER DEFAULT 1,
    categoria_padre_id   INTEGER,
    pos_categoria_padre_id INTEGER,
    created_at           TEXT,
    updated_at           TEXT
);
CREATE INDEX IF NOT EXISTS idx_pcat_cat_padre ON platos_categorias (categoria_padre_id);
CREATE INDEX IF NOT EXISTS idx_pcat_pos_padre ON platos_categorias (pos_categoria_padre_id);

CREATE TABLE IF NOT EXISTS platos (
    id            SERIAL PRIMARY KEY,
    nombre        TEXT NOT NULL,
    categoria_id  INTEGER NOT NULL REFERENCES platos_categorias(id),
    precio_venta  DOUBLE PRECISION DEFAULT 0,
    activo        INTEGER DEFAULT 1,
    es_contorno   INTEGER DEFAULT 0,
    lleva_contornos INTEGER DEFAULT 0,
    created_at    TEXT,
    updated_at    TEXT
);

CREATE TABLE IF NOT EXISTS plato_ingredientes (
    id          SERIAL PRIMARY KEY,
    plato_id    INTEGER NOT NULL REFERENCES platos(id),
    producto_id INTEGER NOT NULL REFERENCES productos(id),
    cantidad    DOUBLE PRECISION NOT NULL,
    unidad      TEXT DEFAULT 'unidad'
);

CREATE TABLE IF NOT EXISTS plato_contornos (
    id             SERIAL PRIMARY KEY,
    plato_id       INTEGER NOT NULL REFERENCES platos(id),
    contorno_id    INTEGER NOT NULL REFERENCES platos(id),
    max_seleccionar INTEGER DEFAULT 2
);

-- Temporales: imagenes pre-cargadas por OCR, visibles entre dispositivos
CREATE TABLE IF NOT EXISTS pos_temporales (
    id              SERIAL PRIMARY KEY,
    imagen_base64   TEXT,
    tipo_documento  TEXT,
    nro_factura     TEXT,
    proveedor       TEXT,
    monto           DOUBLE PRECISION,
    fecha           TEXT,
    creado_en       TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ
);
CREATE TRIGGER trg_pos_temporales_updated_at
    BEFORE INSERT OR UPDATE ON pos_temporales
    FOR EACH ROW EXECUTE FUNCTION set_pos_updated_at();

COMMIT;
