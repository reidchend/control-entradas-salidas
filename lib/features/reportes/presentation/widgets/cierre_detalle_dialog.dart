import 'package:flutter/material.dart';

import '../../../../core/models/pos_cierre_models.dart';
import '../../../../core/utils/modal_sizing.dart';
import '../../../pos/data/reporte_cierre_texto.dart';
import '../widgets/reporte_detallado_view.dart';
import '../widgets/reporte_simple_view.dart';

/// Diálogo con el detalle completo de un cierre: datos de caja, reporte
/// simple y reporte detallado, con opción de reenviar por WhatsApp.
class CierreDetalleDialog extends StatelessWidget {
  const CierreDetalleDialog({
    super.key,
    required this.cierre,
    required this.onReenviar,
  });

  final CierreCaja cierre;
  final VoidCallback onReenviar;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final cajero = cierre.usuarioNombre.isNotEmpty
        ? cierre.usuarioNombre
        : 'Cajero sin nombre';

    return AlertDialog(
      title: Text('$cajero · Turno #${cierre.sesionId}'),
      content: SizedBox(
        width: modalContentWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fila(label: 'Cajero', valor: cajero),
              _Fila(
                  label: 'Apertura',
                  valor: fmtFechaCierre(cierre.abiertaEn)),
              _Fila(label: 'Cierre', valor: fmtFechaCierre(cierre.cerradaEn)),
              _Fila(
                  label: 'Duración',
                  valor: duracionCierreTexto(cierre)),
              const Divider(),
              _Fila(
                  label: 'Caja Inicial',
                  valor: '\$${cierre.cajaInicial.toStringAsFixed(2)}',
                  bold: true),
              _Fila(
                  label: 'Total Ventas',
                  valor: '\$${cierre.totalVentas.toStringAsFixed(2)}'),
              _Fila(
                  label: 'Caja Final',
                  valor: '\$${cierre.cajaFinal.toStringAsFixed(2)}',
                  bold: true,
                  color: Colors.green),
              const Divider(),
              Text('Reporte simple', style: texto.titleMedium),
              const SizedBox(height: 8),
              ReporteSimpleView(reporte: cierre.reporteSimple),
              const SizedBox(height: 16),
              Text('Reporte detallado', style: texto.titleMedium),
              const SizedBox(height: 2),
              Text('Consumo de ingredientes y stock al cierre',
                  style: texto.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              ReporteDetalladoView(reporte: cierre.reporteDetallado),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.forward_to_inbox, size: 18),
          label: const Text('Reenviar'),
          onPressed: () {
            Navigator.pop(context);
            onReenviar();
          },
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.label,
    required this.valor,
    this.bold = false,
    this.color,
  });

  final String label;
  final String valor;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: texto.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(valor,
                textAlign: TextAlign.right,
                style: texto.bodyMedium?.copyWith(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                    color: color)),
          ),
        ],
      ),
    );
  }
}
