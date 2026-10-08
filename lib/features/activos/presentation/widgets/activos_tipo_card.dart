import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';

/// Card de tipo de activo para la grilla principal (estilo tarjeta de
/// categoría). Muestra el nombre, grupo · modelo, el conteo de unidades y un
/// menú con las acciones del catálogo (agregar unidad, editar, desactivar,
/// eliminar).
class ActivosTipoCard extends StatelessWidget {
  const ActivosTipoCard({
    super.key,
    required this.tipo,
    required this.unidades,
    this.onOpen,
    this.onAgregarUnidad,
    this.onEdit,
    this.onDeactivate,
    this.onDelete,
  });

  final ActivoTipo tipo;
  final int unidades;
  final VoidCallback? onOpen;
  final VoidCallback? onAgregarUnidad;
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chips = <String>[
      if ((tipo.grupo ?? '').trim().isNotEmpty) tipo.grupo!.trim(),
      if ((tipo.modelo ?? '').trim().isNotEmpty) tipo.modelo!.trim(),
    ];

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 158,
          height: 124,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colors.surfaceContainerHighest.withValues(alpha: .35),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 20, color: colors.primary),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$unidades',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                tipo.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chips.isEmpty ? 'Sin grupo' : chips.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: colors.onSurfaceVariant),
                    ),
                  ),
                  if (onAgregarUnidad != null ||
                      onEdit != null ||
                      onDeactivate != null ||
                      onDelete != null)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      constraints: const BoxConstraints(),
                      tooltip: 'Acciones',
                      itemBuilder: (_) => [
                        if (onAgregarUnidad != null)
                          const PopupMenuItem(
                              value: 'unidad', child: Text('Agregar unidad')),
                        if (onEdit != null)
                          const PopupMenuItem(
                              value: 'editar', child: Text('Editar tipo')),
                        if (onDeactivate != null)
                          const PopupMenuItem(
                              value: 'desactivar', child: Text('Desactivar')),
                        if (onDelete != null)
                          const PopupMenuItem(
                              value: 'eliminar', child: Text('Eliminar')),
                      ],
                      onSelected: (v) {
                        if (v == 'unidad') onAgregarUnidad?.call();
                        if (v == 'editar') onEdit?.call();
                        if (v == 'desactivar') onDeactivate?.call();
                        if (v == 'eliminar') onDelete?.call();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}