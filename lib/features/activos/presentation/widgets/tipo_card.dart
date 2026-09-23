import 'package:flutter/material.dart';

import '../../data/activo_tipo.dart';

/// Card de un tipo del catálogo con su conteo de unidades. Muestra la
/// identidad (nombre, grupo, modelo) y permite entrar al detalle, agregar
/// una unidad o editar/desactivar/eliminar el tipo.
class TipoCard extends StatelessWidget {
  const TipoCard({
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Icon(Icons.category_outlined, color: colors.primary),
        ),
        title: Text(
          tipo.nombre,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  chips.join(' · '),
                  style: TextStyle(
                      fontSize: 12.5, color: colors.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Row(
              children: [
                _conteo(context, unidades, colors),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'unidad':
                onAgregarUnidad?.call();
              case 'editar':
                onEdit?.call();
              case 'desactivar':
                onDeactivate?.call();
              case 'eliminar':
                onDelete?.call();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'unidad', child: Text('Agregar unidad')),
            const PopupMenuItem(value: 'editar', child: Text('Editar')),
            const PopupMenuItem(
                value: 'desactivar', child: Text('Desactivar')),
            const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }

  static Widget _conteo(BuildContext context, int n, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$n ${n == 1 ? 'unidad' : 'unidades'}',
        style: TextStyle(
            fontSize: 11, color: colors.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}