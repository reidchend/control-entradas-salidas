import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Diálogo para elegir con qué otra comanda fusionar la actual. Devuelve la
/// comanda elegida (la que será absorbida) o `null` si se cancela.
Future<ComandaActiva?> showFusionarComandaDialog(
  BuildContext context, {
  required List<ComandaActiva> otras,
  required String etiquetaActual,
}) {
  return showDialog<ComandaActiva>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Fusionar comanda'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Los productos de la comanda elegida se pasan a '
                  '"$etiquetaActual" y su casilla queda libre.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (otras.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No hay otras comandas activas.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                for (final c in otras)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      c.mesaId != null ? Icons.restaurant : Icons.hotel,
                      color: c.mesaId != null
                          ? const Color(0xFFEF5350)
                          : const Color(0xFF4FC3F7),
                    ),
                    title: Text(c.etiqueta,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${c.items} item${c.items == 1 ? '' : 's'} · \$${c.total.toStringAsFixed(2)}'),
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      );
    },
  );
}
