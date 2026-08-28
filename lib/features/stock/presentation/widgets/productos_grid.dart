import 'package:flutter/material.dart';

import '../../../../core/models/producto.dart';
import 'producto_stock_card.dart';

/// Grid de productos de stock (porta `_render_productos` de stock_view.py).
/// 1 columna en móvil (<720px) y 2 columnas en escritorio, con las tarjetas
/// de cada fila a igual altura.
class ProductosGrid extends StatelessWidget {
  const ProductosGrid({
    super.key,
    required this.productos,
    required this.categorias,
    required this.onAction,
    this.almacen,
  });

  final List<Producto> productos;
  final Map<int, String> categorias;
  final String? almacen;
  final void Function(String action, Producto producto) onAction;

  @override
  Widget build(BuildContext context) {
    if (productos.isEmpty) {
      return const Center(
        child: Text('No se encontraron productos'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 720 ? 2 : 1;
        final cards = [
          for (final p in productos)
            ProductoStockCard(
              producto: p,
              categorias: categorias,
              almacen: almacen,
              onAction: onAction,
            ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            children: [
              for (var i = 0; i < cards.length; i += perRow)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < (i + perRow) && j < cards.length; j++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: 12,
                              right: (j + 1) < (i + perRow) ? 12 : 0,
                            ),
                            child: cards[j],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
