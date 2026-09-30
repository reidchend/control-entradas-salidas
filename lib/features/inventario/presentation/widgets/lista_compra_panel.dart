import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/inventario_repository.dart';
import 'lista_compra_item.dart';

/// Panel "Lista de Compras" (modo toggle) con items agrupados por categoría.
class ListaCompraPanel extends ConsumerStatefulWidget {
  const ListaCompraPanel({super.key, required this.repo, required this.onClose});

  final InventarioRepository repo;
  final VoidCallback onClose;

  @override
  ConsumerState<ListaCompraPanel> createState() => _ListaCompraPanelState();
}

class _ListaCompraPanelState extends ConsumerState<ListaCompraPanel> {
  late Future<List<ComprasListaItem>> _future;

  @override
  void initState() {
    super.initState();
    // Query única por instancia: evita refetch por cada tecla del buscador.
    _future = widget.repo.getComprasListaConProductos();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ComprasListaItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 60, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('Lista de compras vacía', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Agrega productos con el botón "��� Agregar"', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        }

        // Agrupar por categoría
        final grouped = <int, List<ComprasListaItem>>{};
        for (final item in items) {
          grouped.putIfAbsent(item.categoriaId, () => []).add(item);
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final entry in grouped.entries)
              _CategoriaGroup(group: entry.value),
          ],
        );
      },
    );
  }
}

class _CategoriaGroup extends StatelessWidget {
  const _CategoriaGroup({required this.group});

  final List<ComprasListaItem> group;

  @override
  Widget build(BuildContext context) {
    final first = group.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _parseColor(first.categoriaColor).withValues(alpha: 0.15),
          child: Text(
            first.categoriaNombre,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _parseColor(first.categoriaColor),
            ),
          ),
        ),
        for (final item in group) ListaCompraItem(item: item),
      ],
    );
  }

  Color _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', '0xFF'));
    return v != null ? Color(v) : Colors.blue;
  }
}