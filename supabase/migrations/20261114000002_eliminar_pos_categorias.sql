-- =====================================================================
-- Migración: elimina tabla pos_categorias (redundante)
-- =====================================================================
-- Todas las categorías de platos ahora se manejan desde platos_categorias.
-- pos_categorias quedó huérfana: no se usa para clasificar platos ni es
-- necesaria para mostrar categorías en la comanda (ya se usa platos_categorias).
-- =====================================================================

DROP TABLE IF EXISTS pos_categorias CASCADE;
