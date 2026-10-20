import 'package:flutter/material.dart';

import '../../data/activo.dart';
import '../../data/grupo_activos.dart';

/// Hoja con el detalle unidad por unidad de un grupo.
///
/// Sirve para no perder las acciones individuales (editar, desactivar,
/// eliminar) cuando la lista principal muestra una sola tarjeta agrupada.
Future<void> showUnidadesGrupoSheet(
  BuildContext context, {
  required GrupoActivos grupo,
  required ValueChanged<Activo> onEditar,
  required Future<void> Function(Activo) onDesactivar,
  required Future<void> Function(Activo) onEliminar,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: .78,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grupo.plantilla.nombre,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${grupo.cantidad} '
                    '${grupo.cantidad == 1 ? 'unidad' : 'unidades'}'
                    '${_ubicacionTexto(grupo)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: grupo.cantidad,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 60),
                itemBuilder: (context, i) {
                  final u = grupo.unidades[i];
                  return _UnidadTile(
                    unidad: u,
                    onEditar: () {
                      Navigator.pop(ctx);
                      onEditar(u);
                    },
                    onDesactivar: () async {
                      Navigator.pop(ctx);
                      await onDesactivar(u);
                    },
                    onEliminar: () async {
                      Navigator.pop(ctx);
                      await onEliminar(u);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _ubicacionTexto(GrupoActivos grupo) {
  final u = (grupo.plantilla.ubicacion ?? '').trim();
  return u.isEmpty ? ' · Sin ubicación' : ' · $u';
}

class _UnidadTile extends StatelessWidget {
  const _UnidadTile({
    required this.unidad,
    required this.onEditar,
    required this.onDesactivar,
    required this.onEliminar,
  });

  final Activo unidad;
  final VoidCallback onEditar;
  final Future<void> Function() onDesactivar;
  final Future<void> Function() onEliminar;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final codigo = (unidad.codigo ?? '').trim();
    final detalles = [
      unidad.estado,
      if (unidad.valor > 0) 'Bs ${_fmt(unidad.valor)}',
      if ((unidad.fecha ?? '').trim().isNotEmpty) unidad.fecha!.trim(),
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Icon(Icons.qr_code_2, color: colors.primary),
      ),
      title: Text(
        codigo.isEmpty ? 'Unidad ${unidad.id}' : codigo,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        detalles,
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Acciones de la unidad',
        onSelected: (v) async {
          switch (v) {
            case 'editar':
              onEditar();
            case 'desactivar':
              await onDesactivar();
            case 'eliminar':
              await onEliminar();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'editar', child: Text('Editar')),
          if (unidad.activo)
            const PopupMenuItem(
              value: 'desactivar',
              child: Text('Desactivar'),
            ),
          PopupMenuItem(
            value: 'eliminar',
            child: Text('Eliminar', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}
