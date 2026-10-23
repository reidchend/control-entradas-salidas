-- Capability de cada tipo de producto: puede usarse como INGREDIENTE de
-- platos del POS (se descarga del inventario al vender el plato).
--
-- Regla sembrada según negocio: uso interno, producción y feria sí;
-- venta, consumo y ninguno no. Se administra desde Configuración > Tipos
-- (switch "Puede ser ingrediente de platos").

ALTER TABLE tipos_producto ADD COLUMN IF NOT EXISTS es_insumo BOOLEAN DEFAULT FALSE;

UPDATE tipos_producto SET es_insumo = TRUE
    WHERE rol IN ('produccion', 'feria')
       OR nombre = 'productos para uso Interno';
