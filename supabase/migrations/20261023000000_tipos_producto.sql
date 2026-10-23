-- Catálogo administrable de tipos de producto.
--
-- Antes de esto, la única "fuente de verdad" de los tipos era una lista fija
-- hardcodeada en producto_dialog.dart, y en la BD coexistían variantes del
-- mismo tipo con escrituras distintas ("PRODUCTO PARA USO INTERNO" vs
-- "productos para uso Interno"). El catálogo vive ahora en la BD, la pestaña
-- Configuración > Tipos lo administra y el dropdown de alta/edición de
-- producto lo lee de aquí.
--
-- `protegido` marca los tipos de los que depende la lógica de la app
-- (colores del stock según 'feria'/'producción'/'venta', flujo de producción
-- por tipo 'producción', y 'ninguno' como default del modelo): no se pueden
-- renombrar ni inactivar desde la UI, para no romper esos flujos.

CREATE TABLE IF NOT EXISTS tipos_producto (
    id         SERIAL PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL UNIQUE,
    protegido  BOOLEAN DEFAULT FALSE,
    activo     BOOLEAN DEFAULT TRUE,
    orden      INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO tipos_producto (nombre, protegido, activo, orden) VALUES
    ('ninguno', TRUE, TRUE, 1),
    ('feria', TRUE, TRUE, 2),
    ('producción', TRUE, TRUE, 3),
    ('Consumo', FALSE, TRUE, 4),
    ('productos para uso Interno', FALSE, TRUE, 5),
    ('Productos para la venta', TRUE, TRUE, 6)
ON CONFLICT (nombre) DO NOTHING;
