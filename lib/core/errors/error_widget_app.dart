import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Reemplaza el cuadro gris que Flutter dibuja cuando un widget falla.
///
/// En **release** (lo que se instala en los equipos) un error al construir un
/// widget no muestra el stack: Flutter lo tapa con un `ErrorWidget`, que se ve
/// como un rectángulo gris sin ninguna explicación. Eso hacía imposible
/// distinguir "esta sección se quedó sin datos" de "esta sección se rompió":
/// las dos cosas se veían igual, como un cuadro gris.
///
/// Acá se cambia por un aviso legible —mismo lenguaje visual que el resto de la
/// app— con el mensaje de la excepción, para que el problema se pueda reportar.
/// En **debug** no se toca nada: ahí conviene el panel rojo con el stack
/// completo, que es el que usa el desarrollador.
void instalarErrorWidgetDeApp() {
  if (!kReleaseMode) return;
  ErrorWidget.builder = (details) => _AvisoWidgetRoto(details: details);
}

class _AvisoWidgetRoto extends StatelessWidget {
  const _AvisoWidgetRoto({required this.details});

  final FlutterErrorDetails details;

  /// Mensaje corto: en release `exceptionAsString()` trae solo la excepción,
  /// pero igual se recorta para que un texto enorme no rompa el layout.
  String get _mensaje {
    final texto = details.exceptionAsString().trim();
    return texto.length > 400 ? '${texto.substring(0, 400)}…' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // `Directionality` explícito: el aviso puede sustituir a un widget que
    // estaba arriba del `MaterialApp`, donde ya no habría dirección de texto.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: scheme.errorContainer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No se pudo dibujar esta parte de la pantalla',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (_mensaje.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _mensaje,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
