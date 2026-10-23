-- Rol semántico de los tipos del sistema.
--
-- La lógica de la app (flujo de producción, colores del stock) ya no compara
-- el TEXTO del tipo: pregunta por su ROL ('produccion', 'feria', 'venta',
-- 'ninguno'). Así los tipos del sistema se pueden renombrar desde
-- Configuración > Tipos sin romper nada: el nombre es solo etiqueta.
--
-- El índice único parcial evita dos tipos con el mismo rol. Los tipos libres
-- (Consumo, uso interno, los nuevos) tienen rol NULL y no participan de
-- ninguna lógica.

ALTER TABLE tipos_producto ADD COLUMN IF NOT EXISTS rol VARCHAR(20);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tipos_producto_rol
    ON tipos_producto (rol) WHERE rol IS NOT NULL;

UPDATE tipos_producto SET rol = 'ninguno'    WHERE nombre = 'ninguno';
UPDATE tipos_producto SET rol = 'feria'      WHERE nombre = 'feria';
UPDATE tipos_producto SET rol = 'produccion' WHERE nombre = 'producción';
UPDATE tipos_producto SET rol = 'venta'      WHERE nombre = 'Productos para la venta';
