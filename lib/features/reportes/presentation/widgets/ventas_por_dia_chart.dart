import 'package:flutter/material.dart';

import 'grafico_barras.dart';

/// Gráfico de barras de ventas por día. Rellena los días sin ventas con $0
/// para que la línea de tiempo no mienta, resalta el mejor día en verde y,
/// si el rango supera los 14 días, muestra solo los últimos 14 (con aviso),
/// así cada barra entra con su monto impreso.
class VentasPorDiaChart extends StatelessWidget {
  const VentasPorDiaChart({super.key, required this.datos});

  /// Filas `{fecha, total}` ordenadas por fecha ascendente
  /// (de `getTendenciaVentas`; excluye anuladas).
  final List<Map<String, dynamic>> datos;

  static const int _topeDias = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Índice por fecha (YYYY-MM-DD) + fechas parseadas.
    final porFecha = <String, double>{};
    final fechas = <DateTime>[];
    for (final f in datos) {
      final fecha = DateTime.tryParse('${f['fecha'] ?? ''}');
      if (fecha == null) continue;
      porFecha[fecha.toIso8601String().substring(0, 10)] =
          (f['total'] as num?)?.toDouble() ?? 0;
      fechas.add(fecha);
    }
    if (fechas.isEmpty) return const GraficoBarras(barras: []);

    fechas.sort();
    var desde = fechas.first;
    final hasta = fechas.last;
    var truncado = false;
    if (hasta.difference(desde).inDays >= _topeDias) {
      desde = hasta.subtract(Duration(days: _topeDias - 1));
      truncado = true;
    }

    // Mejor día del rango mostrado (para pintarlo de verde).
    double mejor = 0;
    for (var d = desde; !d.isAfter(hasta); d = d.add(const Duration(days: 1))) {
      final v = porFecha[d.toIso8601String().substring(0, 10)] ?? 0;
      if (v > mejor) mejor = v;
    }

    final barras = <DatoBarra>[];
    for (var d = desde; !d.isAfter(hasta); d = d.add(const Duration(days: 1))) {
      final clave = d.toIso8601String().substring(0, 10);
      final valor = porFecha[clave] ?? 0;
      barras.add(DatoBarra(
        etiqueta: '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}',
        valor: valor,
        destacado: mejor > 0 && valor == mejor,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GraficoBarras(barras: barras, colorBase: scheme.primary),
        if (truncado) ...[
          const SizedBox(height: 6),
          Text(
            'Mostrando los últimos $_topeDias días del período',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
