import 'package:flutter/material.dart';

import '../../data/pos_comanda_models.dart';

/// Diálogo para asignar (total o parcialmente) un ítem a un cliente.
/// Devuelve la cantidad y el número de cliente elegido, o `null` si cancela.
Future<({int cantidad, int cliente})?> showCuentaItemDialog(
  BuildContext context, {
  required ComandaItem item,
  required List<int> clientes,
}) {
  return showDialog<({int cantidad, int cliente})>(
    context: context,
    builder: (ctx) => _CuentaItemDialog(item: item, clientes: clientes),
  );
}

class _CuentaItemDialog extends StatefulWidget {
  const _CuentaItemDialog({required this.item, required this.clientes});
  final ComandaItem item;
  final List<int> clientes;

  @override
  State<_CuentaItemDialog> createState() => _CuentaItemDialogState();
}

class _CuentaItemDialogState extends State<_CuentaItemDialog> {
  late int _cantidad = widget.item.cantidad;
  late int _cliente = widget.item.cuenta;

  int get _nuevo => widget.clientes.isEmpty
      ? 1
      : widget.clientes.reduce((a, b) => a > b ? a : b) + 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clienteEsNuevo = !widget.clientes.contains(_cliente);
    return AlertDialog(
      title: const Text('Asignar a cliente'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.nombre,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '\$${widget.item.precio.toStringAsFixed(2)} · ${widget.item.cantidad} disponible${widget.item.cantidad == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in widget.clientes)
                  ChoiceChip(
                    label: Text('Cliente $c'),
                    selected: _cliente == c,
                    onSelected: (_) => setState(() => _cliente = c),
                  ),
                ChoiceChip(
                  label: Text('+ Cliente $_nuevo'),
                  selected: clienteEsNuevo,
                  onSelected: (_) =>
                      setState(() => _cliente = _nuevo),
                ),
              ],
            ),
            if (widget.item.cantidad > 1) ...[
              const SizedBox(height: 16),
              const Text('Cantidad',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    onPressed: _cantidad > 1
                        ? () => setState(() => _cantidad--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_cantidad',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: _cantidad < widget.item.cantidad
                        ? () => setState(() => _cantidad++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF4CAF50)),
                  ),
                  const Spacer(),
                  Text('de ${widget.item.cantidad}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (cantidad: _cantidad, cliente: _cliente)),
          child: const Text('Asignar'),
        ),
      ],
    );
  }
}
