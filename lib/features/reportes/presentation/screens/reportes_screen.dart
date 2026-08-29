import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ventas_report_screen.dart';
import 'movimientos_report_screen.dart';
import 'estadisticas_report_screen.dart';

/// Pantalla principal de Reportes: dashboard con botones grandes.
class ReportesScreen extends ConsumerWidget {
  const ReportesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(scheme),
            Expanded(
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
                          childAspectRatio: esMovil ? 2.2 : 1.8,
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
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.assessment_outlined, size: 28, color: scheme.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reportes',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                'Análisis de ventas, movimientos y KPIs',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
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

    return Card(
      elevation: 2,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                titulo,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitulo,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
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
        ),
      ),
    );
  }
}