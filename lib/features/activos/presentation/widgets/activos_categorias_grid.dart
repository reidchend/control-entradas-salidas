import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activos_categoria.dart';
import '../../data/activos_repository.dart';
import '../dialogs/activos_categoria_dialog.dart';
import '../dialogs/confirmar_dialog.dart';
import 'activos_categoria_card.dart';

/// GridView de categorías de activos (estilo CategoriasGrid de Inventario).
class ActivosCategoriasGrid extends ConsumerStatefulWidget {
  const ActivosCategoriasGrid({
    super.key,
    required this.repo,
    required this.onSelect,
    required this.onCreate,
    this.onEditado,
    this.onEliminado,
  });

  final ActivosRepository repo;
  final ValueChanged<ActivosCategoria> onSelect;
  final VoidCallback onCreate;

  /// Avisos de que el catálogo cambió, para que la pantalla actualice lo que
  /// tenga seleccionado.
  final VoidCallback? onEditado;
  final ValueChanged<ActivosCategoria>? onEliminado;

  @override
  ConsumerState<ActivosCategoriasGrid> createState() =>
      _ActivosCategoriasGridState();
}

class _ActivosCategoriasGridState extends ConsumerState<ActivosCategoriasGrid> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    // Query única por instancia: evita refetch por cada tecla del buscador.
    _future = widget.repo.getCategoriasConConteo();
  }

  /// Vuelve a consultar para que el cambio se vea sin salir de la pantalla.
  void _recargar() {
    setState(() {
      _future = widget.repo.getCategoriasConConteo();
    });
  }

  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _editar(ActivosCategoria categoria) async {
    final editada = await showActivosCategoriaDialog(
      context,
      categoria: categoria,
    );
    if (editada == null || !mounted) return;
    // `nombre` es UNIQUE. Preguntar antes deja un mensaje entendible; el try/catch
    // de abajo sigue cubriendo el caso de que dos personas guarden a la vez.
    final repetida = await widget.repo.existeCategoria(
      editada.nombre,
      ignorarId: categoria.id,
    );
    if (repetida) {
      _error('Ya existe una categoría llamada "${editada.nombre}"');
      return;
    }
    setState(() => _trabajando = true);
    try {
      await widget.repo.updateCategoria(editada);
      widget.onEditado?.call();
      if (mounted) _recargar();
    } catch (e) {
      _error('Error al editar categoría: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _eliminar(ActivosCategoria categoria, int conteo) async {
    // `conteo` viene de getCategoriasConConteo, que cuenta unidades (a través de
    // los tipos), no tipos. El texto tiene que decir lo mismo.
    final unidades = conteo == 1 ? '1 unidad' : '$conteo unidades';
    final ok = await showConfirmarDialog(
      context,
      titulo: 'Eliminar categoría',
      mensaje: '¿Eliminar "${categoria.nombre}"?\n'
          'Sus tipos quedan sin categoría; las $unidades no se tocan.',
      accion: 'Eliminar',
    );
    if (!ok || !mounted) return;
    setState(() => _trabajando = true);
    try {
      await widget.repo.deleteCategoria(categoria.id);
      widget.onEliminado?.call(categoria);
      if (mounted) _recargar();
    } catch (e) {
      _error('Error al eliminar categoría: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sin filtro: solo categorías activas con su conteo de activos.
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
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
              // Se apaga mientras hay una edición en curso: si no, se podría
              // abrir un diálogo de creación encima del que ya está abierto.
              return _NuevaCategoriaCard(
                onCreate: _trabajando ? null : widget.onCreate,
              );
            }
            final item = items[i - 1];
            final categoria = item['categoria'] as ActivosCategoria;
            final conteo = item['conteo'] as int;
            return ActivosCategoriaCard(
              categoria: categoria,
              conteo: conteo,
              onTap: () => widget.onSelect(categoria),
              onEdit: _trabajando ? null : () => _editar(categoria),
              onDelete: _trabajando ? null : () => _eliminar(categoria, conteo),
            );
          },
        );
      },
    );
  }
}

class _NuevaCategoriaCard extends StatelessWidget {
  const _NuevaCategoriaCard({required this.onCreate});
  final VoidCallback? onCreate;

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
