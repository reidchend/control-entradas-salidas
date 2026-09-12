import 'package:flutter/material.dart';

import '../../../../core/utils/modal_sizing.dart';
import '../../../../core/utils/web_utils.dart';

/// Vista previa del ticket de comanda (port de la impresión de `printer.py`
/// adaptada a web): muestra el ticket en monospace de 32 columnas y permite
/// imprimirlo con el diálogo del navegador (única vía de impresión en web).
Future<void> showTicketPreview(
  BuildContext context, {
  required List<String> lineas,
  String titulo = 'Ticket de comanda',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => TicketPreviewDialog(lineas: lineas, titulo: titulo),
  );
}

class TicketPreviewDialog extends StatelessWidget {
  const TicketPreviewDialog({
    super.key,
    required this.lineas,
    this.titulo = 'Ticket de comanda',
  });

  final List<String> lineas;
  final String titulo;

  /// Imprime el ticket con el diálogo del navegador (solo web).
  void _imprimirWeb() {
    printHtml(lineas.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: modalContentWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  lineas.isEmpty ? ' ' : lineas.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.25,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'En web, la impresión usa el diálogo del navegador.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: _imprimirWeb,
          icon: const Icon(Icons.print),
          label: const Text('Imprimir'),
        ),
      ],
    );
  }
}
