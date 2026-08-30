import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ventas_report_screen.dart';
import 'movimientos_report_screen.dart';
import 'estadisticas_report_screen.dart';
import 'cierres_screen.dart';

/// Pantalla principal de Reportes: dashboard con botones grandes.
class ReportesScreen extends ConsumerWidget {
  const ReportesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            final esMovil = ancho < 600;
            final columns = esMovil ? 1 : (ancho < 900 ? 2 : 3);

            return SingleChildScrollView(
              padding: EdgeInsets.all(esMovil ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Selecciona el tipo de reporte',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  GridView.count(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: esMovil ? 2.05 : 1.8,
                    children: [
                      _ReporteCard(
                        icon: Icons.point_of_sale_outlined,
                        titulo: 'Ventas',
                        subtitulo: 'Reporte de ventas por período,\ncajero, producto, forma de pago',
                        color: Colors.green.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const VentasReportScreen()),
                        ),
                      ),
                      _ReporteCard(
                        icon: Icons.inventory_2_outlined,
                        titulo: 'Movimientos',
                        subtitulo: 'Entradas, salidas, ajustes,\ntransferencias y descargos',
                        color: Colors.blue.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MovimientosReportScreen()),
                        ),
                      ),
                      _ReporteCard(
                        icon: Icons.analytics_outlined,
                        titulo: 'Estadísticas',
                        subtitulo: 'KPIs, tendencias, top productos,\nestacionalidad, rendimiento',
                        color: Colors.deepOrange.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EstadisticasReportScreen()),
                        ),
                      ),
                      _ReporteCard(
                        icon: Icons.history_outlined,
                        titulo: 'Cierres de Caja',
                        subtitulo: 'Historial de cierres,\nresumen por turno, exportar',
                        color: Colors.purple.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CierresHistorialScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReporteCard extends StatelessWidget {
  const _ReporteCard({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final esCompacto = constraints.maxWidth < 380;

        return Card(
          elevation: 2,
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: color.withValues(alpha: 0.1),
            highlightColor: color.withValues(alpha: 0.05),
            child: esCompacto ? _buildCompacto(context, scheme) : _buildVertical(context, scheme),
          ),
        );
      },
    );
  }

  Widget _buildVertical(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              subtitulo,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.25,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Ver reporte',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompacto(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: color),
        ],
      ),
    );
  }
}