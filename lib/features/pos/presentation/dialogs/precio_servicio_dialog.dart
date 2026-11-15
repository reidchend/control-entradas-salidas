import 'package:flutter/material.dart';

/// Diálogo para editar el precio de un servicio antes de agregarlo a la
/// comanda. Se usa para servicios como delivery, cargo por servicio, etc.,
/// cuyo monto no es fijo y el usuario debe introducirlo manualmente.
///
/// Retorna el precio ingresado, o `null` si el usuario cancela.
Future<double?> showPrecioServicioDialog(
  BuildContext context, {
  required String nombreServicio,
  double precioSugerido = 0,
}) async {
  final ctrl = TextEditingController(
    text: precioSugerido == 0 ? '' : precioSugerido.toStringAsFixed(2),
  );
  final resultado = await showDialog<double>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Precio del servicio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${nombreServicio}'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monto (\$)',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final monto = double.tryParse(ctrl.text.trim());
            if (monto == null || monto < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ingrese un monto válido')),
              );
              return;
            }
            Navigator.of(context).pop(monto);
          },
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return resultado;
}
