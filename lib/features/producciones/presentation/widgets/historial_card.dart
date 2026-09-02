import 'package:flutter/material.dart';

import '../../data/producciones_repository.dart';

/// Card de historial con estado y desglose salidas/entradas (porta
/// `build_historial_tab` de `historial_view.py`).
class HistorialCard extends StatelessWidget {
  const HistorialCard({
    super.key,
    required this.produccion,
    required this.salidas,
    required this.entradas,
  });

  final ProduccionInfo produccion;
  final List<DetalleInfo> salidas;
  final List<DetalleInfo> entradas;

  String _fmtFecha(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estado = produccion.estado;
    final Color estadoColor;
    final IconData estadoIcon;
    if (estado == 'cancelada') {
      estadoColor = scheme.error;
      estadoIcon = Icons.cancel_outlined;
    } else if (estado == 'pendiente') {
      estadoColor = Colors.orange;
      estadoIcon = Icons.pending_actions;
    } else {
      estadoColor = Colors.green;
      estadoIcon = Icons.check_circle_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(estadoIcon, color: estadoColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    produccion.recetaNombre,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _estadoBadge(estado.toUpperCase(), estadoColor),
                const SizedBox(width: 8),
                Text(
                  'x${_fmtCant(produccion.cantidad)}',
                  style: TextStyle(
                      fontSize: 14,
                      color: scheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              _fmtFecha(produccion.fechaProduccion),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            Text(
              'Por: ${produccion.usuario ?? 'Sistema'}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (produccion.cocineros != null &&
                produccion.cocineros!.trim().isNotEmpty)
              Text(
                'Cocineros: ${produccion.cocineros}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _listaDetalles(
                    scheme,
                    'Salidas: ${salidas.length}',
                    Colors.orange,
                    salidas,
                    prefixo: '-',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _listaDetalles(
                    scheme,
                    'Entradas: ${entradas.length}',
                    Colors.green,
                    entradas,
                    prefixo: '+',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaDetalles(
    ColorScheme scheme,
    String titulo,
    Color color,
    List<DetalleInfo> detalles, {
    required String prefixo,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
        for (final d in detalles.take(3))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '  $prefixo ${d.productoNombre} x${_fmtCant(d.cantidad)} ${d.unidad}'
                  .trimRight(),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _estadoBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  String _fmtCant(double c) {
    if (c == c.roundToDouble()) return c.toInt().toString();
    return c.toStringAsFixed(3);
  }
}
