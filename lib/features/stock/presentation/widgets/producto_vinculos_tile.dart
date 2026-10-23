import 'package:flutter/material.dart';

import '../../data/vinculo_producto.dart';

/// Sección expandible con los vínculos de producción de un producto.
///
/// Muestra dos grupos: los productos que se producen usando este como insumo
/// ("Producciones vinculadas") y los insumos necesarios para producirlo
/// ("Insumos disponibles"), cada uno con su stock actual. Sin vínculos no
/// ocupa espacio.
class ProductoVinculosTile extends StatelessWidget {
  const ProductoVinculosTile({super.key, required this.vinculos});

  final List<VinculoProducto> vinculos;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (vinculos.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final derivados = vinculos.where((v) => v.esDerivado).toList();
    final insumos = vinculos.where((v) => !v.esDerivado).toList();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(Icons.account_tree_outlined,
            size: 18, color: scheme.primary),
        title: Text(
          'Vínculos de producción (${vinculos.length})',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          ),
        ),
        children: [
          if (derivados.isNotEmpty)
            _Grupo(
              titulo: 'Producciones vinculadas',
              icono: Icons.precision_manufacturing_outlined,
              items: derivados,
              fmt: _fmt,
            ),
          if (insumos.isNotEmpty)
            _Grupo(
              titulo: 'Insumos disponibles',
              icono: Icons.inventory_outlined,
              items: insumos,
              fmt: _fmt,
            ),
        ],
      ),
    );
  }
}

class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.titulo,
    required this.icono,
    required this.items,
    required this.fmt,
  });

  final String titulo;
  final IconData icono;
  final List<VinculoProducto> items;
  final String Function(double) fmt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (final v in items)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.nombre,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Desglose por almacén: muestra dónde está el stock
                        // incluso cuando la lista está filtrada por uno solo.
                        if (v.stockPorAlmacen.isNotEmpty)
                          Text(
                            _desglose(v),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${fmt(v.stock)} ${v.unidad.isEmpty ? 'uds' : v.unidad}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: v.stock <= 0 ? scheme.error : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Texto con el stock de cada almacén, ej. "Principal: 5 · Restaurante: 2".
  String _desglose(VinculoProducto v) {
    return [
      for (final e in v.stockPorAlmacen.entries)
        '${e.key.capitalize()}: ${fmt(e.value)}',
    ].join(' · ');
  }
}

extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
