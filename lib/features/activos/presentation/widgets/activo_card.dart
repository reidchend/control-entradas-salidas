import 'package:flutter/material.dart';

import '../../data/activo.dart';

/// Card de una unidad física de activo (ubicación, estado, valor, fecha).
///
/// Con [mostrarTipo] en true el título es el nombre del tipo (útil en vistas
/// filtradas que agrupan varios tipos); en false el título es la ubicación
/// de la unidad (útil dentro del detalle de un tipo).
class ActivoCard extends StatelessWidget {
  const ActivoCard({
    super.key,
    required this.activo,
    this.mostrarTipo = true,
    required this.onEdit,
    required this.onDeactivate,
    required this.onDelete,
  });

  final Activo activo;
  final bool mostrarTipo;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ubicacion = (activo.ubicacion ?? '').trim();
    final lider = activo.estado.toLowerCase() == 'activo'
        ? colors.primary
        : Colors.orange.shade700;

    final titulo = mostrarTipo
        ? activo.nombre
        : ubicacion.isNotEmpty
            ? ubicacion
            : 'Sin ubicación';
    final subtexto = mostrarTipo ? ubicacion : (activo.observaciones ?? '').trim();

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
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtexto.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Icon(Icons.place_outlined,
                        size: 14, color: colors.outline),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      subtexto,
                      style: TextStyle(
                          fontSize: 12.5, color: colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                _chip(context, activo.estado, color: lider),
                if (activo.valor > 0)
                  _chip(context, 'Bs ${_fmtValor(activo.valor)}',
                      color: colors.secondary),
                if ((activo.fecha ?? '').trim().isNotEmpty)
                  _chip(context, activo.fecha!.trim(),
                      color: colors.onSurfaceVariant),
              ],
            ),
          ],
        ),
        isThreeLine: mostrarTipo || subtexto.isNotEmpty,
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

  String _fmtValor(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
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