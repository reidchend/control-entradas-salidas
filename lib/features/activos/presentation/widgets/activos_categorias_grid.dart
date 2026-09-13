import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activos_categoria.dart';
import '../../data/activos_repository.dart';
import 'activos_categoria_card.dart';

/// GridView de categorías de activos (estilo CategoriasGrid de Inventario).
class ActivosCategoriasGrid extends ConsumerWidget {
  const ActivosCategoriasGrid({
    super.key,
    required this.repo,
    required this.onSelect,
    required this.onCreate,
  });

  final ActivosRepository repo;
  final ValueChanged<ActivosCategoria> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sin filtro: solo categorías activas con su conteo de activos.
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.getCategoriasConConteo(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text('Error: ${snap.error}'),
          );
        }
        final items = snap.data ?? const [];

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisExtent: 120,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _NuevaCategoriaCard(onCreate: onCreate);
            }
            final item = items[i - 1];
            return ActivosCategoriaCard(
              categoria: item['categoria'] as ActivosCategoria,
              conteo: item['conteo'] as int,
              onTap: () => onSelect(item['categoria'] as ActivosCategoria),
            );
          },
        );
      },
    );
  }
}

class _NuevaCategoriaCard extends StatelessWidget {
  const _NuevaCategoriaCard({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onCreate,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 32, color: colors.primary),
            const SizedBox(height: 6),
            Text(
              'Nueva categoría',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}