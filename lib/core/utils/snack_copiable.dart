import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Muestra una notificación (SnackBar) cuyo texto se puede **seleccionar y
/// copiar**, útil para reportar errores de base de datos, red o impresión.
///
/// Incluye un botón "Copiar" que manda el mensaje completo al portapapeles y
/// un ícono de cierre. Usa colores del tema, así que se lee en claro y oscuro.
void mostrarSnackCopiable(
  BuildContext context,
  String mensaje, {
  bool error = false,
  Duration duration = const Duration(seconds: 10),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final scheme = Theme.of(context).colorScheme;
  final fondo = error ? scheme.errorContainer : scheme.secondaryContainer;
  final frente = error ? scheme.onErrorContainer : scheme.onSecondaryContainer;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: fondo,
      duration: duration,
      showCloseIcon: true,
      closeIconColor: frente,
      content: SelectableText(
        mensaje,
        style: TextStyle(color: frente, fontSize: 13),
      ),
      action: SnackBarAction(
        label: 'Copiar',
        textColor: frente,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: mensaje));
        },
      ),
    ),
  );
}
