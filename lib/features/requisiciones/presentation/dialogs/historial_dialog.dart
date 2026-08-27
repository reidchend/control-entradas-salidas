import 'package:flutter/material.dart';

import '../../data/requisiciones_repository.dart';

const String _todosAlmacenes = 'TODOS';

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

Future<void> showHistorialAuditoria(
  BuildContext context, {
  required RequisicionesRepository repo,
  required int productoId,
  required String nombre,
  required bool esPesable,
}) async {
  final movs = await repo.getMovimientosProducto(productoId);
  if (!context.mounted) return;
  if (movs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay movimientos para este producto')),
    );
    return;
  }

  final almacenes =
      movs.map((m) => m['almacen'] as String?).whereType<String>().toSet().toList()
        ..sort();
  String seleccion;
  String titulo;
  if (almacenes.length > 1) {
    final elegido = await _preguntarAlmacen(context, nombre, almacenes);
    if (elegido == null || !context.mounted) return;
    seleccion = elegido;
  } else {
    seleccion = almacenes.isEmpty ? _todosAlmacenes : almacenes.first;
  }

  if (seleccion == _todosAlmacenes) {
    titulo = 'Historial: $nombre';
  } else {
    titulo = 'Historial: $nombre - $seleccion';
  }

  final filtrados = seleccion == _todosAlmacenes
      ? movs
      : movs.where((m) => m['almacen'] == seleccion).toList();
  filtrados.sort((a, b) {
    final da = DateTime.tryParse(a['fecha_movimiento']?.toString() ?? '') ?? DateTime(0);
    final db = DateTime.tryParse(b['fecha_movimiento']?.toString() ?? '') ?? DateTime(0);
    return db.compareTo(da);
  });

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 520,
        child: filtrados.isEmpty
            ? const Text('Sin movimientos')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: filtrados.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MovimientoCard(m: filtrados[i], esPesable: esPesable),
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

Future<String?> _preguntarAlmacen(
    BuildContext context, String nombre, List<String> almacenes) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Almacén de $nombre'),
      children: [
        for (final a in almacenes)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, a),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(a),
            ),
          ),
      ],
    ),
  );
}

class _MovimientoCard extends StatelessWidget {
  const _MovimientoCard({required this.m, required this.esPesable});

  final Map<String, dynamic> m;
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
    final tipo = (m['tipo'] as String?) ?? '';
    final (label, color) =
        _tipoLabels[tipo] ?? (tipo.isEmpty ? '?' : tipo, scheme.outline);
    final fecha = DateTime.tryParse(m['fecha_movimiento']?.toString() ?? '');
    final cantidad = (m['cantidad'] as num?)?.toDouble() ?? 0;
    final pesoTotal = (m['peso_total'] as num?)?.toDouble() ?? 0;
    final cantAnterior = (m['cantidad_anterior'] as num?)?.toDouble() ?? 0;
    final cantNueva = (m['cantidad_nueva'] as num?)?.toDouble() ?? 0;
    final registradoPor = m['registrado_por'] as String?;
    final almacen = m['almacen'] as String?;
    final observaciones = m['observaciones'] as String?;

    var cantMedio = cantidad;
    var unidadMedio = '';
    if (esPesable && tipo != 'ajuste' && pesoTotal > 0) {
      cantMedio = pesoTotal;
      unidadMedio = 'kg';
    }
    if (_tiposSalida.contains(tipo)) {
      cantMedio = -cantMedio.abs();
    }

    final sign = cantMedio >= 0 ? '+' : '';
    final signColor = cantMedio >= 0 ? Colors.green : scheme.error;
    final infoParts = [registradoPor ?? '?', if (almacen != null) almacen];
    final obs = (observaciones ?? '').trim();

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
              Text(_fmt(fecha),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration:
                    BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
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
                    _fmtNum(cantAnterior),
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
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: signColor),
                  ),
                ),
                Text('→',
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                Expanded(
                  child: Text(
                    _fmtNum(cantNueva),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onSurface),
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
