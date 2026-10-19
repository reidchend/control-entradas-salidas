import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Banner persistente de error con botón de reintentar.
///
/// Se muestra cuando una sección de la vista no pudo cargar. En vez de dejar
/// el área gris y vacía (como pasaba con el aviso efímero, que desaparecía a
/// los segundos), el mensaje queda hasta que el usuario reintente o cierre la
/// vista, indica qué sección falló y permite copiar el detalle técnico para
/// reportarlo.
class AvisoErrorBanner extends StatelessWidget {
  const AvisoErrorBanner({
    super.key,
    required this.mensaje,
    required this.onReintentar,
    this.detalle = '',
  });

  /// Qué secciones no cargaron (ej. «KPIs, ventas por hora»).
  final String mensaje;

  /// Texto técnico del fallo, para copiar y reportar. Puede ir vacío.
  final String detalle;

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: scheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No se pudo cargar: $mensaje.\n'
                      'El resto de la vista muestra los datos disponibles.',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  if (detalle.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _copiar(context),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar detalle'),
                    ),
                  TextButton.icon(
                    onPressed: onReintentar,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copiar(BuildContext context) {
    Clipboard.setData(
      ClipboardData(text: 'Estadísticas no cargó: $mensaje\n\n$detalle'),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Detalle copiado al portapapeles'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }
}
