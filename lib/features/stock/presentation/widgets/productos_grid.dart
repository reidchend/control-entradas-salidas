import 'package:flutter/material.dart';

import '../../../../core/models/existencia.dart';
import '../../../../core/models/producto.dart';
import 'producto_stock_card.dart';

/// Grid de productos de stock (porta `_render_productos` de stock_view.py).
/// 1 columna en móvil (<720px) y 2 columnas en escritorio, con las tarjetas
/// de cada fila a igual altura. Recibe las existencias agrupadas por producto
/// (una sola query) para evitar N+1.
///
/// Soporta paginación incremental: [scrollController] controla el scroll y
/// [onLoadMore] se invoca al llegar cerca del final (mientras [hasMore]).
class ProductosGrid extends StatelessWidget {
  const ProductosGrid({
    super.key,
    required this.productos,
    required this.existencias,
    required this.categorias,
    required this.onAction,
    this.scrollController,
    this.onLoadMore,
    this.hasMore = false,
    this.cargandoMas = false,
    this.almacen,
  });

  final List<Producto> productos;
  final Map<int, List<Existencia>> existencias;
  final Map<int, String> categorias;
  final String? almacen;
  final void Function(String action, Producto producto) onAction;
  final ScrollController? scrollController;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool cargandoMas;

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
              existencias: existencias[p.id] ?? const [],
              categorias: categorias,
              almacen: almacen,
              onAction: onAction,
            ),
        ];

        // Cargar otra página al llegar casi al final del scroll.
        void onScrollNotification(ScrollNotification n) {
          final m = n.metrics;
          if (m.maxScrollExtent == 0) return;
          if (m.pixels >= m.maxScrollExtent - 240 &&
              hasMore &&
              !cargandoMas) {
            onLoadMore?.call();
          }
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            onScrollNotification(n);
            return false;
          },
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                for (var i = 0; i < cards.length; i += perRow)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = i;
                            j < (i + perRow) && j < cards.length;
                            j++)
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
                if (cargandoMas)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}