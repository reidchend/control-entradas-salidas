import 'package:flutter/material.dart';

import '../../data/activo.dart';

/// Card individual de activo con acciones (editar, desactivar, eliminar).
class ActivoCard extends StatelessWidget {
  const ActivoCard({
    super.key,
    required this.activo,
    required this.onEdit,
    required this.onDeactivate,
    required this.onDelete,
  });

  final Activo activo;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lider = activo.estado.toLowerCase() == 'activo'
        ? colors.primary
        : Colors.orange.shade700;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Icon(Icons.inventory_2_outlined, color: colors.primary),
        ),
        title: Text(
          activo.nombre,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((activo.grupo ?? '').isNotEmpty)
              Text('Grupo: ${activo.grupo}')
            else
              Text(
                  '${activo.categoria ?? 'Sin categoría'} · ${activo.ubicacion ?? 'Sin ubicación'}'),
            Row(
              children: [
                _chip(context, activo.estado, color: lider),
                if (activo.cantidad > 1)
                  _chip(context, 'x${activo.cantidad}', color: colors.secondary),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'editar':
                onEdit();
              case 'desactivar':
                onDeactivate();
              case 'eliminar':
                onDelete();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'editar', child: Text('Editar')),
            const PopupMenuItem(value: 'desactivar', child: Text('Desactivar')),
            const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text, {required Color color}) {
    return Container(
      margin: const EdgeInsets.only(top: 4, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}