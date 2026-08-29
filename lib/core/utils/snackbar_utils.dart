import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Utilidades para SnackBars con acción de copiar al portapapeles.

/// Muestra un SnackBar de error con botón "Copiar" para copiar el mensaje.
void showErrorSnackBar(
  BuildContext context,
  String mensaje, {
  Duration duracion = const Duration(seconds: 5),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(mensaje),
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      duration: duracion,
      action: SnackBarAction(
        label: 'Copiar',
        textColor: Theme.of(context).colorScheme.onErrorContainer,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: mensaje));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Mensaje copiado al portapapeles'),
              duration: const Duration(seconds: 2),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
        },
      ),
    ),
  );
}

/// Muestra un SnackBar informativo con botón "Copiar" opcional.
void showInfoSnackBar(
  BuildContext context,
  String mensaje, {
  Duration duracion = const Duration(seconds: 4),
  bool conCopiar = true,
  Color? backgroundColor,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(mensaje),
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.primaryContainer,
      duration: duracion,
      action: conCopiar
          ? SnackBarAction(
              label: 'Copiar',
              textColor: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: mensaje));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Mensaje copiado al portapapeles'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  ),
                );
              },
            )
          : null,
    ),
  );
}

/// Muestra un SnackBar de éxito con botón "Copiar" opcional.
void showSuccessSnackBar(
  BuildContext context,
  String mensaje, {
  Duration duracion = const Duration(seconds: 3),
  bool conCopiar = true,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(mensaje),
      backgroundColor: Colors.green.shade700,
      duration: duracion,
      action: conCopiar
          ? SnackBarAction(
              label: 'Copiar',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: mensaje));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mensaje copiado al portapapeles'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            )
          : null,
    ),
  );
}