import 'package:flutter/material.dart';

import 'kpi_grid.dart';
import 'ventas_por_dia_chart.dart';
import 'ventas_por_hora_chart.dart';
import 'top_productos_ranking.dart';

/// Cuerpo de la pantalla de estadísticas: tarjetas de KPI, los dos rankings
/// de productos (facturación y cantidad), el gráfico de ventas por día y el
/// de ventas por hora. Recibe los datos ya cargados; no consulta nada.
class EstadisticasCuerpo extends StatelessWidget {
  const EstadisticasCuerpo({
    super.key,
    required this.kpis,
    required this.topFacturacion,
    required this.topCantidad,
    required this.tendencia,
    required this.porHora,
  });

  /// KPIs agregados (ya excluidas las ventas anuladas en el repositorio).
  final Map<String, dynamic> kpis;

  /// Rankings de productos ya ordenados de mayor a menor.
  final List<Map<String, dynamic>> topFacturacion;
  final List<Map<String, dynamic>> topCantidad;

  /// Tendencia `{fecha, total}` ordenada por fecha ascendente.
  final List<Map<String, dynamic>> tendencia;

  /// Ventas `{hora, total}` de las horas que tuvieron ventas.
  final List<Map<String, dynamic>> porHora;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final variante = Theme.of(context).colorScheme.onSurfaceVariant;
    final subtitulo = TextStyle(color: variante);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('KPIs Principales', style: texto.titleLarge),
        const SizedBox(height: 4),
        Text('Las ventas anuladas están excluidas',
            style: texto.bodySmall?.copyWith(color: variante)),
        const SizedBox(height: 16),
        KpiGrid(kpis: _kpisDatos()),
        const SizedBox(height: 32),
        Text('Top Productos', style: texto.titleLarge),
        const SizedBox(height: 4),
        Text('Ranking por facturación y por cantidad vendida',
            style: texto.bodySmall?.copyWith(color: variante)),
        const SizedBox(height: 16),
        _RankingsLayout(
            topFacturacion: topFacturacion, topCantidad: topCantidad),
        const SizedBox(height: 32),
        Text('Ventas por Día', style: texto.titleLarge),
        const SizedBox(height: 4),
        Text('Monto facturado cada día · el mejor día va en verde',
            style: texto.bodySmall?.copyWith(color: variante)),
        const SizedBox(height: 16),
        VentasPorDiaChart(datos: tendencia),
        const SizedBox(height: 32),
        Text('Ventas por Hora', style: texto.titleLarge),
        const SizedBox(height: 4),
        Text('Pic de venta a lo largo del día (0-23 h) · la hora pico, en verde',
            style: texto.bodySmall?.copyWith(color: variante)),
        const SizedBox(height: 16),
        VentasPorHoraChart(datos: porHora),
      ],
    );
  }

  List<KpiDato> _kpisDatos() {
    final mejor = _mejorDia();
    return [
      KpiDato('Ventas Totales', _fmtMoneda(kpis['total_ventas'] ?? 0),
          Icons.attach_money, Colors.green),
      KpiDato('Ticket Promedio', _fmtMoneda(kpis['ticket_promedio'] ?? 0),
          Icons.receipt_long, Colors.blue),
      KpiDato('Comandas', '${kpis['num_comandas'] ?? 0}',
          Icons.point_of_sale, Colors.purple),
      KpiDato('Unidades Vendidas', '${kpis['productos_vendidos'] ?? 0}',
          Icons.inventory_2, Colors.orange),
      KpiDato('Ventas Anuladas', '${kpis['num_anuladas'] ?? 0}',
          Icons.cancel_presentation, Colors.red),
      KpiDato('Mejor Día · ${_fmtMoneda(mejor.total)}', mejor.fecha,
          Icons.trending_up, Colors.teal),
    ];
  }

  /// Día con mayor facturación del período (de la tendencia ya cargada).
  ({String fecha, double total}) _mejorDia() {
    if (tendencia.isEmpty) return (fecha: '—', total: 0);
    final mejor = tendencia.reduce((a, b) {
      final ta = (a['total'] as num?)?.toDouble() ?? 0;
      final tb = (b['total'] as num?)?.toDouble() ?? 0;
      return tb > ta ? b : a;
    });
    final fecha = mejor['fecha'] as String? ?? '';
    final corta = fecha.length >= 10
        ? '${fecha.substring(8, 10)}/${fecha.substring(5, 7)}'
        : '—';
    return (fecha: corta, total: (mejor['total'] as num?)?.toDouble() ?? 0);
  }

  static String _fmtMoneda(dynamic v) =>
      '\$${((v is num) ? v.toDouble() : 0).toStringAsFixed(2)}';
}

/// Los dos rankings lado a lado en pantallas anchas (>= 900 px), apilados
/// uno debajo del otro en móviles.
class _RankingsLayout extends StatelessWidget {
  const _RankingsLayout({
    required this.topFacturacion,
    required this.topCantidad,
  });

  final List<Map<String, dynamic>> topFacturacion;
  final List<Map<String, dynamic>> topCantidad;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final porFacturacion = TopProductosRanking(
          titulo: 'Top por Facturación',
          icono: Icons.attach_money,
          color: Colors.green.shade700,
          metrica: TopMetrica.facturacion,
          productos: topFacturacion,
        );
        final porCantidad = TopProductosRanking(
          titulo: 'Top por Cantidad',
          icono: Icons.inventory_2,
          color: Colors.orange.shade700,
          metrica: TopMetrica.cantidad,
          productos: topCantidad,
        );
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: porFacturacion),
              const SizedBox(width: 16),
              Expanded(child: porCantidad),
            ],
          );
        }
        return Column(
          children: [
            porFacturacion,
            const SizedBox(height: 16),
            porCantidad,
          ],
        );
      },
    );
  }
}
