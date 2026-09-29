import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../widgets/db_config_panel.dart';

/// Abre el panel de configuración de base de datos en un diálogo.
///
/// Vive en su propio archivo porque lo necesitan pantallas que están
/// *antes* del login: con la base sin configurar no se puede autenticar, así
/// que la única forma de salir del círculo es que el login ofrezca esta
/// pantalla.
///
/// Devuelve `true` si el usuario guardó una configuración utilizable.
Future<bool> showDbConfigDialog(BuildContext context) async {
  if (kIsWeb) {
    // En web la conexión la resuelve el proxy del servidor: no hay nada que
    // configurar en el dispositivo.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'En web la conexión la resuelve el proxy del servidor. '
          'Esta configuración aplica a Windows y Android.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
    return false;
  }

  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Expanded(child: DbConfigPanel()),
          ],
        ),
      ),
    ),
  );
  return true;
}
