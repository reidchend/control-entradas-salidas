import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/modal_sizing.dart';

/// Diálogo que muestra el detalle de un error y permite copiarlo al
/// portapapeles. Reutilizable para errores de sync, red, etc.
Future<void> showErrorDetailsDialog(
  BuildContext context, {
  required String titulo,
  required String detalle,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ErrorDetailsDialog(titulo: titulo, detalle: detalle),
  );
}

class _ErrorDetailsDialog extends StatelessWidget {
  const _ErrorDetailsDialog({required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(titulo)),
        ],
      ),
      content: SizedBox(
        width: modalContentWidth(context),
        child: SingleChildScrollView(
          child: SelectableText(
            detalle,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: detalle));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error copiado al portapapeles')),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiar'),
        ),
      ],
    );
  }
}