import 'package:flutter/material.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../pos/data/reporte_cierre_texto.dart';

/// Vista legible del reporte simple: líneas agrupadas por categoría con
/// columnas alineadas (nombre / cantidad x precio / total) y subtotales.
class ReporteSimpleView extends StatelessWidget {
  const ReporteSimpleView({super.key, required this.reporte});

  final ReporteSimple reporte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    // Agrupar por categoría respetando el orden de aparición.
    final porCategoria = <String, List<LineaVenta>>{};
    for (final l in reporte.lineas) {
      porCategoria.putIfAbsent(l.categoria, () => []).add(l);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in porCategoria.entries) ...[
          _CategoriaCard(
            categoria: entry.key,
            items: entry.value,
            scheme: scheme,
            texto: texto,
          ),
          const SizedBox(height: 8),
        ],
        if (reporte.contornos.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Contornos servidos',
              style: texto.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final cn in reporte.contornos)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                      '${cn.nombre} x ${fmtNumCierre(cn.cantidad)}',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL GENERAL',
                  style: texto.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer)),
              Text('\$${fmtNumCierre(reporte.totalGeneral)}',
                  style: texto.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoriaCard extends StatelessWidget {
  const _CategoriaCard({
    required this.categoria,
    required this.items,
    required this.scheme,
    required this.texto,
  });

  final String categoria;
  final List<LineaVenta> items;
  final ColorScheme scheme;
  final TextTheme texto;

  @override
  Widget build(BuildContext context) {
    final subtotal = items.fold<double>(0, (s, l) => s + l.total);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(categoria.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: texto.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant)),
                ),
                Text('Subtotal \$${fmtNumCierre(subtotal)}',
                    style: texto.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                for (final l in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(l.nombre,
                              style: texto.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500)),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(
                            '${fmtNumCierre(l.cantidad)} x \$${fmtNumCierre(l.precioUnitario)}',
                            textAlign: TextAlign.right,
                            style: texto.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            '\$${fmtNumCierre(l.total)}',
                            textAlign: TextAlign.right,
                            style: texto.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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
