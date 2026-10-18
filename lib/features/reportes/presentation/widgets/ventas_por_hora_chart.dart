import 'package:flutter/material.dart';

import 'grafico_barras.dart';

/// Gráfico de barras de ventas por hora del día (0-23 h) para ver los
/// picos de venta. La hora con más facturación queda resaltada en verde.
class VentasPorHoraChart extends StatelessWidget {
  const VentasPorHoraChart({super.key, required this.datos});

  /// Filas `{hora, total}` con las horas que tuvieron ventas
  /// (de `getVentasPorHora`; excluye anuladas).
  final List<Map<String, dynamic>> datos;

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) return const GraficoBarras(barras: []);
    final scheme = Theme.of(context).colorScheme;

    final porHora = <int, double>{};
    for (final f in datos) {
      final hora = switch (f['hora']) {
        final num h => h.toInt(),
        final String s => int.tryParse(s) ?? -1,
        _ => -1,
      };
      if (hora < 0 || hora > 23) continue;
      porHora[hora] = (f['total'] as num?)?.toDouble() ?? 0;
    }
    if (porHora.isEmpty) return const GraficoBarras(barras: []);

    double pico = 0;
    for (final v in porHora.values) {
      if (v > pico) pico = v;
    }

    return GraficoBarras(
      barras: [
        for (var h = 0; h < 24; h++)
          DatoBarra(
            etiqueta: '${h.toString().padLeft(2, '0')}h',
            valor: porHora[h] ?? 0,
            destacado: pico > 0 && porHora[h] == pico,
          ),
      ],
      colorBase: scheme.tertiary,
      etiquetasMaximas: 12,
      vacioTexto: 'Sin ventas en el período',
    );
  }
}
