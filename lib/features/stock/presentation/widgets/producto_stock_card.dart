import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/existencia.dart';
import '../../../../core/models/producto.dart';
import '../../data/stock_providers.dart';

/// Tarjeta de producto en la vista de stock (porta `build_product_card`).
/// Nombre + menú, categoría/código, existencias por almacén y stock
/// destacado con color según el nivel.
class ProductoStockCard extends ConsumerWidget {
  const ProductoStockCard({
    super.key,
    required this.producto,
    required this.categorias,
    required this.onAction,
    this.almacen,
  });

  final Producto producto;
  final Map<int, String> categorias;
  final String? almacen;
  final void Function(String action, Producto producto) onAction;

  bool get _esPesable => producto.esPesable;

  String _fmt(double v) => _esPesable ? v.toStringAsFixed(2) : v.round().toString();

  Color _colorPara(BuildContext context, double total) {
    final scheme = Theme.of(context).colorScheme;
    if (total <= 0) return scheme.error;
    if (producto.stockMinimo > 0 && total <= producto.stockMinimo) {
      return const Color(0xFFFB8C00);
    }
    return Colors.green;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(stockRepoProvider)!;
    final scheme = Theme.of(context).colorScheme;
    final unidad = producto.unidadMedida.isEmpty ? 'uds' : producto.unidadMedida;
    final catNombre = producto.categoriaId != null
        ? (categorias[producto.categoriaId] ?? 'S/C')
        : 'S/C';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: FutureBuilder<List<Existencia>>(
        future: repo.getExistenciasProducto(producto.id),
        builder: (context, snap) {
          final exis = snap.data ?? [];
          // Con filtro de almacén, el stock destacado y su nivel se calculan
          // solo con las existencias de ese almacén; sin filtro, la suma.
          final totalEsAlmacen = almacen != null
              ? exis
                  .where((e) => e.almacen == almacen)
                  .fold<double>(0, (a, e) => a + e.cantidad)
              : exis.fold<double>(0, (a, e) => a + e.cantidad);
          final color = _colorPara(context, totalEsAlmacen);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      producto.nombre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        color: scheme.onSurfaceVariant, size: 20),
                    onSelected: (v) => onAction(v, producto),
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(
                        value: 'historial',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.history),
                          title: Text('Ver historial'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'existencias',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.inventory_2_outlined),
                          title: Text('Existencias'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$catNombre  •  ID ${producto.codigo ?? '---'}',
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              if (exis.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    for (final e in exis)
                      Text(
                        '${e.almacen.capitalize()}: ${_fmt(e.cantidad)}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmt(totalEsAlmacen),
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ' $unidad',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension _StringCapitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
