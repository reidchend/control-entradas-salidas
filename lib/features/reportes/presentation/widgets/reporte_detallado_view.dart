import 'package:flutter/material.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../pos/data/reporte_cierre_texto.dart';

/// Vista legible del reporte detallado: una tarjeta por ingrediente con su
/// consumo y stock final, expandible para ver el uso por plato.
class ReporteDetalladoView extends StatelessWidget {
  const ReporteDetalladoView({super.key, required this.reporte});

  final ReporteDetallado reporte;

  @override
  Widget build(BuildContext context) {
    if (reporte.desgloses.isEmpty) {
      return Text('Sin desglose de ingredientes registrado',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    return Column(
      children: [
        for (final d in reporte.desgloses) ...[
          _IngredienteCard(d: d),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _IngredienteCard extends StatelessWidget {
  const _IngredienteCard({required this.d});

  final DesgloseIngrediente d;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    final resumen = Row(
      children: [
        Expanded(
          child: Text(d.ingrediente,
              style:
                  texto.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Text('Consumido: ${fmtNumCierre(d.totalConsumido)}',
            style:
                texto.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('Stock ${fmtNumCierre(d.stockFinal)}',
              style: texto.labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer)),
        ),
      ],
    );

    if (d.usos.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: resumen,
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        title: resumen,
        dense: true,
        childrenPadding:
            const EdgeInsets.only(left: 16, right: 12, bottom: 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final u in d.usos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text('· ${u.plato}',
                        style: texto.bodySmall),
                  ),
                  Text(fmtNumCierre(u.cantidad),
                      style: texto.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
