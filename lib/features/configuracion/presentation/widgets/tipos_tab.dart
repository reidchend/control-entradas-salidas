import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/tipo_producto.dart';
import '../../../../core/utils/roles_tipo_producto.dart';
import '../../data/configuracion_providers.dart';
import '../dialogs/tipo_producto_dialog.dart';

/// Pestaña Tipos: catálogo administrable de tipos de producto.
///
/// La lógica de la app (flujo de producción, colores) pregunta por ROL, no
/// por el nombre: los tipos del sistema se pueden renombrar sin romper
/// nada. Reglas:
///
/// - `'ninguno'` (default del modelo): fijo, no se toca.
/// - Tipos con rol (producción, feria, venta…): renombrables, no
///   inactivables (los flujos deben poder seguir dando de alta productos).
/// - Tipos libres: renombrables, inactivables/reactivables.
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
                  'Los tipos con escudo (🛡) ligan flujos del sistema por '
                  'ROL, no por nombre: se pueden renombrar sin romper nada. '
                  'Solo no se pueden inactivar.',
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
                  onRename: tipos[i].rol == RolesTipoProducto.ninguno
                      ? null
                      : () => _renombrar(context, ref, tipos, tipos[i]),
                  onToggle: tipos[i].esDelSistema
                      ? null
                      : (v) => _setActivo(context, ref, tipos[i], v),
                  onEsInsumo: (v) => _setEsInsumo(context, ref, tipos[i], v),
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
    final tipos = ref.read(tiposProductoConfigProvider).valueOrNull ??
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

  Future<void> _setActivo(BuildContext context, WidgetRef ref,
      TipoProducto tipo, bool activo) async {
    final repo = ref.read(configuracionRepoProvider)!;
    try {
      await repo.setTipoProductoActivo(tipo, activo);
      ref.invalidate(tiposProductoConfigProvider);
    } catch (e) {
      ref.invalidate(tiposProductoConfigProvider); // revierte el switch
      _snack(context, 'No se pudo cambiar: $e');
    }
  }

  Future<void> _setEsInsumo(BuildContext context, WidgetRef ref,
      TipoProducto tipo, bool esInsumo) async {
    final repo = ref.read(configuracionRepoProvider)!;
    try {
      await repo.setTipoProductoEsInsumo(tipo, esInsumo);
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
    required this.onEsInsumo,
    this.onRename,
    this.onToggle,
  });

  final TipoProducto tipo;
  final ColorScheme scheme;
  final ValueChanged<bool> onEsInsumo;
  final VoidCallback? onRename;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final esDefault = tipo.rol == RolesTipoProducto.ninguno;
    final delSistema = tipo.esDelSistema && !esDefault;

    final icono = esDefault
        ? Icons.lock_outline
        : (delSistema ? Icons.shield_outlined : Icons.label_outline);
    final colorIcono = esDefault
        ? scheme.onSurfaceVariant
        : (delSistema ? scheme.tertiary : scheme.primary);

    final subtitulo = esDefault
        ? 'Default del sistema · ${tipo.enUso} producto(s)'
        : delSistema
            ? 'Liga flujos del sistema (por rol) · ${tipo.enUso} producto(s)'
            : '${tipo.enUso} producto(s) lo usan';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 22, color: colorIcono),
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
                        subtitulo,
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
                if (onRename != null)
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: scheme.primary),
                    tooltip: 'Renombrar',
                    onPressed: onRename,
                  ),
                if (onToggle != null)
                  Switch(
                    value: tipo.activo,
                    onChanged: onToggle,
                  ),
              ],
            ),
            // Capability administrable: define qué tipos alimentan el
            // selector de ingredientes de los platos del POS.
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text(
                'Puede ser ingrediente de platos',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              value: tipo.esInsumo,
              onChanged: onEsInsumo,
            ),
          ],
        ),
      ),
    );
  }
}
