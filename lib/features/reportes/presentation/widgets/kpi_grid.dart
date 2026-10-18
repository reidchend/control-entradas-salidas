import 'package:flutter/material.dart';

/// Dato de una tarjeta de KPI (título, valor ya formateado, ícono, color).
class KpiDato {
  const KpiDato(this.titulo, this.valor, this.icono, this.color);
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
}

/// Grilla responsiva de tarjetas de KPI (3 columnas en escritorio,
/// 2 en tabletas, 1 en móvil).
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.kpis});

  final List<KpiDato> kpis;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 900
            ? 3
            : (constraints.maxWidth > 520 ? 2 : 1);
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: [for (final kpi in kpis) KpiCard(data: kpi)],
        );
      },
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.data});
  final KpiDato data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(data.icono, size: 28, color: data.color),
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                data.valor,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: data.color,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data.titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
