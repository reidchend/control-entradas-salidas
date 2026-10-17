import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Elección de cobro cuando la comanda tiene sub-cuentas ("clientes").
/// Devuelve `(todo: true)` para cobrar la comanda completa, `(todo: false,
/// cliente: n)` para cobrar solo a ese cliente, o `null` si se cancela.
Future<({bool todo, int? cliente})?> showCobroPorClienteDialog(
  BuildContext context, {
  required double total,
  required double tasa,
  required String ubicacion,
  required List<({int cliente, double total})> clientes,
}) {
  return showDialog<({bool todo, int? cliente})>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Cobrar'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_bar_outlined,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(ubicacion,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.receipt_long,
                      color: Color(0xFF4CAF50)),
                  title: const Text('Toda la comanda',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${clientes.length} clientes'),
                  trailing: Text('\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4CAF50))),
                  onTap: () => Navigator.pop(ctx, (todo: true, cliente: null)),
                ),
                const Divider(),
                for (final c in clientes)
                  ListTile(
                    leading: const Icon(Icons.person_outline,
                        color: Color(0xFF7E3FF2)),
                    title: Text('Cliente ${c.cliente}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text('\$${c.total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.pop(
                        ctx, (todo: false, cliente: c.cliente)),
                  ),
                if (tasa > 0) ...[
                  const SizedBox(height: 4),
                  Text('Tasa ${formatearTasa(tasa)} Bs/\$',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
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
