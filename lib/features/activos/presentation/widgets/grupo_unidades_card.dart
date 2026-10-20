import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/grupo_activos.dart';
import 'grupo_activos_chips.dart';

/// Tarjeta de un grupo de unidades idénticas, con la cantidad y el contador.
///
/// Reemplaza a la fila por unidad: diez mesas iguales en el restaurante se ven
/// como una sola tarjeta con "10", y desde acá se agrega, se quita, se cambia
/// la cantidad o se mueven varias a otra ubicación. El detalle unidad por
/// unidad queda en "Ver unidades".
class GrupoUnidadesCard extends StatelessWidget {
  const GrupoUnidadesCard({
    super.key,
    required this.grupo,
    this.mostrarTipo = true,
    required this.onAgregar,
    required this.onQuitar,
    required this.onCantidad,
    required this.onMover,
    required this.onVerUnidades,
    required this.onEliminar,
    required this.onReactivar,
  });

  final GrupoActivos grupo;

  /// `true` en la vista filtrada: el título es la ubicación. `false` en el
  /// detalle de un tipo: el título es el nombre del tipo y la ubicación ya
  /// viene en el encabezado de la sección.
  final bool mostrarTipo;

  final VoidCallback onAgregar;
  final VoidCallback onQuitar;
  final VoidCallback onCantidad;
  final VoidCallback onMover;
  final VoidCallback onVerUnidades;
  final VoidCallback onEliminar;
  final VoidCallback onReactivar;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final a = grupo.plantilla;
    final ubicacion = (a.ubicacion ?? '').trim();
    final titulo = mostrarTipo
        ? (ubicacion.isEmpty ? 'Sin ubicación' : ubicacion)
        : a.nombre;
    final detalles = [
      if ((a.modelo ?? '').trim().isNotEmpty) a.modelo!.trim(),
      if ((a.observaciones ?? '').trim().isNotEmpty) a.observaciones!.trim(),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CantidadBadge(
                  cantidad: grupo.cantidad,
                  activo: grupo.activo,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (detalles.isNotEmpty)
                        Text(
                          detalles,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Acciones del grupo',
                  onSelected: (v) {
                    switch (v) {
                      case 'ver':
                        onVerUnidades();
                      case 'eliminar':
                        onEliminar();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'ver',
                      child: Text('Ver unidades'),
                    ),
                    PopupMenuItem(
                      value: 'eliminar',
                      child: Text(
                        'Eliminar todas',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            GrupoActivosChips(grupo: grupo),
            const SizedBox(height: 2),
            if (grupo.activo)
              _accionesActivas(colors)
            else
              _accionesInactivas(context, colors),
          ],
        ),
      ),
    );
  }

  Widget _accionesActivas(ColorScheme colors) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Quitar una unidad',
          onPressed: onQuitar,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Tooltip(
          message: 'Cambiar cantidad',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onCantidad,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                '${grupo.cantidad}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Agregar una unidad',
          onPressed: onAgregar,
          icon: const Icon(Icons.add_circle_outline),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onMover,
          icon: const Icon(Icons.drive_file_move_outlined),
          label: const Text('Mover'),
        ),
      ],
    );
  }

  Widget _accionesInactivas(BuildContext context, ColorScheme colors) {
    return Row(
      children: [
        Icon(
          Icons.pause_circle_outline,
          size: 20,
          color: appColor(context, 'warning'),
        ),
        const SizedBox(width: 6),
        Text(
          'Inactiva',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onReactivar,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reactivar'),
        ),
      ],
    );
  }
}

/// Cuadro con la cantidad grande, para que se lea de un vistazo.
class _CantidadBadge extends StatelessWidget {
  const _CantidadBadge({required this.cantidad, required this.activo});

  final int cantidad;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fondo =
        activo ? colors.primaryContainer : colors.surfaceContainerHighest;
    final texto = activo ? colors.onPrimaryContainer : colors.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$cantidad',
            style: TextStyle(
              fontSize: 19,
              height: 1,
              fontWeight: FontWeight.w800,
              color: texto,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            cantidad == 1 ? 'unidad' : 'unidades',
            style: TextStyle(fontSize: 9, height: 1, color: texto),
          ),
        ],
      ),
    );
  }
}
