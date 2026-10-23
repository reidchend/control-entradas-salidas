import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/tipo_producto.dart';
import '../../data/configuracion_providers.dart';
import '../dialogs/tipo_producto_dialog.dart';

/// Pestaña Tipos: catálogo administrable de tipos de producto.
///
/// Los tipos protegidos ('producción', 'feria', 'Productos para la venta',
/// 'ninguno') son los de los que depende la lógica de la app (colores del
/// stock, flujo de producción, default del modelo): solo se listan, no se
/// editan. El resto se puede renombrar (el cambio arrastra a los productos
/// que lo usan) e inactivar (desaparece del alta de productos; los
/// existentes lo conservan).
class TiposTab extends ConsumerWidget {
  const TiposTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tiposAsync = ref.watch(tiposProductoConfigProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Los tipos del sistema (🔒) no se editan para no romper '
                  'los flujos que dependen de ellos.',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo tipo'),
                onPressed: () => _crear(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: tiposAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: scheme.error))),
            data: (tipos) {
              if (tipos.isEmpty) {
                return Center(
                  child: Text('No hay tipos registrados',
                      style:
                          TextStyle(color: scheme.onSurfaceVariant)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tipos.length,
                itemBuilder: (context, i) => _TipoCard(
                  tipo: tipos[i],
                  scheme: scheme,
                  onRename: () => _renombrar(context, ref, tipos, tipos[i]),
                  onToggle: (v) => _setActivo(context, ref, tipos[i], v),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _crear(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(configuracionRepoProvider)!;
    final tipos =
        ref.read(tiposProductoConfigProvider).valueOrNull ??
            const <TipoProducto>[];
    final nombre = await showTipoProductoDialog(
      context,
      nombresExistentes: [for (final t in tipos) t.nombre],
    );
    if (nombre == null || !context.mounted) return;
    try {
      await repo.crearTipoProducto(nombre);
      ref.invalidate(tiposProductoConfigProvider);
    } catch (e) {
      _snack(context, 'No se pudo crear el tipo: $e');
    }
  }

  Future<void> _renombrar(BuildContext context, WidgetRef ref,
      List<TipoProducto> tipos, TipoProducto tipo) async {
    final repo = ref.read(configuracionRepoProvider)!;
    final nombre = await showTipoProductoDialog(
      context,
      nombresExistentes: [
        for (final t in tipos)
          if (t.id != tipo.id) t.nombre,
      ],
      tipo: tipo,
    );
    if (nombre == null || !context.mounted) return;
    try {
      await repo.renombrarTipoProducto(tipo, nombre);
      ref.invalidate(tiposProductoConfigProvider);
      // Los productos cambiaron de tipo: refresca la lista de Productos.
      ref.invalidate(productosConfigProvider);
      if (context.mounted) _snack(context, 'Tipo renombrado: $nombre');
    } catch (e) {
      _snack(context, 'No se pudo renombrar: $e');
    }
  }

  Future<void> _setActivo(
      BuildContext context, WidgetRef ref, TipoProducto tipo, bool activo) async {
    final repo = ref.read(configuracionRepoProvider)!;
    try {
      await repo.setTipoProductoActivo(tipo, activo);
      ref.invalidate(tiposProductoConfigProvider);
    } catch (e) {
      ref.invalidate(tiposProductoConfigProvider); // revierte el switch
      _snack(context, 'No se pudo cambiar: $e');
    }
  }

  void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _TipoCard extends StatelessWidget {
  const _TipoCard({
    required this.tipo,
    required this.scheme,
    required this.onRename,
    required this.onToggle,
  });

  final TipoProducto tipo;
  final ColorScheme scheme;
  final VoidCallback onRename;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final protegido = tipo.protegido;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              protegido ? Icons.lock_outline : Icons.label_outline,
              size: 22,
              color: protegido
                  ? scheme.onSurfaceVariant
                  : scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tipo.nombre,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    protegido
                        ? 'Tipo del sistema · ${tipo.enUso} producto(s)'
                        : '${tipo.enUso} producto(s) lo usan',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!tipo.activo)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'INACTIVO',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: scheme.onErrorContainer),
                ),
              ),
            if (!protegido) ...[
              IconButton(
                icon: Icon(Icons.edit_outlined, color: scheme.primary),
                tooltip: 'Renombrar',
                onPressed: onRename,
              ),
              Switch(
                value: tipo.activo,
                onChanged: onToggle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
