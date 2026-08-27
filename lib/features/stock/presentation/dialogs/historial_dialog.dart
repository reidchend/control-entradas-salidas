import 'package:flutter/material.dart';

import '../../../../core/models/movimiento.dart';

const Map<String, (String, Color)> _tipoLabels = {
  'entrada': ('Entrada', Colors.green),
  'salida': ('Salida', Colors.red),
  'ajuste': ('Ajuste', Color(0xFFFB8C00)),
  'tr_entrada': ('Tr. Entrada', Colors.blue),
  'tr_salida': ('Tr. Salida', Colors.indigo),
  'validacion': ('Validación', Colors.green),
  'venta': ('Venta', Colors.green),
  'devolucion': ('Devolución', Colors.blue),
  'entrada_produccion': ('Ent. Producción', Colors.green),
  'salida_produccion': ('Sal. Producción', Colors.red),
};

const Set<String> _tiposSalida = {'salida', 'salida_produccion', 'venta'};

/// Diálogo de historial de movimientos (porta `build_historial_dialog` de
/// `usr/views/common/movimientos.py`).
Future<void> showHistorialDialog(
  BuildContext context, {
  required String titulo,
  required List<Movimiento> movimientos,
  required bool esPesable,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 520,
        child: movimientos.isEmpty
            ? const Text('No hay movimientos para este producto')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: movimientos.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MovimientoCard(
                    m: movimientos[i],
                    esPesable: esPesable,
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

/// Tarjeta de movimiento (porta `build_movimiento_card`).
class _MovimientoCard extends StatelessWidget {
  const _MovimientoCard({required this.m, required this.esPesable});

  final Movimiento m;
  final bool esPesable;

  String _fmt(DateTime? d) {
    if (d == null) return '';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  /// Muestra la cantidad real (hasta 3 decimales) sin ceros redundantes.
  String _fmtNum(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tipo = m.tipo;
    final (label, color) = _tipoLabels[tipo] ?? (tipo.isEmpty ? '?' : tipo, scheme.outline);

    var cantMedio = m.cantidad;
    var unidadMedio = '';
    if (esPesable && tipo != 'ajuste' && m.pesoTotal > 0) {
      cantMedio = m.pesoTotal;
      unidadMedio = 'kg';
    }
    if (_tiposSalida.contains(tipo)) {
      cantMedio = -cantMedio.abs();
    }

    final sign = cantMedio >= 0 ? '+' : '';
    final signColor = cantMedio >= 0 ? Colors.green : scheme.error;
    final infoParts = [m.registradoPor ?? '?', if (m.almacen != null) m.almacen!];
    final obs = (m.observaciones ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_fmt(m.fechaMovimiento),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Text(
            infoParts.join(' · '),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          if (obs.isNotEmpty)
            Text(
              obs,
              style: TextStyle(fontSize: 9, color: scheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _fmtNum(m.cantidadAnterior),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
                Text('→',
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                Expanded(
                  child: Text(
                    '$sign${_fmtNum(cantMedio)} $unidadMedio'.trim(),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: signColor),
                  ),
                ),
                Text('→',
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                Expanded(
                  child: Text(
                    _fmtNum(m.cantidadNueva),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
