import 'package:flutter/material.dart';

import '../../data/producciones_repository.dart';

/// Card de producción pendiente con acciones Descargar/Cancelar (porta
/// `build_pendientes_tab` de `pendientes_view.py`).
class PendienteCard extends StatelessWidget {
  const PendienteCard({
    super.key,
    required this.produccion,
    required this.entradas,
    required this.onDescargar,
    required this.onCancelar,
  });

  final ProduccionInfo produccion;
  final List<DetalleInfo> entradas;
  final VoidCallback onDescargar;
  final VoidCallback onCancelar;

  String _fmtFecha(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entradasTxt = entradas.isEmpty
        ? 'Sin detalles de entrada'
        : entradas
            .map((d) => '${d.productoNombre}: ${_fmtCant(d.cantidad)} ${d.unidad}')
            .join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions, color: Colors.orange, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        produccion.recetaNombre,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Producción #${produccion.id} · ${_fmtFecha(produccion.fechaProduccion)}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        'Por: ${produccion.usuario ?? 'Sistema'}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'x${_fmtCant(produccion.cantidad)}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Entradas del lote (${entradas.length}): $entradasTxt',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Descargar'),
                  onPressed: onDescargar,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancelar'),
                  onPressed: onCancelar,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtCant(double c) {
    if (c == c.roundToDouble()) return c.toInt().toString();
    return c.toStringAsFixed(3);
  }
}
