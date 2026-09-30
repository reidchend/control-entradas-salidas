import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/categoria.dart';
import '../../data/inventario_repository.dart';
import 'categoria_card.dart';

/// GridView de categorías estilo Flet.
/// Al hacer click en una categoría se navega a sus productos (manejado por la pantalla vía `onSelect`).
class CategoriasGrid extends ConsumerStatefulWidget {
  const CategoriasGrid({
    super.key,
    required this.repo,
    required this.searchTerm,
    required this.onSelect,
  });

  final InventarioRepository repo;
  final String searchTerm;
  final ValueChanged<Categoria> onSelect;

  @override
  ConsumerState<CategoriasGrid> createState() => _CategoriasGridState();
}

class _CategoriasGridState extends ConsumerState<CategoriasGrid> {
  late Future<List<Categoria>> _future;

  @override
  void initState() {
    super.initState();
    // Query única por instancia: evita refetch por cada tecla del buscador.
    _future = widget.repo.getAllCategorias();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Categoria>>(
      future: _future,
      builder: (context, snap) {
        var cats = snap.data ?? [];
        if (cats.isEmpty) {
          return const Center(child: Text('Sin categorías'));
        }
        if (widget.searchTerm.isNotEmpty) {
          final q = widget.searchTerm.toLowerCase();
          cats = cats.where((c) => c.nombre.toLowerCase().contains(q)).toList();
        }
        if (cats.isEmpty) {
          return const Center(child: Text('Sin resultados'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
            mainAxisExtent: 150,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: cats.length,
          itemBuilder: (context, i) => CategoriaCard(
            nombre: cats[i].nombre,
            color: cats[i].color,
            onTap: () => widget.onSelect(cats[i]),
          ),
        );
      },
    );
  }
}