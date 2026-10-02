import 'package:flutter/material.dart';

/// Confirmación sí/no para acciones que no se pueden deshacer.
///
/// Vive acá y no repetido en cada panel porque la forma es siempre la misma:
/// título, mensaje, cancelar y la acción en rojo. Devuelve `true` solo si se
/// confirma.
Future<bool> showConfirmarDialog(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String accion,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: Text(accion),
        ),
      ],
    ),
  ).then((v) => v == true);
}
