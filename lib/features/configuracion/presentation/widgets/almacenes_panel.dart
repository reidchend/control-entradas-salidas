import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/almacen.dart';
import '../../data/configuracion_providers.dart'
    show
        configuracionRepoProvider,
        almacenesAdminProvider,
        almacenesConfigProvider,
        almacenProduccionDefaultProvider;
import '../dialogs/almacen_dialog.dart';

/// Panel de administración de almacenes (CRUD) para Configuración → Sistema.
class AlmacenesPanel extends ConsumerWidget {
  const AlmacenesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final almacenesAsync = ref.watch(almacenesAdminProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Gestiona los almacenes del sistema. El almacén principal '
                'guarda existencias sin uso.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo'),
              onPressed: () => _crearAlmacen(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 12),
        almacenesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e', style: TextStyle(color: scheme.error)),
          data: (almacenes) {
            if (almacenes.isEmpty) {
              return Text('Sin almacenes',
                  style: TextStyle(color: scheme.onSurfaceVariant));
            }
            return Column(
              children: [
                for (final a in almacenes)
                  _AlmacenTile(
                    almacen: a,
                    scheme: scheme,
                    onEdit: () => _editarAlmacen(context, ref, a),
                    onDelete: () => _eliminarAlmacen(context, ref, a),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _crearAlmacen(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(configuracionRepoProvider)!;
    final saved = await showAlmacenDialog(context, repo: repo);
    if (saved == true) _invalidar(ref);
  }

  Future<void> _editarAlmacen(
      BuildContext context, WidgetRef ref, Almacen a) async {
    final repo = ref.read(configuracionRepoProvider)!;
    final saved = await showAlmacenDialog(
      context,
      repo: repo,
      almacen: a,
      nombreViejo: a.nombre,
    );
    if (saved == true) _invalidar(ref);
  }

  Future<void> _eliminarAlmacen(
      BuildContext context, WidgetRef ref, Almacen a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar almacén'),
        content: Text('¿Eliminar "${a.nombre}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final repo = ref.read(configuracionRepoProvider)!;
    final (ok, msg) = await repo.eliminarAlmacen(a);
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Almacén eliminado')));
      _invalidar(ref);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  void _invalidar(WidgetRef ref) {
    ref.invalidate(almacenesAdminProvider);
    ref.invalidate(almacenesConfigProvider);
    ref.invalidate(almacenProduccionDefaultProvider);
  }
}

class _AlmacenTile extends StatelessWidget {
  const _AlmacenTile({
    required this.almacen,
    required this.scheme,
    required this.onEdit,
    required this.onDelete,
  });

  final Almacen almacen;
  final ColorScheme scheme;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              almacen.activo ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          child: Icon(Icons.warehouse,
              color: almacen.activo ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
        ),
        title: Text(almacen.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (almacen.descripcion?.isNotEmpty == true)
              Text(almacen.descripcion!, style: const TextStyle(fontSize: 12)),
            Text(
              almacen.activo ? 'Activo' : 'Inactivo',
              style: TextStyle(
                fontSize: 11,
                color: almacen.activo ? Colors.green : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit_outlined, color: scheme.primary),
              tooltip: 'Editar / Renombrar',
              onPressed: onEdit,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: scheme.error),
              tooltip: 'Eliminar',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}